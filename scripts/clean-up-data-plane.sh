#!/bin/bash
# =============================================================================
# TIBCO Platform on EKS — Data Plane Clean-up Script
#
# Purpose:
#   Removes the TIBCO Data Plane and all associated AWS resources from
#   the EKS cluster in safe deletion order.
#
# Deletion order:
#   1. TibcoResourceSet CRs             — finalizers; must be removed first
#   2. DP Ingress objects               — triggers ALB de-provisioning
#   3. DP capability Helm releases      — no-layer releases (BWCE, Flogo, etc.)
#   4. DP observability Helm releases   — dp-config-es (Elasticsearch, Kibana, APM)
#   5. DP config/infra Helm releases    — dp-config-aws (Nginx/Traefik, storage)
#   6. DP namespace                     — removes all remaining K8s objects
#   7. DP EFS file system (CLI method)  — mount targets then file system
#   8. DP EFS security group            — depends on EFS deletion completing
#   9. EKS cluster (optional)           — controlled by TP_DELETE_CLUSTER
#
# Note: If CP and DP share the same EKS cluster, set TP_DELETE_CLUSTER=false.
#       Delete the CP resources with clean-up-control-plane.sh separately.
#
# Usage:
#   source scripts/env.sh          # load environment variables
#   cd scripts/
#   ./clean-up-data-plane.sh                  # interactive (prompts for confirmation)
#   ./clean-up-data-plane.sh --no-confirm     # skip confirmation (CI/CD use)
#   ./clean-up-data-plane.sh --dry-run        # show what will be deleted, no action
#
# Required variables (from scripts/env.sh):
#   TP_CLUSTER_NAME       — EKS cluster name
#   TP_CLUSTER_REGION     — AWS region
#   TP_CROSSPLANE_ENABLED — "true" or "false"
#   TP_DELETE_CLUSTER     — "true" to delete EKS cluster; "false" = charts + AWS resources only
#
# Optional variables:
#   DP_NAMESPACE          — Data Plane namespace (default: dp1-ns)
#   TP_STORAGE_CLASS_EFS  — EFS StorageClass name (default: efs-sc)
#   TP_DELETE_TIBCO_RESOURCE_SET — Delete TibcoResourceSet CRs (default: true)
#   TP_ES_RELEASE_NAME    — Elastic stack Helm release name (default: dp-config-es)
#
# Source: https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks/scripts/clean-up-data-plane.sh
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
export DP_NAMESPACE="${DP_NAMESPACE:-dp1-ns}"
export TP_ES_RELEASE_NAME="${TP_ES_RELEASE_NAME:-dp-config-es}"

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

# =============================================================================
# PRE-FLIGHT: SHOW DELETION PLAN
# =============================================================================
log_section "Data Plane Clean-up Plan"

echo ""
echo "  Cluster         : ${TP_CLUSTER_NAME} (${TP_CLUSTER_REGION})"
echo "  DP Namespace    : ${DP_NAMESPACE}"
echo "  EFS StorageClass: ${TP_STORAGE_CLASS_EFS}"
echo "  Crossplane      : ${TP_CROSSPLANE_ENABLED}"
echo "  Delete Cluster  : ${TP_DELETE_CLUSTER}"
echo "  ES Release      : ${TP_ES_RELEASE_NAME}"
echo ""

if [ "${DRY_RUN}" = "true" ]; then
  log_warn "DRY-RUN mode — no resources will be deleted"
fi

if [ "${NO_CONFIRM}" = "false" ] && [ "${DRY_RUN}" = "false" ]; then
  echo -e "${RED}${BOLD}WARNING: This will permanently delete the TIBCO Data Plane and AWS resources.${NC}"
  echo ""
  echo "Before proceeding, confirm:"
  echo "  1. The Data Plane has been de-registered from the CP UI"
  echo "     (CP UI → Data Planes → Delete)"
  echo "  2. All running applications/capabilities have been stopped"
  echo "  3. TP_DELETE_CLUSTER=${TP_DELETE_CLUSTER} is correct"
  echo "     (set to 'false' if CP is on the same cluster)"
  echo ""
  read -r -p "Type 'yes' to continue: " CONFIRM
  if [ "${CONFIRM}" != "yes" ]; then
    log_info "Aborted."
    exit 0
  fi
fi

# =============================================================================
# STEP 1: DELETE TibcoResourceSet CRs
# Why: TibcoResourceSet CRs carry finalizers that block namespace termination.
# They must be deleted first so capability namespaces can terminate cleanly.
# =============================================================================
log_section "Step 1: Delete TibcoResourceSet CRs"

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

