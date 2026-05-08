#!/bin/bash
# =============================================================================
# TIBCO Platform on EKS — Control Plane Clean-up Script
#
# Purpose:
#   Removes the TIBCO Control Plane and all associated AWS resources from
#   the EKS cluster in safe deletion order.
#
# Deletion order (order matters — reversing it leaves orphaned resources):
#   1. TibcoResourceSet CRs         — finalizers; must be removed first
#   2. TIBCO CP Helm release        — cleans K8s objects in CP namespace
#   3. CP Ingress Helm releases     — removes ALB ingress rules for CP domains
#   4. External DNS                 — stops automated Route 53 management
#   5. Crossplane claims (if used)  — Crossplane deletes EFS + Aurora + IAM role
#   6. Crossplane components        — providers, configs, compositions, crossplane
#   7. Remaining Helm releases      — AWS LBC, cert-manager, metrics-server, etc.
#   8. EFS file system (CLI method) — delete mount targets then file system
#   9. RDS DB instance (CLI method) — delete instance + subnet group + SGs
#  10. Crossplane IAM role          — detach policy then delete role
#  11. EKS cluster (optional)       — controlled by TP_DELETE_CLUSTER
#
# Usage:
#   source scripts/env.sh          # load environment variables
#   cd scripts/
#   ./clean-up-control-plane.sh                  # interactive (prompts for confirmation)
#   ./clean-up-control-plane.sh --no-confirm     # skip confirmation (CI/CD use)
#   ./clean-up-control-plane.sh --dry-run        # show what will be deleted, no action
#
# Required variables (from scripts/env.sh):
#   TP_CLUSTER_NAME        — EKS cluster name
#   TP_CLUSTER_REGION      — AWS region
#   TP_CROSSPLANE_ENABLED  — "true" or "false" (whether Crossplane was used)
#   TP_DELETE_CLUSTER      — "true" to delete EKS cluster; "false" = charts + AWS resources only
#   CP_INSTANCE_ID         — Control Plane instance ID (namespace = ${CP_INSTANCE_ID}-ns)
#
# Optional variables:
#   CP_RESOURCE_PREFIX     — Required when TP_CROSSPLANE_ENABLED=true (default: platform)
#   TP_CROSSPLANE_ROLE     — Crossplane IAM role name (default: ${TP_CLUSTER_NAME}-crossplane-${TP_CLUSTER_REGION})
#   TP_STORAGE_CLASS_EFS   — EFS StorageClass name (default: efs-sc)
#   TP_DELETE_TIBCO_RESOURCE_SET — Delete TibcoResourceSet CRs (default: true)
#
# Source: https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks/scripts/clean-up-control-plane.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# COLOR OUTPUT
# =============================================================================
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC}    $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
log_section() { echo ""; echo -e "${BOLD}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
log_dry()     { echo -e "${YELLOW}[DRY-RUN]${NC} $*"; }

# =============================================================================
# FLAGS
# =============================================================================
DRY_RUN=false
NO_CONFIRM=false

for arg in "$@"; do
  case "${arg}" in
    --dry-run)    DRY_RUN=true ;;
    --no-confirm) NO_CONFIRM=true ;;
    --help|-h)
      grep "^#" "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

run() {
  if [ "${DRY_RUN}" = "true" ]; then
    log_dry "$*"
  else
    eval "$@"
  fi
}

# =============================================================================
# VARIABLE SETUP AND VALIDATION
# =============================================================================
log_section "Loading Environment Variables"

# Try to source env.sh from the scripts directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/env.sh" ]; then
  log_info "Sourcing ${SCRIPT_DIR}/env.sh"
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/env.sh"
fi

export TP_CLUSTER_NAME="${TP_CLUSTER_NAME:-}"
export TP_CLUSTER_REGION="${TP_CLUSTER_REGION:-${AWS_REGION:-}}"
export TP_STORAGE_CLASS_EFS="${TP_STORAGE_CLASS_EFS:-efs-sc}"
export TP_CROSSPLANE_ENABLED="${TP_CROSSPLANE_ENABLED:-false}"
export TP_DELETE_CLUSTER="${TP_DELETE_CLUSTER:-false}"
export TP_DELETE_TIBCO_RESOURCE_SET="${TP_DELETE_TIBCO_RESOURCE_SET:-true}"
export CP_INSTANCE_ID="${CP_INSTANCE_ID:-cp1}"
export CP_RESOURCE_PREFIX="${CP_RESOURCE_PREFIX:-platform}"
export CP_NAMESPACE="${CP_INSTANCE_ID}-ns"

