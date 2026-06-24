You are helping validate and set up all prerequisites for a TIBCO Platform deployment on Amazon Elastic Kubernetes Service (EKS). Work through each phase methodically — run each check, report the result, and fix gaps before moving on.

## Reference
Read `howto/prerequisites-checklist-for-customer.md` for the full requirements list. This skill covers the technical setup required before running `tibco-provision-cp` or `tibco-provision-cp-dp`.

## Phase 1 — Cluster Access

Verify AWS CLI and `kubectl` access:

```bash
aws sts get-caller-identity
kubectl version --short
kubectl get nodes -o wide
eksctl version
```

Report: AWS account ID/ARN, `kubectl` server version, number of Ready nodes.

If `kubectl get nodes` fails:
```bash
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${TP_CLUSTER_NAME}"
```

## Phase 2 — Collect Configuration

Ask the user to confirm or provide these values (check `scripts/env.sh` for defaults):

| Variable | Description | Example |
|----------|-------------|---------|
| `CP_INSTANCE_ID` | Control Plane ID, max 5 chars, **no hyphens** | `cp1` |
| `DP_INSTANCE_ID` | Data Plane ID | `dp1` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `TP_CLUSTER_NAME` | EKS cluster name | `tibco-workshop-eks` |
| `TP_HOSTED_ZONE_DOMAIN` | Route 53 base domain | `aws.example.com` |
| `TP_BASE_DNS_DOMAIN` | Simplified DNS domain (1.17+) | `aws.example.com` |
| `ACM_CERTIFICATE_ARN` | ACM wildcard certificate ARN | `arn:aws:acm:...` |
| `TP_CONTAINER_REGISTRY_URL` | TIBCO JFrog registry | `csgprduswrepoedge.jfrog.io` |
| `TP_CONTAINER_REGISTRY_USER` | JFrog username | |
| `TP_CONTAINER_REGISTRY_PASSWORD` | JFrog password | |
| `CP_DB_HOST` | Aurora PostgreSQL hostname | `mydb.cluster-xxx.us-east-1.rds.amazonaws.com` |
| `CP_DB_USERNAME` | Database username | |
| `CP_DB_PASSWORD` | Database password | |

Export all provided values before continuing.

## Phase 3 — OIDC Provider

IRSA requires an OIDC provider associated with the cluster:

```bash
aws eks describe-cluster --name "${TP_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.identity.oidc.issuer' --output text
```

Verify the OIDC provider exists in IAM:
```bash
aws iam list-open-id-connect-providers | grep oidc
```

If missing, create it:
```bash
eksctl utils associate-iam-oidc-provider \
  --cluster "${TP_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --approve
```

## Phase 4 — EKS Addons

Verify required EKS addons are installed:

```bash
aws eks list-addons --cluster-name "${TP_CLUSTER_NAME}" --region "${AWS_REGION}"
kubectl get pods -n kube-system | grep -E "vpc-cni|coredns|kube-proxy"
kubectl get pods -n kube-system | grep -E "efs-csi|ebs-csi"
```

Required addons: `vpc-cni`, `kube-proxy`, `coredns`, `aws-efs-csi-driver`, `aws-ebs-csi-driver`.

Install missing addons:
```bash
# EFS CSI driver
aws eks create-addon --cluster-name "${TP_CLUSTER_NAME}" --region "${AWS_REGION}" \
  --addon-name aws-efs-csi-driver 2>/dev/null || echo "EFS CSI already installed"

# EBS CSI driver
aws eks create-addon --cluster-name "${TP_CLUSTER_NAME}" --region "${AWS_REGION}" \
  --addon-name aws-ebs-csi-driver 2>/dev/null || echo "EBS CSI already installed"
```

## Phase 5 — Storage Classes

Verify EFS (RWX) and EBS gp3 (RWO) storage classes:

```bash
kubectl get storageclass
```

Required:
- `efs-sc` — EFS file storage with RWX, for CP and BWCE artifacts
- `ebs-gp3` — EBS block storage for EMS and stateful workloads

If missing, install via the `dp-config-aws` chart:
```bash
helm repo add tibco-platform-public https://tibcosoftware.github.io/tp-helm-charts
helm repo update
helm upgrade --install --wait --timeout 1h --create-namespace \
  -n storage-system dp-config-aws-storage tibco-platform-public/dp-config-aws \
  --set "global.tibco.createNetworkPolicy=false"
```

## Phase 6 — AWS Load Balancer Controller

The ALB controller creates AWS Application Load Balancers from Ingress resources.

Check if installed:
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null && echo "ALB controller OK" || echo "ALB controller MISSING"
```

If missing, create the IRSA service account and install:
```bash
# Create IRSA role (requires aws-load-balancer-controller IAM policy to exist)
eksctl create iamserviceaccount \
  --cluster "${TP_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# Install controller
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install --wait --timeout 10m -n kube-system aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --set clusterName="${TP_CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