# =============================================================================
# STEP 2: DELETE INGRESS OBJECTS (triggers ALB de-provisioning)
# Why: The AWS LBC watches Ingress objects. Deleting ingresses first signals
# the LBC to delete ALB listeners, target groups, and the ALB itself.
# Waiting 2 minutes ensures the ALB is fully removed before the LBC is deleted.
# Without this wait, the ALB stays in AWS (orphaned) and continues to incur costs.
# =============================================================================
log_section "Step 2: Delete Ingress Objects (trigger ALB de-provisioning)"

_dp_ingress_count=$(kubectl get ingress -n "${DP_NAMESPACE}" --no-headers 2>/dev/null | wc -l)
_all_ingress_count=$(kubectl get ingress -A --no-headers 2>/dev/null | wc -l)

if [ "${_all_ingress_count}" -gt 0 ]; then
  log_info "Deleting all Ingress objects (${_all_ingress_count} total across all namespaces)..."
  run "kubectl delete ingress -A --all --ignore-not-found"
  if [ "${DRY_RUN}" = "false" ]; then
    log_info "Waiting 2 minutes for AWS ALB to be de-provisioned..."
    sleep 120
  fi
else
  log_ok "No Ingress objects found"
fi

# =============================================================================
# STEP 3: UNINSTALL DP CAPABILITY HELM RELEASES (no layer label)
# These are releases deployed by TIBCO capabilities (BWCE, Flogo, EMS, etc.)
# directly into the DP namespace without a layer label.
# =============================================================================
log_section "Step 3: Uninstall DP Capability Helm Releases (no layer)"

_dp_unlabeled=$(helm ls -n "${DP_NAMESPACE}" --selector '!layer' -a -o json 2>/dev/null \
  | jq -r '.[].name' 2>/dev/null || true)

if [ -n "${_dp_unlabeled}" ]; then
  while IFS= read -r _release; do
    [ -z "${_release}" ] && continue
    log_info "Uninstalling capability release: ${_release}"
    run "helm uninstall '${_release}' -n '${DP_NAMESPACE}' --wait --timeout 5m || true"
  done <<< "${_dp_unlabeled}"
else
  log_ok "No unlabeled Helm releases found in ${DP_NAMESPACE}"
fi

# Also check for capability releases in other namespaces (EMS uses dedicated namespaces)
_all_unlabeled=$(helm ls --selector '!layer' -a -A -o json 2>/dev/null \
  | jq -r '.[] | "\(.name) \(.namespace)"' 2>/dev/null || true)
while IFS= read -r _line; do
  [ -z "${_line}" ] && continue
  _rel=$(echo "${_line}" | awk '{print $1}')
  _ns=$(echo "${_line}" | awk '{print $2}')
  # Skip system namespaces
  case "${_ns}" in
    kube-system|kube-public|kube-node-lease|cert-manager|crossplane-system|ingress-system|external-dns-system|elastic-system|monitoring) continue ;;
  esac
  log_info "Uninstalling: ${_rel} (ns: ${_ns})"
  run "helm uninstall '${_rel}' -n '${_ns}' || true"
  [ "${DRY_RUN}" = "false" ] && sleep 15
done <<< "${_all_unlabeled}"

# =============================================================================
# STEP 4: UNINSTALL OBSERVABILITY HELM RELEASES (dp-config-es)
# Why: Elastic Stack uses CRDs managed by the ECK operator. The dp-config-es
# Helm release must be deleted before the ECK operator (which is part of the
# dp-config-aws chart) to allow ECK to cleanly remove Elasticsearch,
# Kibana, and APM resources via its own controllers.
# =============================================================================
log_section "Step 4: Uninstall Observability Helm Releases (dp-config-es)"

for _ns in elastic-system monitoring "${DP_NAMESPACE}"; do
  if helm ls -n "${_ns}" 2>/dev/null | grep -qE "dp-config-es|${TP_ES_RELEASE_NAME}"; then
    log_info "Uninstalling ${TP_ES_RELEASE_NAME} from namespace ${_ns}..."
    run "helm uninstall '${TP_ES_RELEASE_NAME}' -n '${_ns}' --wait --timeout 10m || true"
  fi
done