_default_role="${TP_CLUSTER_NAME:-}-crossplane-${TP_CLUSTER_REGION:-}"
export TP_CROSSPLANE_ROLE="${TP_CROSSPLANE_ROLE:-${_default_role}}"

# Validate required variables
ERRORS=0
check_var() {
  if [ -z "${!1:-}" ]; then
    log_error "Required variable \$$1 is not set. Set it in scripts/env.sh or export it before running."
    ERRORS=$((ERRORS + 1))
  fi
}

check_var TP_CLUSTER_NAME
check_var TP_CLUSTER_REGION
[ "${ERRORS}" -gt 0 ] && exit 1

if [ "${TP_CROSSPLANE_ENABLED}" = "true" ] && [ -z "${CP_RESOURCE_PREFIX}" ]; then
  log_error "CP_RESOURCE_PREFIX is required when TP_CROSSPLANE_ENABLED=true"
  exit 1
fi

# =============================================================================
# PRE-FLIGHT: SHOW DELETION PLAN
# =============================================================================
log_section "Control Plane Clean-up Plan"

echo ""
echo "  Cluster         : ${TP_CLUSTER_NAME} (${TP_CLUSTER_REGION})"
echo "  CP Namespace    : ${CP_NAMESPACE}"
echo "  CP Instance ID  : ${CP_INSTANCE_ID}"
echo "  EFS StorageClass: ${TP_STORAGE_CLASS_EFS}"
echo "  Crossplane      : ${TP_CROSSPLANE_ENABLED}"
[ "${TP_CROSSPLANE_ENABLED}" = "true" ] && echo "  CP Prefix       : ${CP_RESOURCE_PREFIX}"
[ "${TP_CROSSPLANE_ENABLED}" = "true" ] && echo "  Crossplane Role : ${TP_CROSSPLANE_ROLE}"
echo "  Delete Cluster  : ${TP_DELETE_CLUSTER}"
echo ""

if [ "${DRY_RUN}" = "true" ]; then
  log_warn "DRY-RUN mode — no resources will be deleted"
fi

if [ "${NO_CONFIRM}" = "false" ] && [ "${DRY_RUN}" = "false" ]; then
  echo -e "${RED}${BOLD}WARNING: This will permanently delete the TIBCO Control Plane and AWS resources.${NC}"
  echo ""
  echo "Before proceeding, confirm:"
  echo "  1. All Data Planes have been deleted from the CP UI"
  echo "  2. You have backed up session-keys and cporch-encryption-secret to Azure Key Vault"
  echo "  3. TP_DELETE_CLUSTER=${TP_DELETE_CLUSTER} — review if this is correct"
  echo ""
  read -r -p "Type 'yes' to continue: " CONFIRM
  if [ "${CONFIRM}" != "yes" ]; then
    log_info "Aborted."
    exit 0
  fi
fi

# =============================================================================
# STEP 1: DELETE TibcoResourceSet CRs
# Why: TibcoResourceSet CRs hold finalizers that keep K8s namespaces from
# terminating. Deleting them first prevents namespace deletion from hanging.
# =============================================================================
log_section "Step 1: Delete TibcoResourceSet CRs"

if [ "${TP_DELETE_TIBCO_RESOURCE_SET}" = "true" ]; then
  if kubectl get crd tibcoresourcesets.platform.tibco.com &>/dev/null; then
    _namespaces=$(kubectl get tibcoresourceset -A --no-headers \
      -o custom-columns=":metadata.namespace" 2>/dev/null | sort -u | tr '\n' ' ')
    if [ -n "${_namespaces}" ]; then
      for _ns in ${_namespaces}; do
        log_info "Deleting TibcoResourceSet CRs in namespace ${_ns}..."
        run "kubectl delete tibcoresourceset -n '${_ns}' --all --ignore-not-found"
      done
      if [ "${DRY_RUN}" = "false" ]; then
        log_info "Waiting 2 minutes for TibcoResourceSet finalizers to clear..."
        sleep 120
      fi
    else
      log_ok "No TibcoResourceSet CRs found"
    fi
  else
    log_ok "TibcoResourceSet CRD not found — skipping"
  fi
else
  log_info "TP_DELETE_TIBCO_RESOURCE_SET=false — skipping TibcoResourceSet deletion"
