---
layout: default
title: TIBCO Platform on EKS - Customer Prerequisites Checklist
---

# TIBCO Platform on EKS - Customer Prerequisites Checklist

**Document Purpose**: This checklist outlines the requirements that must be in place **before** TIBCO Platform Control Plane and Data Plane installation begins on Amazon Elastic Kubernetes Service (EKS).

**Target Audience**: Customer IT teams responsible for AWS infrastructure preparation

**Last Updated**: June 2026

---

## Overview

Before the TIBCO implementation team begins installation, please ensure all prerequisites listed in this document are met. This preparation is critical for a successful and timely deployment.

**Estimated Preparation Time**: 3-5 business days (depending on organizational processes)

> **Quick Reference**: Sections 1–7 cover **AWS infrastructure** prerequisites. Sections 8–10 cover **TIBCO Platform Control Plane** specific prerequisites (Helm chart access, Kubernetes secrets, security configuration).

---

## Infrastructure Prerequisites

The following sections (1–7) describe the AWS and Kubernetes infrastructure that must be provisioned before TIBCO Platform installation begins.

---

## 1. Amazon EKS Cluster Requirements

> **Note:** TIBCO Control Plane supports Cloud Native Computing Foundation (CNCF) certified Kubernetes platforms.

### Control Plane EKS Cluster

| Requirement | Specification | Notes |
|-------------|--------------|-------|
| **Cluster Type** | Amazon Elastic Kubernetes Service (EKS) | CNCF certified |
| **Kubernetes Version** | 1.33 or higher | See [EKS supported versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) |
| **Cluster Access** | `kubectl` CLI with admin permissions | Must be able to create namespaces, CRDs, and cluster roles |
| **Node Count** | Minimum 3 worker nodes | For high availability |
| **Node Instance Type** | `m5a.xlarge` or larger | 4 vCPU, 16 GB RAM per node |
| **Total Cluster Capacity** | 12+ CPU cores, 48+ GB RAM | Ensure headroom for Control Plane workloads |
| **Node Storage** | 100 GB gp3 per node | Root volume |
| **OIDC Provider** | Enabled | Required for IRSA |
| **Private Networking** | Node group in private subnets | Recommended for security |

### Data Plane EKS Cluster

| Requirement | Specification | Notes |
|-------------|--------------|-------|
| **Cluster Type** | Amazon Elastic Kubernetes Service (EKS) | Can be same cluster as Control Plane for dev/test |
| **Kubernetes Version** | 1.33 or higher | Must be compatible with Control Plane |
| **Cluster Access** | `kubectl` CLI with admin permissions | Per Data Plane cluster |
| **Node Instance Type** | `m5a.xlarge` or larger | Scale based on workload |
| **Node Resources** | 4 vCPU, 16 GB RAM per node | Minimum per node |
| **Network Connectivity** | Bidirectional HTTPS to Control Plane | See network requirements section |

### EKS Configuration Requirements

| Configuration | Requirement | Details |
|--------------|-------------|---------|
| **VPC CIDR** | Non-overlapping IP address space | e.g., `10.180.0.0/16` |
| **Service CIDR** | Kubernetes service IPs | e.g., `172.20.0.0/16` |
| **VPC CNI** | With `enableNetworkPolicy: true` | For network policy enforcement |
| **EKS Addons** | `vpc-cni`, `kube-proxy`, `coredns`, `aws-efs-csi-driver`, `aws-ebs-csi-driver` | All required |
| **IRSA Service Accounts** | Pre-created via eksctl | See IRSA section below |

---

## 2. IAM Roles and Service Accounts (IRSA)

EKS uses IAM Roles for Service Accounts (IRSA) to grant AWS permissions to Kubernetes workloads. The following service accounts must be created with OIDC-based IAM role annotations.