Verify:
```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Phase 7 — ACM Certificate

Verify the wildcard ACM certificate is in `ISSUED` state:

```bash
aws acm describe-certificate \
  --certificate-arn "${ACM_CERTIFICATE_ARN}" \
  --region "${AWS_REGION}" \
  --query 'Certificate.{Status:Status, Domain:DomainName, SANs:SubjectAlternativeNames}' \
  --output table
```

Status must be `ISSUED`. If pending validation, check Route 53 for the CNAME validation record.

## Phase 8 — Route 53 Hosted Zone

Verify the hosted zone exists:

```bash
aws route53 list-hosted-zones-by-name \
  --dns-name "${TP_HOSTED_ZONE_DOMAIN}" \
  --query 'HostedZones[0].{Name:Name, Id:Id}' \
  --output table
```

## Phase 9 — Aurora PostgreSQL Connectivity

Verify the CP database is reachable from the cluster:

```bash
# Run a temporary pod to test connectivity
kubectl run -it --rm pg-test --image=postgres:16 --restart=Never -- \
  psql "host=${CP_DB_HOST} port=5432 dbname=postgres user=${CP_DB_USERNAME} password=${CP_DB_PASSWORD} sslmode=require" \
  -c "SELECT version();" 2>/dev/null
```

Or use the Azure DevOps pipeline `test-postgres-connectivity.yml` if available.

## Phase 10 — Control Plane Namespace and Secrets

Create CP namespace:
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${CP_INSTANCE_ID}-ns
  labels:
    platform.tibco.com/controlplane-instance-id: ${CP_INSTANCE_ID}
EOF

kubectl create serviceaccount ${CP_INSTANCE_ID}-sa -n ${CP_INSTANCE_ID}-ns 2>/dev/null || echo "SA already exists"
```

Create image pull secret and required secrets:
```bash
kubectl create secret docker-registry tibco-container-registry-credentials \
  --docker-server="${TP_CONTAINER_REGISTRY_URL}" \
  --docker-username="${TP_CONTAINER_REGISTRY_USER}" \
  --docker-password="${TP_CONTAINER_REGISTRY_PASSWORD}" \
  --docker-email="platform@company.com" \
  -n ${CP_INSTANCE_ID}-ns \
  --dry-run=client -o yaml | kubectl apply -f -

# Session keys
TSC_SESSION_KEY=$(openssl rand -base64 48 | tr -dc A-Za-z0-9 | head -c32)
DOMAIN_SESSION_KEY=$(openssl rand -base64 48 | tr -dc A-Za-z0-9 | head -c32)
kubectl create secret generic session-keys -n ${CP_INSTANCE_ID}-ns \
  --from-literal=TSC_SESSION_KEY=${TSC_SESSION_KEY} \
  --from-literal=DOMAIN_SESSION_KEY=${DOMAIN_SESSION_KEY} \
  --dry-run=client -o yaml | kubectl apply -f -

# Encryption secret
CP_ENCRYPTION_SECRET=$(openssl rand -base64 32)
kubectl create secret generic cporch-encryption-secret -n ${CP_INSTANCE_ID}-ns \
  --from-literal=ENCRYPTION_KEY=${CP_ENCRYPTION_SECRET} \
  --dry-run=client -o yaml | kubectl apply -f -

# Database credentials
kubectl create secret generic ${CP_INSTANCE_ID}-provider-cp-database -n ${CP_INSTANCE_ID}-ns \
  --from-literal=db_username="${CP_DB_USERNAME}" \
  --from-literal=db_password="${CP_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Phase 11 — Helm Repository

```bash
helm repo add tibco-platform-public https://tibcosoftware.github.io/tp-helm-charts
helm repo update
helm search repo tibco-platform-public/tibco-cp-base --versions | head -5
```

## Phase 12 — Final Summary

```bash
echo "=== Cluster ===" && kubectl get nodes --no-headers | wc -l && echo "nodes Ready"
echo "=== OIDC ===" && aws eks describe-cluster --name "${TP_CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.identity.oidc.issuer' --output text
echo "=== EKS Addons ===" && aws eks list-addons --cluster-name "${TP_CLUSTER_NAME}" --region "${AWS_REGION}" --output text
echo "=== ALB Controller ===" && kubectl get deployment -n kube-system aws-load-balancer-controller
echo "=== Storage Classes ===" && kubectl get storageclass | grep -E "efs|ebs|gp3"
echo "=== ACM Status ===" && aws acm describe-certificate --certificate-arn "${ACM_CERTIFICATE_ARN}" --region "${AWS_REGION}" --query 'Certificate.Status' --output text
echo "=== Namespace ===" && kubectl get namespace ${CP_INSTANCE_ID}-ns
echo "=== Secrets ===" && kubectl get secrets -n ${CP_INSTANCE_ID}-ns | grep -E "registry|session|encryption|database"
echo "=== Helm Repo ===" && helm repo list | grep tibco
```

Report PASS/FAIL for each item. If everything passes, the environment is ready for `tibco-provision-cp`.