fi

# =============================================================================
# STEP 2: UNINSTALL TIBCO CONTROL PLANE HELM RELEASE
# Why: Helm's pre-delete hooks cleanly remove CP-specific K8s resources
# (finalizers, webhooks, CRDs) before namespace deletion.
# The tibco-platform release has no layer label — it must be deleted first.
# =============================================================================
log_section "Step 2: Uninstall TIBCO Control Plane Helm Release"

_cp_releases=$(helm ls -n "${CP_NAMESPACE}" -a -o json 2>/dev/null \
  | jq -r '.[].name' 2>/dev/null || true)

if [ -n "${_cp_releases}" ]; then
  for _release in ${_cp_releases}; do
    log_info "Uninstalling Helm release: ${_release} (namespace: ${CP_NAMESPACE})"
    run "helm uninstall '${_release}' -n '${CP_NAMESPACE}' --wait --timeout 10m || true"
  done
else
  log_ok "No Helm releases found in namespace ${CP_NAMESPACE}"
fi

# Wait for pods in CP namespace to terminate before proceeding
if [ "${DRY_RUN}" = "false" ]; then
  log_info "Waiting for CP namespace pods to terminate (up to 3 minutes)..."
  kubectl wait --for=delete pods --all -n "${CP_NAMESPACE}" --timeout=180s 2>/dev/null || true
fi

# =============================================================================
# STEP 3: DELETE CP NAMESPACE
# =============================================================================
log_section "Step 3: Delete CP Namespace"

if kubectl get namespace "${CP_NAMESPACE}" &>/dev/null; then
  log_info "Deleting namespace ${CP_NAMESPACE}..."
  run "kubectl delete namespace '${CP_NAMESPACE}' --timeout=120s || true"
else
  log_ok "Namespace ${CP_NAMESPACE} already removed"
fi

# =============================================================================
# STEP 4: DELETE INGRESS OBJECTS (triggers ALB deletion)
# Why: The AWS Load Balancer Controller watches Ingress objects. Deleting
# ingresses first signals the LBC to de-provision ALB resources (target groups,
# listeners, ALB itself). Waiting ensures the ALB is removed before the LBC
# itself is deleted (otherwise AWS resources become orphaned and charged).
# =============================================================================
log_section "Step 4: Delete Ingress Objects (trigger ALB de-provisioning)"

_ingress_count=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l)
if [ "${_ingress_count}" -gt 0 ]; then
  log_info "Deleting ${_ingress_count} Ingress object(s) across all namespaces..."
  run "kubectl delete ingress -A --all --ignore-not-found"
  if [ "${DRY_RUN}" = "false" ]; then
    log_info "Waiting 2 minutes for AWS ALB to be de-provisioned..."
    sleep 120
  fi
else
  log_ok "No Ingress objects found"
fi

# =============================================================================
# STEP 5: UNINSTALL INGRESS HELM RELEASES (Nginx, Traefik, tunnel)
# =============================================================================
log_section "Step 5: Uninstall Ingress Controller Helm Releases"

for _release in dp-config-aws-nginx dp-config-aws-tunnel dp-config-aws-traefik dp-config-aws-tunnel-traefik; do
  if helm ls -n ingress-system 2>/dev/null | grep -q "^${_release}"; then
    log_info "Uninstalling ${_release}..."
    run "helm uninstall '${_release}' -n ingress-system || true"
  else
    log_info "${_release} not found — skipping"
  fi
done

# =============================================================================
# STEP 6: UNINSTALL EXTERNAL DNS
# Why: External DNS continuously reconciles Route 53 records. Removing it
# before uninstalling other charts prevents it from re-creating records that
# have already been deleted during cleanup.
# =============================================================================
log_section "Step 6: Uninstall External DNS"

if helm ls -n external-dns-system 2>/dev/null | grep -q "external-dns"; then
  log_info "Uninstalling external-dns..."
  run "helm uninstall external-dns -n external-dns-system || true"
else
  log_ok "external-dns not found — skipping"
fi

