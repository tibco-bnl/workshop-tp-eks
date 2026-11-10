# TIBCO Platform on Amazon EKS Workshop

This repository contains workshop guides for deploying TIBCO Platform on Amazon Elastic Kubernetes Service (EKS). It covers full Control Plane plus Data Plane deployments, Data Plane-only deployments, DNS, storage, observability, prerequisites, and optional Azure DevOps automation.

> **Current release:** [v1.22.0](./releases/v1.22.0)
> **TIBCO Platform Control Plane:** 1.22.0
> **Upgrading from 1.18.0?** Upgrade to 1.19.0, then 1.20.0, then 1.21.0, then 1.22.0; see the [1.22.0 upgrade path](./releases/v1.22.0#upgrade-from-1210).

> **Workshop scope:** These guides are for evaluation, development, demos, and workshops. For production deployments, work with TIBCO Support, TIBCO SI Partners, or your TIBCO account team and follow the official TIBCO Platform documentation.

## Start Here

| Goal | Primary guide |
|------|---------------|
| Plan CP/DP topology, DTAP, and subscription strategy | [Topology options](./howto/topology-options) |
| Deploy Control Plane and Data Plane on one EKS cluster | [CP + DP setup guide](./howto/how-to-cp-and-dp-eks-setup-guide) |
| Apply 1.22-specific install or upgrade notes | [v1.22 quick reference](./howto/v1.22/QUICK-REFERENCE) |
| Pass through 1.19 when upgrading from 1.18 | [v1.19 overlay](./howto/v1.19/how-to-cp-and-dp-eks-setup-guide) |
| Connect an EKS Data Plane to an existing Control Plane | [Data Plane-only guide](./howto/how-to-dp-eks-setup-guide) |
| Configure Route 53 and DNS records | [Route 53 DNS guide](./howto/how-to-add-dns-records-eks-aws) |
| Install logs, metrics, traces, and dashboards | [Data Plane observability guide](./howto/how-to-dp-eks-observability) |
| Check customer readiness before install | [Prerequisites checklist](./howto/prerequisites-checklist-for-customer) |
| Review AWS firewall and endpoint access | [Firewall requirements](./docs/firewall-requirements-eks) |

## Current Release Highlights

TIBCO Platform 1.22.0 on EKS adds resource customization for infrastructure components on Kubernetes and Control Tower Data Planes, on-demand installation of Control Tower infrastructure components, an Application Operator permission, application log download from the Control Plane UI, Amazon Bedrock and an EMS MCP server for TESSA, new BW5/BW6 alert categories (Instance Count and App Status), a BW5 REST API for Control Tower, and Flogo password-type engine variables. NGINX Ingress Controller support is removed from TIBCO Operated Control Plane. Self-hosted upgrades also include a `tp-cp-o11y` values layout change handled by the upgrade assistant.

For version-specific features, chart versions, known issues, and upgrade requirements, see the [v1.22.0 release notes](./releases/v1.22.0) and [v1.22 quick reference](./howto/v1.22/QUICK-REFERENCE). The EKS guides continue to use Aurora with `rds.force_ssl=1`; retain the EKS storage, identity, networking, and DNS prerequisites.

## Release Matrix

| Version | Status | Where to start |
|---------|--------|----------------|
| 1.22.0 | Current, recommended for new deployments | [Release notes](./releases/v1.22.0), [quick reference](./howto/v1.22/QUICK-REFERENCE) |
| 1.21.0 | Previous release | [Release notes](./releases/v1.21.0), [quick reference](./howto/v1.21/QUICK-REFERENCE) |
| 1.20.0 | Previous release | [Release notes](./releases/v1.20.0), [historical overlay](./howto/v1.20/how-to-cp-and-dp-eks-setup-guide) |
| 1.19.0 | Previous release, mandatory hop from 1.18.0 | [Release notes](./releases/v1.19.0), [v1.19 overlay](./howto/v1.19/how-to-cp-and-dp-eks-setup-guide) |
| 1.18.0 | Older reference | [Release notes](./releases/v1.18.0), [v1.18 overlay](./howto/v1.18/how-to-cp-and-dp-eks-setup-guide) |
| 1.17.0 | Older reference | [Release notes](./releases/v1.17.0), [v1.17 quick reference](./howto/v1.17/QUICK-REFERENCE) |
| 1.16.0 | Older reference | [Release notes](./releases/v1.16.0) |

## Upgrade Paths

| From | To | Guide |
|------|----|-------|
| 1.21.0 | 1.22.0 | [Upgrade path](./releases/v1.22.0#upgrade-from-1210) |
| 1.20.0 | 1.21.0 | [Upgrade path](./releases/v1.21.0#upgrade-from-1200) |
| 1.19.0 | 1.20.0 | [Upgrade path](./releases/v1.20.0#upgrade-path-from-v1190) |
| 1.18.0 | 1.19.0 | [Upgrade path](./releases/v1.19.0#upgrade-path-from-v1180) |
| 1.17.0 | 1.18.0 | [Upgrade path](./releases/v1.18.0#upgrade-path-from-v1170) |

The official upgrade assistants in `tp-helm-charts/scripts/<version>/upgrade.sh` move one minor version at a time; use `scripts/MASTER-UPGRADE-README.md` for multi-hop upgrades.

## Deployment Paths

### Full Platform on EKS

Use this path for workshops, evaluations, demos, and standalone development environments. It deploys TIBCO Platform Control Plane and Data Plane into the same EKS cluster with Aurora PostgreSQL, EFS, EBS gp3, Route 53, ACM, ALB, and Traefik (or optionally Gateway API).

Start with the [CP + DP setup guide](./howto/how-to-cp-and-dp-eks-setup-guide), then review the [v1.22 quick reference](./howto/v1.22/QUICK-REFERENCE) and current release notes.

### EKS Data Plane Only

Use this path when a Control Plane already exists, such as TIBCO Platform SaaS or a self-hosted Control Plane in another cluster. It sets up the EKS Data Plane, storage, ingress, DNS, and optional observability.

Start with the [Data Plane-only guide](./howto/how-to-dp-eks-setup-guide).

### Observability

Use this path when you need logs, metrics, traces, dashboards, and troubleshooting data for Data Plane workloads.

Start with the [Data Plane observability guide](./howto/how-to-dp-eks-observability).

## Required Tools

Install and configure these before starting. Confirm current AWS/eksctl availability and the TIBCO 1.22 system requirements:

| Tool | Recommended version |
|------|---------------------|
| AWS CLI | 2.27.31+ |
| eksctl | 0.210.0+ |
| kubectl | v1.34.3+ |
| Helm | 3.17.0+ (3.18.0 tested upstream) |
| jq | 1.8.0+ |
| yq | 4.45.4+ |
| envsubst | gettext 0.24.1+ |

You also need AWS permissions for EKS, IAM, EC2/VPC, Route 53, ACM, EFS, EBS, and RDS, plus access to the TIBCO container registry and Helm charts.

## Platform Baseline

| Area | Baseline |
|------|----------|
| Kubernetes | TIBCO 1.22.0 certifies Kubernetes 1.35; confirm regional EKS availability |
| Worker nodes | 3+ `m5a.xlarge` or larger for CP + DP workshops |
| Database | Amazon Aurora PostgreSQL 16 with `rds.force_ssl=1` |
| Storage | Amazon EFS for shared files, Amazon EBS gp3 for block storage |
| DNS and TLS | Route 53 hosted zone and ACM wildcard certificate |
| Ingress and Gateway API | AWS ALB with Traefik 3.3.4 for the baseline (NGINX Ingress Controller support is removed); optional Gateway API with NGINX Gateway Fabric 2.3.0, Traefik `traefik-39.0.7`, Istio 1.28.2, or NetScaler |
| AWS identity | IAM Roles for Service Accounts (IRSA) |

## Repository Map

```text
workshop-tp-eks/
|-- howto/
|   |-- topology-options.md
|   |-- how-to-cp-and-dp-eks-setup-guide.md
|   |-- how-to-dp-eks-setup-guide.md
|   |-- how-to-dp-eks-observability.md
|   |-- how-to-add-dns-records-eks-aws.md
|   |-- how-to-sync-images.md
|   |-- prerequisites-checklist-for-customer.md
|   |-- v1.22/                      # current release quick reference
|   |-- v1.21/                      # previous release quick reference
|   |-- v1.20/                      # historical release overlay
|   |   |-- how-to-cp-and-dp-eks-setup-guide.md
|   |   |-- QUICK-REFERENCE.md
|   |   `-- DOCUMENTATION-SUMMARY.md
|   |-- v1.19/                      # upgrade hop from 1.18
|   |-- v1.18/
|   `-- v1.17/
|-- docs/
|   `-- firewall-requirements-eks.md
|-- pipelines/azure-devops/
|-- releases/                       # v1.16.0 ... v1.22.0
`-- scripts/env.sh
```

## Automation

The [Azure DevOps pipeline folder](https://github.com/tibco-bnl/workshop-tp-eks/tree/main/pipelines/azure-devops) includes three ready-to-import pipelines:

| Pipeline | Purpose |
|----------|---------|
| [test-postgres-connectivity.yml](./pipelines/azure-devops/test-postgres-connectivity.yml) | Validate Aurora PostgreSQL connectivity from inside EKS before deploying Control Plane |
| [deploy-tibco-control-plane.yml](./pipelines/azure-devops/deploy-tibco-control-plane.yml) | Create prerequisites, generate `tibco-cp-base` values, deploy Control Plane (default chart 1.22.0), and verify access |
| [check-namespace-health.yml](./pipelines/azure-devops/check-namespace-health.yml) | Scheduled or manual CP/DP namespace diagnostics for pods, PVCs, events, ingresses, secrets, and node pressure |

All pipelines expect an Azure DevOps variable group named `tibco-platform-eks-secrets`; production use should link it to Azure Key Vault.

## Configuration

Source [scripts/env.sh](./scripts/env.sh) before running guide commands, then override values for your AWS account, EKS cluster, hosted zone, certificates, database, registry, and TIBCO Platform settings.

```bash
source scripts/env.sh
export TP_CLUSTER_NAME="my-eks-cluster"
export TP_HOSTED_ZONE_DOMAIN="aws.example.com"
export TP_CONTAINER_REGISTRY_USER="my-jfrog-user"
export TP_CONTAINER_REGISTRY_PASSWORD="my-jfrog-token"
```

The guide also references upstream AWS helper scripts maintained in the official [tp-helm-charts EKS workshop directory](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks). Release validation can use [scripts/verify-release.sh](https://github.com/TIBCOSoftware/tp-helm-charts/blob/main/scripts/verify-release.sh) from the same repository.

## Image Synchronization

If your EKS cluster cannot reach the TIBCO JFrog registry directly, mirror images to an internal registry (e.g., Amazon ECR) before installation. See the full guide for safe copy methods, ECR setup, and image integrity verification:

- [How to push TIBCO Platform images to a custom container registry](./howto/how-to-sync-images)

> **Important**: Do not use `docker push` or `podman push` for BusinessWorks plugin images. Use the official `sync-images.sh` script or `docker buildx imagetools` / `skopeo copy --format v2s2` to preserve GZIP layer integrity. See the guide for details.

## Troubleshooting

Start with these checks before raising a support ticket:

1. Run [check-namespace-health.yml](./pipelines/azure-devops/check-namespace-health.yml) if you use Azure DevOps automation.
2. Review pod, event, PVC, ingress, and node-pressure findings in the affected namespace.
3. Verify Route 53 records, ACM certificate ARN, ALB status, EFS/EBS CSI drivers, and Aurora PostgreSQL connectivity.
4. Compare your generated Helm values with the current guide and [v1.22 quick reference](./howto/v1.22/QUICK-REFERENCE).
5. If an upgrade fails, follow the version-specific recovery guidance and record Helm history before retrying.

## Official References

- [TIBCO Platform Control Plane 1.22.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.22.0/doc/html/Default.htm)
- [TIBCO Platform Control Plane 1.19.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.19.0/doc/html/Default.htm)
- [TIBCO Helm Charts Repository](https://github.com/TIBCOSoftware/tp-helm-charts)
- [Official EKS workshop assets in tp-helm-charts](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks)
- [Official upgrade scripts (including 1.22.0)](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/scripts)
- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [eksctl Documentation](https://eksctl.io/)

## Related Workshops

- [TIBCO Platform on AKS Workshop](https://github.com/tibco-bnl/workshop-tp-aks)
- [TIBCO Platform on ARO Workshop](https://github.com/tibco-bnl/workshop-tp-aro)

## License

This project is licensed under the Apache License 2.0. See [LICENSE](https://github.com/tibco-bnl/workshop-tp-eks/blob/main/LICENSE) for details.

**Maintained by:** TIBCO-BNL Team
**Last updated:** September 21, 2026