# Delete any remaining ECK CRs if the operator was removed before the resources
for _crd in elasticsearch kibana apmserver beat logstash elasticsearchautoscaler; do
  _count=$(kubectl get "${_crd}.elasticsearch.k8s.elastic.co" -A --no-headers 2>/dev/null | wc -l)
  if [ "${_count}" -gt 0 ]; then
    log_info "Removing remaining ${_crd} CRs..."
    run "kubectl delete '${_crd}.elasticsearch.k8s.elastic.co' -A --all --ignore-not-found || true"
  fi
done

# =============================================================================
# STEP 5: UNINSTALL DP INFRASTRUCTURE HELM RELEASES (by layer, high to low)
# These are dp-config-aws releases: nginx/traefik, storage, AWS LBC, etc.
# =============================================================================
log_section "Step 5: Uninstall DP Infrastructure Helm Releases (by layer)"

for _layer in 3 2 1 0; do
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
# STEP 6: DELETE DP NAMESPACE
# Why: Deleting the namespace removes all remaining K8s objects (ConfigMaps,
# Secrets, ServiceAccounts, etc.) that were not part of any Helm release.
# After the above Helm uninstalls, only a few TIBCO-created objects remain.
# =============================================================================
log_section "Step 6: Delete Data Plane Namespace"

if kubectl get namespace "${DP_NAMESPACE}" &>/dev/null; then
  log_info "Deleting namespace ${DP_NAMESPACE}..."
  run "kubectl delete namespace '${DP_NAMESPACE}' --timeout=120s || true"

  if [ "${DRY_RUN}" = "false" ]; then
    log_info "Waiting for namespace to terminate..."
    kubectl wait --for=delete namespace/"${DP_NAMESPACE}" --timeout=120s 2>/dev/null || \
      log_warn "Namespace may still be terminating — check manually if needed"
  fi
else
  log_ok "Namespace ${DP_NAMESPACE} already removed"
fi

# =============================================================================
# STEP 7: DELETE DP EFS FILE SYSTEM (CLI provisioning only)
# Why: The DP EFS file system is separate from the CP EFS. It is tagged with
# the cluster name and identified by the DP StorageClass fileSystemId parameter.
# Mount targets must be deleted before the file system can be deleted.
# =============================================================================
if [ "${TP_CROSSPLANE_ENABLED}" = "false" ]; then
  log_section "Step 7: Delete DP EFS File System"

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
    log_ok "EFS ${_efs_id} deleted"
  else
    log_ok "EFS StorageClass '${TP_STORAGE_CLASS_EFS}' not found — EFS may already be deleted or not created"
  fi

  # Delete EFS security group (tagged with cluster name)
  log_section "Step 7b: Delete DP EFS Security Group"
  _efs_sg_id=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Cluster,Values=${TP_CLUSTER_NAME}" \
    --query "SecurityGroups[?contains(GroupName,'efs')].GroupId | [0]" \
    --output text --region "${TP_CLUSTER_REGION}" 2>/dev/null || true)

  if [ -n "${_efs_sg_id}" ] && [ "${_efs_sg_id}" != "None" ]; then
    log_info "Deleting DP EFS security group: ${_efs_sg_id}"
    run "aws ec2 delete-security-group --group-id '${_efs_sg_id}' --region '${TP_CLUSTER_REGION}' || true"
    log_ok "EFS security group deleted"
  else
    log_ok "No DP EFS security group found with cluster tag '${TP_CLUSTER_NAME}'"
  fi
else
  log_section "Step 7: DP EFS — Handled by Crossplane (skipped)"
fi

# =============================================================================
# STEP 8: DELETE EKS CLUSTER (optional)
# WARNING: Only delete the cluster if this is a DP-only cluster.
# If CP and DP share the same cluster, set TP_DELETE_CLUSTER=false and
# run clean-up-control-plane.sh to handle the cluster deletion.
# =============================================================================
log_section "Step 8: Delete EKS Cluster"

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
  log_info "If this is a shared cluster with CP, run clean-up-control-plane.sh next."
  log_info "To delete the cluster later:"
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
  echo -e "${GREEN}${BOLD}Data Plane clean-up complete.${NC}"
  echo ""
  echo "Verify in the AWS Console:"
  echo "  - EKS/EC2: cluster ${TP_CLUSTER_NAME} is removed (if TP_DELETE_CLUSTER=true)"
  echo "  - EFS: DP file systems in ${TP_CLUSTER_REGION} are removed"
  echo "  - EC2: Load balancers and security groups for the DP are removed"
  echo "  - Route 53: DP records (*.${DP_NAMESPACE}) are removed"
fi
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