# =============================================================================
# STEP 7: UNINSTALL CROSSPLANE CLAIMS AND COMPONENTS (if Crossplane was used)
# Why: Crossplane claims must be deleted before the Crossplane operators are
# removed, otherwise the finalizer-based deletion controllers are gone and
# the EFS/RDS/IAM resources will never be cleaned up by Crossplane.
# Deletion order within Crossplane: claims → compositions → configs → providers → crossplane
# =============================================================================
if [ "${TP_CROSSPLANE_ENABLED}" = "true" ]; then
  log_section "Step 7: Uninstall Crossplane Claims and Components"

  log_info "Uninstalling Crossplane claims (this deletes EFS, Aurora, and IAM role via Crossplane)..."
  run "helm uninstall crossplane-claims-aws -n '${CP_NAMESPACE}' 2>/dev/null || true"

  if [ "${DRY_RUN}" = "false" ]; then
    log_info "Waiting for Crossplane to delete AWS resources (EFS, Aurora cluster)..."
    log_info "Aurora deletion typically takes 5-20 minutes — waiting up to 25 minutes..."
    _waited=0
    while [ ${_waited} -lt 1500 ]; do
      _aurora=$(kubectl get DBCluster.rds.aws.crossplane.io \
        -o name 2>/dev/null | grep -c "${CP_RESOURCE_PREFIX}-aurora-cluster" || true)
      [ "${_aurora}" -eq 0 ] && { log_ok "Aurora cluster deleted by Crossplane"; break; }
      log_info "  Aurora still deleting... (${_waited}s elapsed)"
      sleep 60
      _waited=$((_waited + 60))
    done
  fi

  for _layer in 3 2 1 0; do
    _releases=$(helm ls --selector "layer=${_layer}" -a -A -o json 2>/dev/null \
      | jq -r '.[] | "\(.name) \(.namespace)"' 2>/dev/null || true)
    if [ -n "${_releases}" ]; then
      while IFS= read -r _line; do
        [ -z "${_line}" ] && continue
        _rel=$(echo "${_line}" | awk '{print $1}')
        _ns=$(echo "${_line}" | awk '{print $2}')
        log_info "Uninstalling Crossplane component: ${_rel} (layer ${_layer}, ns: ${_ns})"
        run "helm uninstall '${_rel}' -n '${_ns}' || true"
        [ "${DRY_RUN}" = "false" ] && sleep 30
      done <<< "${_releases}"
    fi
  done
else
  log_section "Step 7: Crossplane — Skipped (TP_CROSSPLANE_ENABLED=false)"
fi

# =============================================================================
# STEP 8: UNINSTALL REMAINING HELM RELEASES (AWS LBC, cert-manager, etc.)
# Process: unlabeled releases first, then labeled releases from highest to lowest layer.
# =============================================================================
log_section "Step 8: Uninstall Remaining Helm Releases"

log_info "Uninstalling releases with no layer label..."
_unlabeled=$(helm ls --selector '!layer' -a -A -o json 2>/dev/null \
  | jq -r '.[] | "\(.name) \(.namespace)"' 2>/dev/null || true)
while IFS= read -r _line; do
  [ -z "${_line}" ] && continue
  _rel=$(echo "${_line}" | awk '{print $1}')
  _ns=$(echo "${_line}" | awk '{print $2}')
  log_info "Uninstalling: ${_rel} (ns: ${_ns})"
  run "helm uninstall '${_rel}' -n '${_ns}' || true"
  [ "${DRY_RUN}" = "false" ] && sleep 30
done <<< "${_unlabeled}"

for _layer in 4 3 2 1 0; do
  _labeled=$(helm ls --selector "layer=${_layer}" -a -A -o json 2>/dev/null \
    | jq -r '.[] | "\(.name) \(.namespace)"' 2>/dev/null || true)
  while IFS= read -r _line; do
    [ -z "${_line}" ] && continue
    _rel=$(echo "${_line}" | awk '{print $1}')
    _ns=$(echo "${_line}" | awk '{print $2}')
    log_info "Uninstalling (layer ${_layer}): ${_rel} (ns: ${_ns})"
    run "helm uninstall '${_rel}' -n '${_ns}' || true"
    [ "${DRY_RUN}" = "false" ] && sleep 30
  done <<< "${_labeled}"
done