| Service Account | Namespace | IAM Policy | Purpose |
|----------------|-----------|------------|---------|
| `aws-load-balancer-controller` | `kube-system` | `AWSLoadBalancerControllerIAMPolicy` | Creates and manages AWS ALBs |
| `external-dns` | `external-dns-system` | Route 53 record management | Creates Route 53 DNS records |
| `cert-manager` | `cert-manager` | Route 53 DNS challenge | DNS-01 ACME challenge for ACM |
| `efs-csi-controller-sa` | `kube-system` | `AmazonElasticFileSystemFullAccess` | Manages EFS volumes |
| `ebs-csi-controller-sa` | `kube-system` | `service:CreateVolume`, etc. | Manages EBS volumes |

These accounts are pre-created by the `eksctl` ClusterConfig recipe when using `wellKnownPolicies`.

---

## 3. AWS Resources Required

### Storage

| Resource | Type | Purpose |
|----------|------|---------|
| **Amazon EFS** | Elastic File System | Control Plane storage; BWCE artifact manager; EMS log storage |
| **Amazon EBS gp3** | Elastic Block Store | EMS capability data storage |

#### EFS Requirements

| Requirement | Details |
|-------------|---------|
| **VPC** | Must be in the same VPC as the EKS cluster |
| **Security Group** | Allow NFS (port 2049) from EKS node security group |
| **Performance Mode** | General Purpose |
| **Throughput Mode** | Elastic (recommended) |
| **Encryption** | Enabled (recommended) |

### Database (Control Plane Only)

| Requirement | Specification | Notes |
|-------------|--------------|-------|
| **Database Engine** | Amazon Aurora PostgreSQL 16 | Or PostgreSQL 16 (RDS) |
| **Instance Class** | `db.t3.medium` or larger | Based on load |
| **VPC** | Same as EKS cluster | Or peered VPC |
| **Security Group** | Allow port 5432 from EKS node security group | |
| **SSL Enforcement** | `rds.force_ssl=1` (recommended) | Required for production |
| **Database Name** | `postgres` | Created automatically |
| **Master Username** | Customer-defined | e.g., `useradmin` |

### Load Balancing

| Requirement | Specification |
|-------------|--------------|
| **AWS ALB** | Created automatically by `aws-load-balancer-controller` |
| **Ingress Controller** | Nginx or Traefik (installed via `dp-config-aws` chart) |

---

## 4. DNS Requirements

| Requirement | Details |
|-------------|---------|
| **DNS Provider** | Amazon Route 53 hosted zone |
| **Domain** | Top-level domain registered in Route 53 (e.g., `aws.example.com`) |
| **Simplified DNS (Recommended)** | One shared base domain: admin, subscription portal, and tunnel all use `*.aws.example.com` |
| **Control Plane domains (Legacy)** | Wildcard certificates for `*.cp1-my.<domain>` and `*.cp1-tunnel.<domain>` |
| **Data Plane domain** | Wildcard certificate for `*.dp1.<domain>` |
| **External DNS** | Automatically manages records via IRSA |

---

## 5. SSL/TLS Certificate Requirements

| Requirement | Details |
|-------------|---------|
| **Certificate Provider** | AWS Certificate Manager (ACM) |
| **Simplified DNS (Recommended)** | One wildcard certificate: `*.<base-domain>` covers admin, subscription, and tunnel |
| **Legacy DNS** | Two wildcard certificates: `*.cp1-my.<domain>` and `*.cp1-tunnel.<domain>` |
| **Data Plane** | Wildcard certificate: `*.dp1.<domain>` |
| **Validation Method** | DNS validation (recommended) |
| **Status** | Must be in `ISSUED` status before installation |

---

## 6. Access and Credentials

### Required AWS Access

| Access Type | Details | Required Before Installation |
|-------------|---------|------------------------------|
| **AWS Account** | IAM user or role with sufficient permissions | ✅ Required |
| **EKS Cluster Admin** | `kubectl` with admin kubeconfig | ✅ Required |
| **TIBCO Container Registry** | JFrog credentials for `csgprduswrepoedge.jfrog.io` | ✅ Required |
| **Route 53** | Hosted zone with permission to create records | ✅ Required for CP |
| **ACM** | Ability to request/validate certificates | ✅ Required for CP |
| **RDS Admin** | Database master credentials | ✅ Required for CP |

