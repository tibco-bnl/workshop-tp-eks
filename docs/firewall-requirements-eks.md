---
layout: default
title: Firewall Requirements for TIBCO Platform on EKS
---

# Firewall Requirements for TIBCO Platform on EKS

This document lists all external URLs and endpoints that need to be accessible for deploying TIBCO Platform on Amazon Elastic Kubernetes Service (EKS).

**Repository**: https://github.com/TIBCOSoftware/tp-helm-charts  
**Cloud Provider**: Amazon Web Services (AWS)  
**Last Updated**: June 11, 2026

---

## Official TIBCO Documentation References

Before configuring your firewall, review the official TIBCO Platform documentation:

- [TIBCO Platform Whitelisting Requirements](https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#UserGuide/whitelisting-requirements.htm) — Official Control Plane firewall requirements
- [Pushing Images to Custom Container Registry](https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#UserGuide/pushing-images-to-registry.htm) — Container registry authentication
- [TIBCO Platform Helm Charts Repository](https://github.com/TIBCOSoftware/tp-helm-charts) — Official Helm charts and deployment guides

---

## Summary

The TIBCO Platform deployment on EKS requires access to:
- **4 Container Registries** for pulling images (TIBCO JFrog, Docker Hub, Quay.io, GitHub)
- **6 Helm Chart Repositories** for downloading charts
- **8+ AWS-specific endpoints** for EKS, ECR, ELB, and other AWS services
- **2 Go Module Proxy endpoints** for Flogo applications

**Critical Requirements:**
1. **TIBCO JFrog Registry** (`csgprduswrepoedge.jfrog.io`) — All TIBCO Platform images
2. **TIBCO Helm Charts** (`tibcosoftware.github.io`) — Official Helm charts repository
3. **Go Module Proxy** (`proxy.golang.org`) — Required for Flogo applications unless built with Flogo CLI

---

## 1. Container Registries

### TIBCO Container Registry (Critical)

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `csgprduswrepoedge.jfrog.io` | 443 | HTTPS | TIBCO Platform production images (CP, DP, capabilities) |

Access requires JFrog credentials provided by TIBCO.

### Public Container Registries

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `docker.io` | 443 | HTTPS | Docker Hub — PostgreSQL, Jaeger |
| `registry-1.docker.io` | 443 | HTTPS | Docker Hub registry endpoint |
| `quay.io` | 443 | HTTPS | OAuth2 Proxy, Prometheus operator components |
| `ghcr.io` | 443 | HTTPS | GitHub Container Registry — TIBCO Message Gateway |

### AWS Container Registry

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `*.ecr.<region>.amazonaws.com` | 443 | HTTPS | Amazon ECR — EKS system images |
| `*.dkr.ecr.<region>.amazonaws.com` | 443 | HTTPS | ECR Docker registry endpoint |
| `public.ecr.aws` | 443 | HTTPS | Amazon ECR Public Gallery |

Replace `<region>` with your AWS region (e.g., `us-west-2`).

---

## 2. Helm Chart Repositories

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `https://tibcosoftware.github.io/tp-helm-charts` | 443 | HTTPS | **Primary** — TIBCO Platform official Helm charts |
| `https://charts.jetstack.io` | 443 | HTTPS | cert-manager charts |
| `https://helm.elastic.co` | 443 | HTTPS | Elastic ECK operator charts |
| `https://kubernetes-sigs.github.io/external-dns` | 443 | HTTPS | External DNS charts |
| `https://prometheus-community.github.io/helm-charts` | 443 | HTTPS | Prometheus and Grafana stack |
| `https://aws.github.io/eks-charts` | 443 | HTTPS | AWS EKS add-on charts (ALB controller) |
| `https://kubernetes-sigs.github.io/metrics-server` | 443 | HTTPS | Metrics Server charts |

---

## 3. AWS API Endpoints

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `*.eks.amazonaws.com` | 443 | HTTPS | EKS cluster API endpoints |
| `ec2.amazonaws.com` | 443 | HTTPS | EC2 API for node management |
| `elasticloadbalancing.amazonaws.com` | 443 | HTTPS | ELB API for ALB management |
| `autoscaling.amazonaws.com` | 443 | HTTPS | Auto Scaling API |
| `sts.amazonaws.com` | 443 | HTTPS | AWS STS for IRSA token exchange |
| `iam.amazonaws.com` | 443 | HTTPS | IAM API |
| `logs.amazonaws.com` | 443 | HTTPS | CloudWatch Logs |
| `monitoring.amazonaws.com` | 443 | HTTPS | CloudWatch Metrics |
| `s3.amazonaws.com` | 443 | HTTPS | S3 API endpoint |
| `*.s3.amazonaws.com` | 443 | HTTPS | S3 bucket access |
| `*.s3.<region>.amazonaws.com` | 443 | HTTPS | Regional S3 endpoints |
| `elasticfilesystem.amazonaws.com` | 443 | HTTPS | EFS API |
| `rds.amazonaws.com` | 443 | HTTPS | RDS API (Aurora PostgreSQL) |
| `route53.amazonaws.com` | 443 | HTTPS | Route 53 API (for External DNS) |
| `acm.amazonaws.com` | 443 | HTTPS | AWS Certificate Manager |

---

## 4. Go Module Proxy (Critical for Flogo)

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `https://proxy.golang.org` | 443 | HTTPS | **Critical** — Go module proxy for Flogo applications |
| `https://sum.golang.org` | 443 | HTTPS | Go checksum database for module verification |

> **Important:** Required for TIBCO Flogo applications NOT built using the Flogo CLI. Without access to `proxy.golang.org`, Flogo applications with external Go module dependencies will fail to start.
>
> **Workaround:** Build Flogo applications using the Flogo CLI to bundle all dependencies.

---

## 5. Source Code and Tools

| URL | Port | Protocol | Purpose |
|-----|------|----------|---------|
| `github.com` | 443 | HTTPS | Source code, releases, documentation |
| `*.githubusercontent.com` | 443 | HTTPS | GitHub raw content |
| `kubernetes.io` | 443 | HTTPS | Kubernetes documentation and API references |

---

## 6. Internal Cluster Communication (No Firewall Rules Needed)

These are internal cluster services that communicate within Kubernetes:

- `*.svc.cluster.local` — Internal Kubernetes service DNS
- `otel-userapp-traces.<namespace>.svc.cluster.local` — OTEL trace collector
- `otel-userapp-metrics.<namespace>.svc.cluster.local` — OTEL metrics collector
- `dp-config-es-es-http.elastic-system.svc.cluster.local` — Elasticsearch
- `kube-prometheus-stack-prometheus.prometheus-system.svc.cluster.local` — Prometheus
- `169.254.169.254` — AWS EC2 metadata service (node-local, no external access required)

---

## 7. Complete Outbound Firewall Rules Summary

### Required (Critical)

```
Protocol: HTTPS (TCP 443)
Destinations:
  # TIBCO Platform
  - csgprduswrepoedge.jfrog.io              # TIBCO images
  - tibcosoftware.github.io                  # TIBCO Helm charts
  
  # Container Registries
  - docker.io                                 # PostgreSQL, Jaeger
  - registry-1.docker.io                      # Docker Hub registry
  - quay.io                                   # OAuth2 Proxy, Prometheus
  - ghcr.io                                   # Message Gateway
  
  # Helm Repositories
  - charts.jetstack.io                        # cert-manager
  - helm.elastic.co                           # Elastic ECK
  - kubernetes-sigs.github.io                 # External DNS, Metrics Server
  - prometheus-community.github.io            # Prometheus stack
  - aws.github.io                             # AWS EKS charts
  
  # AWS Services
  - *.eks.amazonaws.com                       # EKS API
  - *.ecr.<region>.amazonaws.com              # ECR
  - *.dkr.ecr.<region>.amazonaws.com          # ECR Docker
  - ec2.amazonaws.com                         # EC2 API
  - elasticloadbalancing.amazonaws.com        # ELB API (ALB)
  - elasticfilesystem.amazonaws.com           # EFS API
  - rds.amazonaws.com                         # RDS API
  - sts.amazonaws.com                         # STS (for IRSA)
  - iam.amazonaws.com                         # IAM
  - route53.amazonaws.com                     # Route 53 (for External DNS)
  
  # Go Module Proxy (for Flogo)
  - proxy.golang.org                          # Go modules
  - sum.golang.org                            # Go checksum database
```

### Recommended

```
Protocol: HTTPS (TCP 443)
Destinations:
  - autoscaling.amazonaws.com                 # Auto Scaling
  - logs.amazonaws.com                        # CloudWatch Logs
  - monitoring.amazonaws.com                  # CloudWatch Metrics
  - s3.amazonaws.com                          # S3 API
  - *.s3.amazonaws.com                        # S3 buckets
  - *.s3.<region>.amazonaws.com               # Regional S3
  - public.ecr.aws                            # ECR Public
  - acm.amazonaws.com                         # Certificate Manager
  - github.com                                # GitHub
  - *.githubusercontent.com                   # GitHub raw content
```

### Optional

```
Protocol: HTTPS (TCP 443)
Destinations:
  - docs.tibco.com                            # TIBCO documentation
  - prometheus.io                             # Prometheus documentation
  - elastic.co                                # Elastic documentation
  - grafana.com                               # Grafana documentation
  - opentelemetry.io                          # OpenTelemetry documentation
```

---

## 8. AWS Security Group Configuration

If using AWS Security Groups on EKS nodes, create the following outbound rules:

### Outbound: HTTPS to Internet

```
Type: HTTPS
Protocol: TCP
Port Range: 443
Destination: 0.0.0.0/0
Description: Allow HTTPS for container registry, Helm charts, and AWS APIs
```

### Outbound: NFS to EFS

```
Type: NFS
Protocol: TCP
Port Range: 2049
Destination: EFS Mount Target Security Group
Description: Allow NFS for Amazon EFS access
```

> **Tip:** Use VPC endpoints for AWS services (ECR, S3, STS, EC2, ELB) to keep traffic within the AWS network and reduce data transfer costs.

---

## 9. VPC Endpoints (Recommended for Production)

Configure VPC endpoints to keep AWS API traffic off the public internet:

### Interface Endpoints (PrivateLink)

```
- com.amazonaws.<region>.ec2
- com.amazonaws.<region>.ecr.api
- com.amazonaws.<region>.ecr.dkr
- com.amazonaws.<region>.sts
- com.amazonaws.<region>.logs
- com.amazonaws.<region>.monitoring
- com.amazonaws.<region>.autoscaling
- com.amazonaws.<region>.elasticloadbalancing
- com.amazonaws.<region>.elasticfilesystem
- com.amazonaws.<region>.rds
```

### Gateway Endpoints

```
- com.amazonaws.<region>.s3
```

---

## 10. AWS Network Firewall Domain List (Most Restrictive)

For environments with AWS Network Firewall, create a stateful domain list rule group:

```yaml
# Required domains
- .jfrog.io                  # TIBCO registry
- tibcosoftware.github.io    # TIBCO Helm charts
- .docker.io                 # Docker Hub
- ghcr.io                    # GitHub Container Registry
- quay.io                    # Quay
- .github.io                 # Helm repositories on GitHub Pages
- charts.jetstack.io         # cert-manager
- helm.elastic.co            # ECK
- .amazonaws.com             # All AWS services
- .eks.amazonaws.com         # EKS API
- proxy.golang.org           # Go module proxy (Flogo)
- sum.golang.org             # Go checksum (Flogo)
```

---

## 11. Testing Connectivity from within EKS

Use these commands to verify connectivity from a pod within the cluster:

```bash
# Test TIBCO JFrog registry
kubectl run test-jfrog --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I https://csgprduswrepoedge.jfrog.io

# Test TIBCO Helm charts
kubectl run test-helm --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I https://tibcosoftware.github.io/tp-helm-charts/index.yaml

# Test AWS EKS charts
kubectl run test-eks-charts --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I https://aws.github.io/eks-charts/index.yaml

# Test AWS STS (required for IRSA)
kubectl run test-sts --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I https://sts.amazonaws.com

# Test Go module proxy (required for Flogo)
kubectl run test-goproxy --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I https://proxy.golang.org

# Test ECR Public
kubectl run test-ecr --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I https://public.ecr.aws
```

Alternatively, use the [connectivity test job](../scripts/connectivity-test-job.yaml) in the `scripts/` directory:

```bash
kubectl apply -f scripts/connectivity-test-job.yaml
kubectl logs -n kube-system job/tibco-connectivity-test
```

---

## 12. Troubleshooting

### Cannot Pull Images from JFrog

1. Verify outbound HTTPS (443) to `csgprduswrepoedge.jfrog.io`
2. Check JFrog credentials: `kubectl get secret -n <namespace> tibco-container-registry-credentials`
3. Test login: `docker login csgprduswrepoedge.jfrog.io`

### Helm Install Fails with "Failed to Download Chart"

1. Verify access to `tibcosoftware.github.io`
2. Test: `helm repo add tibco-platform https://tibcosoftware.github.io/tp-helm-charts && helm repo update`

### Flogo Applications Fail with Go Module Errors

1. Verify access to `proxy.golang.org` and `sum.golang.org`
2. Check pod logs: `kubectl logs <flogo-pod> | grep -i "proxy.golang.org"`
3. **Workaround**: Build Flogo applications using Flogo CLI to bundle all dependencies

### ALB Not Being Created

1. Verify `aws-load-balancer-controller` is running: `kubectl get pods -n kube-system | grep load-balancer`
2. Verify IRSA service account annotation: `kubectl get sa aws-load-balancer-controller -n kube-system -o yaml`
3. Check controller logs: `kubectl logs -n kube-system deploy/aws-load-balancer-controller`
4. Ensure access to `elasticloadbalancing.amazonaws.com`

### External DNS Not Creating Route 53 Records

1. Check External DNS logs: `kubectl logs -n external-dns-system deploy/external-dns`
2. Verify IRSA role has Route 53 permissions
3. Verify hosted zone domain filter matches your domain

---

## Additional Resources

- [TIBCO Platform Whitelisting Requirements](https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm#UserGuide/whitelisting-requirements.htm)
- [AWS EKS Network Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [AWS VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [AWS Network Firewall](https://docs.aws.amazon.com/network-firewall/latest/developerguide/what-is-aws-network-firewall.html)
- [Go Module Proxy](https://proxy.golang.org)
- [Prerequisites Checklist](../howto/prerequisites-checklist-for-customer)