# =============================================================================
# STEP 9: DELETE EFS (CLI provisioning only)
# Why: EFS has mount targets — each must be deleted before the file system
# itself can be deleted. Mount target deletion takes ~1 minute per AZ.
# =============================================================================
if [ "${TP_CROSSPLANE_ENABLED}" = "false" ]; then
  log_section "Step 9: Delete EFS File System (CLI provisioning)"

  _efs_id=$(kubectl get sc "${TP_STORAGE_CLASS_EFS}" -o yaml \
    --ignore-not-found 2>/dev/null \
    | grep fileSystemId | awk '{print $2}' || true)

  if [ -n "${_efs_id}" ]; then
    log_info "Found EFS file system: ${_efs_id}"

    log_info "Deleting EFS mount targets..."
    _mt_ids=$(aws efs describe-mount-targets \
      --file-system-id "${_efs_id}" \
      --query "MountTargets[].MountTargetId" \
      --output text --region "${TP_CLUSTER_REGION}" 2>/dev/null || true)

    for _mt_id in ${_mt_ids}; do
      log_info "  Deleting mount target: ${_mt_id}"
      run "aws efs delete-mount-target --mount-target-id '${_mt_id}' --region '${TP_CLUSTER_REGION}'"
    done

    if [ "${DRY_RUN}" = "false" ] && [ -n "${_mt_ids}" ]; then
      log_info "Waiting 2 minutes for mount targets to be deleted..."
      sleep 120
    fi

    log_info "Deleting EFS file system: ${_efs_id}"
    run "aws efs delete-file-system --file-system-id '${_efs_id}' --region '${TP_CLUSTER_REGION}'"

    # Delete EFS security group
    _efs_sg_id=$(aws ec2 describe-security-groups \
      --filters "Name=tag:Resource,Values=${TP_CLUSTER_NAME}-efs" \
      --query "SecurityGroups[0].GroupId" \
      --output text --region "${TP_CLUSTER_REGION}" 2>/dev/null || true)
    if [ -n "${_efs_sg_id}" ] && [ "${_efs_sg_id}" != "None" ]; then
      log_info "Deleting EFS security group: ${_efs_sg_id}"
      run "aws ec2 delete-security-group --group-id '${_efs_sg_id}' --region '${TP_CLUSTER_REGION}'"
    fi
  else
    log_ok "EFS StorageClass '${TP_STORAGE_CLASS_EFS}' not found — EFS may already be deleted or was not created"
  fi
else
  log_section "Step 9: EFS Deletion — Handled by Crossplane (skipped)"
fi

# =============================================================================
# STEP 10: DELETE RDS DB INSTANCE (CLI provisioning only)
# Why: RDS deletion requires skip-final-snapshot for non-production clusters.
# The DB instance must be fully deleted before the subnet group and security
# group can be removed (AWS enforces dependency ordering).
# =============================================================================
if [ "${TP_CROSSPLANE_ENABLED}" = "false" ]; then
  log_section "Step 10: Delete RDS DB Instance (CLI provisioning)"

  _db_id="${TP_CLUSTER_NAME}-db"
  _db_status=$(aws rds describe-db-instances \
    --db-instance-identifier "${_db_id}" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text --region "${TP_CLUSTER_REGION}" 2>/dev/null || echo "not-found")

  if [ "${_db_status}" = "not-found" ] || [ "${_db_status}" = "None" ]; then
    log_ok "RDS DB instance ${_db_id} not found — already deleted or not created"
  else
    log_info "RDS DB instance ${_db_id} is in '${_db_status}' state"
    log_info "Deleting RDS DB instance ${_db_id} (skip-final-snapshot)..."
    run "aws rds delete-db-instance \
      --db-instance-identifier '${_db_id}' \
      --skip-final-snapshot \
      --region '${TP_CLUSTER_REGION}'"

    if [ "${DRY_RUN}" = "false" ]; then
      log_info "Waiting for RDS DB instance to be fully deleted (can take up to 30 minutes)..."
      _waited=0
      while [ ${_waited} -lt 1800 ]; do
        _status=$(aws rds describe-db-instances \
          --db-instance-identifier "${_db_id}" \
          --query "DBInstances[0].DBInstanceStatus" \
          --output text --region "${TP_CLUSTER_REGION}" 2>/dev/null || echo "not-found")
        if [ "${_status}" = "not-found" ] || [ "${_status}" = "None" ]; then
          log_ok "RDS DB instance ${_db_id} deleted"
          break
        fi
        log_info "  DB status: ${_status} (${_waited}s elapsed)"
        sleep 60
        _waited=$((_waited + 60))
      done
    fi

    # Delete subnet group
    _subnet_group="${TP_CLUSTER_NAME}-subnet-group"
    log_info "Deleting RDS subnet group: ${_subnet_group}"
    run "aws rds delete-db-subnet-group \
      --db-subnet-group-name '${_subnet_group}' \
      --region '${TP_CLUSTER_REGION}' 2>/dev/null || true"

    # Delete RDS security group
    _rds_sg_id=$(aws ec2 describe-security-groups \
      --filters "Name=tag:Resource,Values=${TP_CLUSTER_NAME}-rds" \
      --query "SecurityGroups[0].GroupId" \
      --output text --region "${TP_CLUSTER_REGION}" 2>/dev/null || true)
    if [ -n "${_rds_sg_id}" ] && [ "${_rds_sg_id}" != "None" ]; then
      log_info "Deleting RDS security group: ${_rds_sg_id}"
      run "aws ec2 delete-security-group --group-id '${_rds_sg_id}' --region '${TP_CLUSTER_REGION}' || true"
    fi
  fi
