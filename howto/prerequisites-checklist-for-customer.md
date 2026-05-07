---
layout: default
title: TIBCO Platform on EKS - Customer Prerequisites Checklist
---

# TIBCO Platform on EKS - Customer Prerequisites Checklist

**Document Purpose**: This checklist outlines the requirements that must be in place **before** TIBCO Platform Control Plane and Data Plane installation begins on Amazon Elastic Kubernetes Service (EKS).

**Target Audience**: Customer IT teams responsible for AWS infrastructure preparation

**Last Updated**: May 2026

---

## Overview

Before the TIBCO implementation team begins installation, please ensure all prerequisites listed in this document are met. This preparation is critical for a successful and timely deployment.

**Estimated Preparation Time**: 3-5 business days (depending on organizational processes)

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
| **Control Plane domains** | Wildcard certificates for `*.cp1-my.<domain>` and `*.cp1-tunnel.<domain>` |
| **Data Plane domain** | Wildcard certificate for `*.dp1.<domain>` |
| **External DNS** | Automatically manages records via IRSA |

---

## 5. SSL/TLS Certificate Requirements

| Requirement | Details |
|-------------|---------|
| **Certificate Provider** | AWS Certificate Manager (ACM) |
| **Certificate Type** | Wildcard public certificate (`*.cp1-my.<domain>`, `*.cp1-tunnel.<domain>`, `*.dp1.<domain>`) |
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

See [Firewall Requirements](../docs/firewall-requirements-eks.md) for the complete list.

---

## 8. TIBCO Platform Helm Chart Repository

| Requirement | Details |
|-------------|---------|
| **Helm Repo URL** | `https://tibcosoftware.github.io/tp-helm-charts` |
| **Add Repository** | `helm repo add tibco-platform https://tibcosoftware.github.io/tp-helm-charts` |
| **TIBCO CP Base Chart** | `tibco-cp-base` version `1.16.0` |
| **dp-config-aws Chart** | `dp-config-aws` version `^1.0.0` |

---

## 9. Storage Class Summary

| Storage Class | Provisioner | Used For | Required For |
|:-------------|:------------|:---------|:-------------|
| `efs-sc` | `efs.csi.aws.com` | CP storage, BWCE artifact manager, EMS log | Control Plane + Data Plane |
| `ebs-gp3` | `ebs.csi.aws.com` | EMS capability data storage | Data Plane only |
| `gp2` | `kubernetes.io/aws-ebs` | EKS default — avoid using | — |

---

## 10. Security Requirements

| Requirement | Details |
|-------------|---------|
| **Network Policies** | VPC CNI with `enableNetworkPolicy: true` |
| **RBAC** | Standard Kubernetes RBAC |
| **IRSA** | IAM roles for Kubernetes service accounts via OIDC |
| **Secret Management** | `session-keys` and `cporch-encryption-secret` must be pre-created |
| **Container Registry Auth** | JFrog credentials stored as Kubernetes image pull secret |
| **Pod Security** | Standard pod security admission |

---

## 11. Capacity Planning

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

## 12. Pre-Installation Verification Checklist

Before beginning installation, verify each item:

- [ ] EKS cluster created with Kubernetes 1.33+
- [ ] OIDC provider enabled on the cluster
- [ ] IRSA service accounts created for ALB controller, External DNS, cert-manager, EFS CSI, EBS CSI
- [ ] EKS addons installed: `vpc-cni`, `kube-proxy`, `coredns`, `aws-efs-csi-driver`, `aws-ebs-csi-driver`
- [ ] Amazon EFS created in the same VPC as the EKS cluster
- [ ] Amazon RDS Aurora PostgreSQL 16 created (for Control Plane)
- [ ] Route 53 hosted zone configured for the deployment domain
- [ ] ACM wildcard certificates in `ISSUED` status
- [ ] TIBCO JFrog container registry credentials available
- [ ] `kubectl` configured with cluster admin access
- [ ] Helm 3.13+ installed
- [ ] `eksctl` 0.210.0+ installed
- [ ] AWS CLI configured with appropriate region and credentials
- [ ] `jq`, `yq`, and `envsubst` installed
- [ ] Outbound HTTPS (443) allowed from EKS cluster to internet
- [ ] Firewall allows all required domains (see section 7)

---

## 13. Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
- [eksctl Documentation](https://eksctl.io/)
- [TIBCO Platform Documentation](https://docs.tibco.com/pub/platform-cp/latest/doc/html/Default.htm)
- [AWS Certificate Manager Guide](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html)
- [Amazon Route 53 Developer Guide](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html)
- [Firewall Requirements](../docs/firewall-requirements-eks.md)
- [CP and DP Setup Guide](how-to-cp-and-dp-eks-setup-guide.md)
- [Data Plane Only Setup Guide](how-to-dp-eks-setup-guide.md)