### IAM Permissions Required

The IAM user or role used during installation needs permissions for:
- EKS cluster management (`eks:*`)
- EC2 (VPC, subnets, security groups)
- IAM role and policy management (for IRSA)
- EFS management (`elasticfilesystem:*`)
- RDS management (`rds:*`)
- ELB management (`elasticloadbalancing:*`)
- Route 53 (`route53:*`)
- ACM (`acm:*`)

See [eksctl minimum IAM policies](https://eksctl.io/usage/minimum-iam-policies/) for the eksctl-specific requirements.

### Tools Required on Installation Machine

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| `aws` (AWS CLI) | 2.15.0+ | AWS resource management |
| `eksctl` | 0.210.0+ | EKS cluster creation |
| `kubectl` | 1.33.0+ | Kubernetes cluster management |
| `helm` | 3.13.0+ | Chart deployment (labels require v3.13+) |
| `openssl` | 1.1+ | Secret generation |
| `jq` | 1.6+ | JSON processing |
| `yq` | 4.40.0+ | YAML processing |
| `envsubst` | Latest | Environment variable substitution |

### Custom / Internal Registry (Air-Gapped or Private Registry Environments)

If your EKS cluster cannot reach the TIBCO JFrog registry directly, you must pre-mirror all images to an accessible private registry (such as Amazon ECR) before installation.

> **⚠️ Important**: Do **not** use standard `docker push`, `podman push`, `docker save`, or `podman save` to transfer BusinessWorks plugin images. These commands silently re-compress image layers and corrupt the GZIP headers required by the `bwce-utilities` extraction container, causing `tar: invalid tar header checksum` failures during BW capability deployment.

Use the **official TIBCO sync script** or one of these registry-to-registry copy methods that preserve original layer compression:

| Tool | Best For |
|------|----------|
| `sync-images.sh` (official TIBCO script) | All images at once — recommended starting point |
| `docker buildx imagetools create` | Docker environments, per-image copy |
| `skopeo copy --format v2s2` | Scripted copy, Podman environments |
| `skopeo dir://` | Air-gapped / physical data transfer |

📖 **Full guide**: [How to Push TIBCO Platform Images to a Custom Container Registry](./how-to-sync-images) — covers all copy methods, ECR setup, air-gapped staging, and image integrity verification.

#### Amazon ECR Checklist

If using Amazon ECR as your private registry:

- [ ] ECR repositories created for each required TIBCO image
- [ ] IAM permissions include `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, and related push permissions
- [ ] TIBCO images mirrored to ECR using a bit-perfect copy method (see guide above)
- [ ] Image integrity verified using GZIP header inspection (see sync guide)
- [ ] Note: ECR auth tokens expire after 12 hours — use IRSA or a token refresh mechanism for production

---

## 7. Network Requirements

### Control Plane Network Requirements

| Network Configuration | Requirement | Details |
|----------------------|-------------|---------|
| **Internet Access** | Outbound HTTPS (443) | Pull container images from TIBCO registry |
| **DNS Resolution** | Internal and external | Resolve cluster services and internet domains |
| **ALB** | Automatically provisioned by aws-load-balancer-controller | |
| **VPC Endpoints** | Optional but recommended | For AWS services (S3, ECR, STS) |

### Data Plane Network Requirements

| Network Configuration | Requirement | Details |
|----------------------|-------------|---------|
| **Control Plane Connectivity** | Bidirectional HTTPS (443) | DP communicates with CP over HTTPS |
| **Tunnel Connectivity** | Outbound HTTPS to CP tunnel domain | For hybrid connectivity |
| **Internet Access** | Outbound HTTPS (443) | Pull capability images |

### Firewall / Security Group Outbound Rules

| Destination | Port | Protocol | Purpose |
|-------------|------|----------|---------|
| `csgprduswrepoedge.jfrog.io` | 443 | HTTPS | TIBCO container images |
| `tibcosoftware.github.io` | 443 | HTTPS | TIBCO Helm charts |
| `docker.io`, `registry-1.docker.io` | 443 | HTTPS | Docker Hub images |
| `ghcr.io` | 443 | HTTPS | GitHub Container Registry |
| `quay.io` | 443 | HTTPS | Quay container registry |
| `charts.jetstack.io` | 443 | HTTPS | cert-manager Helm charts |
| `helm.elastic.co` | 443 | HTTPS | Elastic ECK charts |
| `aws.github.io` | 443 | HTTPS | AWS EKS charts |
| `kubernetes-sigs.github.io` | 443 | HTTPS | External DNS charts |
| `prometheus-community.github.io` | 443 | HTTPS | Prometheus charts |
| `*.eks.amazonaws.com` | 443 | HTTPS | EKS API |
| `*.ecr.<region>.amazonaws.com` | 443 | HTTPS | Amazon ECR |
| `ec2.amazonaws.com` | 443 | HTTPS | EC2 API |
| `elasticloadbalancing.amazonaws.com` | 443 | HTTPS | ELB API |
| `sts.amazonaws.com` | 443 | HTTPS | AWS STS |
| `iam.amazonaws.com` | 443 | HTTPS | IAM API |
| `proxy.golang.org` | 443 | HTTPS | Go module proxy (required for Flogo) |
| `sum.golang.org` | 443 | HTTPS | Go checksum database (required for Flogo) |

See [Firewall Requirements](../docs/firewall-requirements-eks) for the complete list.

---

## TIBCO Platform Control Plane Prerequisites

The following sections (8–10) describe prerequisites specific to TIBCO Platform Control Plane installation. These are independent of the AWS infrastructure and focus on TIBCO-specific configuration, secrets, and security settings that must be prepared before running the TIBCO Helm charts.

---

## 8. TIBCO Platform Helm Chart Repository

| Requirement | Details |
|-------------|---------|
| **Helm Repo URL** | `https://tibcosoftware.github.io/tp-helm-charts` |
| **Add Repository** | `helm repo add tibco-platform https://tibcosoftware.github.io/tp-helm-charts` |
| **TIBCO CP Base Chart** | `tibco-cp-base` version `1.18.0` |
| **dp-config-aws Chart** | `dp-config-aws` version `^1.0.0` |

---

## 9. Storage Class Summary

| Storage Class | Provisioner | Used For | Required For |
|:-------------|:------------|:---------|:-------------|
| `efs-sc` | `efs.csi.aws.com` | CP storage, BWCE artifact manager, EMS log | Control Plane + Data Plane |
| `ebs-gp3` | `ebs.csi.aws.com` | EMS capability data storage | Data Plane only |
| `gp2` | `kubernetes.io/aws-ebs` | EKS default — avoid using | — |

---

## 10. Kubernetes Secrets

The TIBCO Control Plane requires several Kubernetes secrets to be pre-created in the Control Plane namespace (`${CP_INSTANCE_ID}-ns`, typically `cp1-ns`) **before** deploying the `tibco-cp-base` Helm chart. These secrets are not created by the chart itself.

> **Important**: Store all generated secret values in a secure vault (e.g., AWS Secrets Manager). These secrets are required for disaster recovery and upgrades. Changing `session-keys` or `cporch-encryption-secret` after initial deployment will break the running Control Plane.

### 10.1 CP Namespace and Service Account

Before creating secrets, the CP namespace and service account must exist:

```bash
export CP_INSTANCE_ID="cp1"

kubectl apply -f <(envsubst '${CP_INSTANCE_ID}' <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ${CP_INSTANCE_ID}-ns
  labels:
    platform.tibco.com/controlplane-instance-id: ${CP_INSTANCE_ID}
EOF
)

kubectl create serviceaccount ${CP_INSTANCE_ID}-sa -n ${CP_INSTANCE_ID}-ns
```

> **Note**: If using Crossplane claims to provision infrastructure, the namespace and service account are created automatically by the claim.

### 10.2 session-keys (Required)

The TIBCO Control Plane router pods use these cryptographic keys to sign and verify user session tokens. Without this secret, the router pods crash on startup with a missing secret error. **These keys must remain stable across upgrades** — changing them immediately invalidates all active user sessions.

| Key | Purpose |
|-----|---------|
| `TSC_SESSION_KEY` | Signs tokens for the TSC (TIBCO Subscription Console) domain |
| `DOMAIN_SESSION_KEY` | Signs tokens for custom domain routing |

```bash
export TSC_SESSION_KEY=$(openssl rand -base64 48 | tr -dc A-Za-z0-9 | head -c32)
export DOMAIN_SESSION_KEY=$(openssl rand -base64 48 | tr -dc A-Za-z0-9 | head -c32)

kubectl create secret generic session-keys -n ${CP_INSTANCE_ID}-ns \
  --from-literal=TSC_SESSION_KEY=${TSC_SESSION_KEY} \
  --from-literal=DOMAIN_SESSION_KEY=${DOMAIN_SESSION_KEY}
```

### 10.3 cporch-encryption-secret (Required)

The CP Orchestrator service uses this key to encrypt sensitive data written to the database — including Data Plane connection strings, external service credentials, and API keys. This is application-layer encryption (separate from RDS at-rest encryption). **This key must never change after initial deployment**: if it changes, the orchestrator cannot decrypt previously stored data and the Control Plane will fail to connect to registered Data Planes.

```bash
export CP_ENCRYPTION_SECRET=$(openssl rand -base64 48 | tr -dc A-Za-z0-9 | head -c44)

kubectl create secret generic cporch-encryption-secret -n ${CP_INSTANCE_ID}-ns \
  --from-literal=CP_ENCRYPTION_SECRET=${CP_ENCRYPTION_SECRET}
```

### 10.4 rds-ca-cert (Required only for SSL verify-full mode)

If you configure `TP_DB_SSL_MODE=verify-full`, the orchestrator needs the AWS RDS CA bundle to verify the Aurora certificate chain against AWS's own Certificate Authority. This secret is **optional** for development environments — use `disable` or `require` SSL mode instead.

```bash
# Download the regional CA bundle
curl -o rds-ca-bundle.pem \
  "https://truststore.pki.rds.amazonaws.com/${TP_CLUSTER_REGION}/${TP_CLUSTER_REGION}-bundle.pem"

# Verify the download contains at least one certificate
grep -c "BEGIN CERTIFICATE" rds-ca-bundle.pem

kubectl create secret generic rds-ca-cert \
  -n ${CP_INSTANCE_ID}-ns \
  --from-file=rds-ca-bundle.pem=rds-ca-bundle.pem
```

### 10.5 Container Registry Credentials

The TIBCO JFrog container registry credentials are passed as Helm values (`global.tibco.containerRegistry.username` / `password`) in the `tibco-cp-base` chart — the chart creates the internal image pull secret automatically. You do **not** need to pre-create a Kubernetes pull secret manually.

Confirm your JFrog credentials (`TP_CONTAINER_REGISTRY_USER` and `TP_CONTAINER_REGISTRY_PASSWORD`) are available before the Helm install step.

### Secrets Summary

| Secret Name | Namespace | Required | Notes |
|-------------|-----------|----------|-------|
| `session-keys` | `${CP_INSTANCE_ID}-ns` | Always | Create before `helm install tibco-cp-base` |
| `cporch-encryption-secret` | `${CP_INSTANCE_ID}-ns` | Always | Create before `helm install tibco-cp-base` |
| `rds-ca-cert` | `${CP_INSTANCE_ID}-ns` | Only for `verify-full` SSL | Contains AWS RDS CA bundle PEM |
| Container registry | Via Helm values | Always | Chart creates the pull secret automatically |

---

## 11. Security Requirements

| Requirement | Details |
|-------------|---------|
| **Network Policies** | VPC CNI with `enableNetworkPolicy: true` |
| **RBAC** | Standard Kubernetes RBAC |
| **IRSA** | IAM roles for Kubernetes service accounts via OIDC |
| **Secret Management** | `session-keys` and `cporch-encryption-secret` must be pre-created (see Section 10) |
| **Container Registry Auth** | JFrog credentials passed via Helm values; chart creates the pull secret |
| **Pod Security** | Standard pod security admission |

---

## 12. Capacity Planning

### Control Plane Resource Requirements

| Component | CPU Request | Memory Request | Storage |
|-----------|-------------|----------------|---------|
| CP core services | ~8 CPU | ~24 GB | EFS |
| Router pods | ~2 CPU | ~4 GB | — |
| Ingress controller | ~1 CPU | ~1 GB | — |
| cert-manager | ~0.5 CPU | ~1 GB | — |
| External DNS | ~0.1 CPU | ~256 MB | — |
| **Total (minimum)** | **~12 CPU** | **~30 GB** | EFS |

### Data Plane Resource Requirements

Resource requirements depend on the capabilities deployed (BWCE, Flogo, EMS). As a baseline:

| Component | CPU | Memory |
|-----------|-----|--------|
| Nginx ingress | ~0.5 CPU | ~512 MB |
| ECK (Elastic stack) | ~2 CPU | ~5 GB |
| Prometheus + Grafana | ~1 CPU | ~2 GB |
| TIBCO capabilities | Varies | Varies |

---

## 13. Pre-Installation Verification Checklist

Before beginning installation, verify each item:

**Infrastructure**

- [ ] EKS cluster created with Kubernetes 1.33+
- [ ] OIDC provider enabled on the cluster
- [ ] IRSA service accounts created for ALB controller, External DNS, cert-manager, EFS CSI, EBS CSI
- [ ] EKS addons installed: `vpc-cni`, `kube-proxy`, `coredns`, `aws-efs-csi-driver`, `aws-ebs-csi-driver`
- [ ] Amazon EFS created in the same VPC as the EKS cluster
- [ ] Amazon RDS Aurora PostgreSQL 16 created (for Control Plane)
- [ ] Route 53 hosted zone configured for the deployment domain
- [ ] ACM wildcard certificates in `ISSUED` status
- [ ] Outbound HTTPS (443) allowed from EKS cluster to internet
- [ ] Firewall allows all required domains (see section 7)

**Tools and Access**

- [ ] TIBCO JFrog container registry credentials available (`TP_CONTAINER_REGISTRY_USER` / `TP_CONTAINER_REGISTRY_PASSWORD`)
- [ ] `kubectl` configured with cluster admin access
- [ ] Helm 3.13+ installed
- [ ] `eksctl` 0.210.0+ installed
- [ ] AWS CLI configured with appropriate region and credentials
- [ ] `jq`, `yq`, `openssl`, and `envsubst` installed

**TIBCO Platform Control Plane**

- [ ] TIBCO Helm chart repository added (`helm repo add tibco-platform https://tibcosoftware.github.io/tp-helm-charts`)
- [ ] CP namespace (`${CP_INSTANCE_ID}-ns`) created with the correct label
- [ ] CP service account (`${CP_INSTANCE_ID}-sa`) created in CP namespace
- [ ] `session-keys` Kubernetes secret created in CP namespace
- [ ] `cporch-encryption-secret` Kubernetes secret created in CP namespace
- [ ] `rds-ca-cert` secret created (only if using `verify-full` SSL mode)
- [ ] `session-keys` and `cporch-encryption-secret` values saved to a secure vault (AWS Secrets Manager or equivalent)

---

## 14. Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
- [eksctl Documentation](https://eksctl.io/)
- [TIBCO Platform Documentation](https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm)
- [AWS Certificate Manager Guide](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)
- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [Firewall Requirements](../docs/firewall-requirements-eks)
- [CP and DP Setup Guide](how-to-cp-and-dp-eks-setup-guide)
- [Data Plane Only Setup Guide](how-to-dp-eks-setup-guide)