else
  log_section "Step 10: RDS Deletion — Handled by Crossplane (skipped)"
fi

# =============================================================================
# STEP 11: DELETE CROSSPLANE IAM ROLE
# =============================================================================
if [ "${TP_CROSSPLANE_ENABLED}" = "true" ]; then
  log_section "Step 11: Delete Crossplane IAM Role"

  log_info "Detaching AdministratorAccess policy from ${TP_CROSSPLANE_ROLE}..."
  run "aws iam detach-role-policy \
    --role-name '${TP_CROSSPLANE_ROLE}' \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>/dev/null || true"

  # Detach any inline policies
  _inline_policies=$(aws iam list-role-policies \
    --role-name "${TP_CROSSPLANE_ROLE}" \
    --query "PolicyNames" --output text 2>/dev/null || true)
  for _policy in ${_inline_policies}; do
    log_info "  Deleting inline policy: ${_policy}"
    run "aws iam delete-role-policy --role-name '${TP_CROSSPLANE_ROLE}' --policy-name '${_policy}' || true"
  done

  log_info "Deleting IAM role: ${TP_CROSSPLANE_ROLE}"
  run "aws iam delete-role --role-name '${TP_CROSSPLANE_ROLE}' 2>/dev/null || true"
  log_ok "Crossplane IAM role cleaned up"
else
  log_section "Step 11: Crossplane IAM Role — Skipped (TP_CROSSPLANE_ENABLED=false)"
fi

# =============================================================================
# STEP 12: DELETE EKS CLUSTER (optional)
# Why: eksctl delete cluster removes the EKS cluster, CloudFormation stacks,
# EC2 node groups, VPC, and subnets that were created by eksctl.
# WARNING: If CP and DP share a cluster, set TP_DELETE_CLUSTER=false and
# delete the DP first, then run this script to delete only the CP resources.
# =============================================================================
log_section "Step 12: Delete EKS Cluster"

if [ "${TP_DELETE_CLUSTER}" = "true" ]; then
  log_warn "Deleting EKS cluster ${TP_CLUSTER_NAME} and all associated VPC/node group resources..."
  run "eksctl delete cluster \
    --name '${TP_CLUSTER_NAME}' \
    --region '${TP_CLUSTER_REGION}' \
    --disable-nodegroup-eviction \
    --force"
  log_ok "EKS cluster deletion initiated"
else
  log_info "TP_DELETE_CLUSTER=false — EKS cluster ${TP_CLUSTER_NAME} preserved"
  log_info "You can delete it later with:"
  log_info "  eksctl delete cluster --name ${TP_CLUSTER_NAME} --region ${TP_CLUSTER_REGION} --force"
fi

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "${DRY_RUN}" = "true" ]; then
  echo -e "${YELLOW}${BOLD}DRY-RUN complete — no resources were deleted.${NC}"
  echo "Re-run without --dry-run to perform the actual cleanup."
else
  echo -e "${GREEN}${BOLD}Control Plane clean-up complete.${NC}"
  echo ""
  echo "Verify in the AWS Console:"
  echo "  - ECS/EKS: cluster ${TP_CLUSTER_NAME} is removed (if TP_DELETE_CLUSTER=true)"
  echo "  - RDS: DB instance ${TP_CLUSTER_NAME}-db is removed (if CLI provisioning)"
  echo "  - EFS: file systems in ${TP_CLUSTER_REGION} are removed"
  echo "  - EC2: Load balancers and security groups for the cluster are removed"
  echo "  - Route 53: records for ${CP_NAMESPACE} are removed"
fi
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
