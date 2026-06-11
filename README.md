# TIBCO Platform on Amazon EKS Workshop

This repository contains workshop guides for deploying TIBCO Platform on Amazon Elastic Kubernetes Service (EKS). It covers full Control Plane plus Data Plane deployments, Data Plane-only deployments, DNS, storage, observability, prerequisites, and optional Azure DevOps automation.

> **Current release:** [v1.18.0](./releases/v1.18.0)
> **TIBCO Platform Control Plane:** 1.18.0
> **Upgrading from 1.17.0?** Start with the [v1.18.0 release notes](./releases/v1.18.0#upgrade-path-from-v1170).

> **Workshop scope:** These guides are for evaluation, development, demos, and workshops. For production deployments, work with TIBCO Support, TIBCO SI Partners, or your TIBCO account team and follow the official TIBCO Platform documentation.

## Start Here

| Goal | Primary guide |
|------|---------------|
| Deploy Control Plane and Data Plane on one EKS cluster | [CP + DP setup guide](./howto/how-to-cp-and-dp-eks-setup-guide) |
| Apply 1.18-specific install or upgrade notes | [v1.18 overlay](./howto/v1.18/how-to-cp-and-dp-eks-setup-guide) |
| Connect an EKS Data Plane to an existing Control Plane | [Data Plane-only guide](./howto/how-to-dp-eks-setup-guide) |
| Configure Route 53 and DNS records | [Route 53 DNS guide](./howto/how-to-add-dns-records-eks-aws) |
| Install logs, metrics, traces, and dashboards | [Data Plane observability guide](./howto/how-to-dp-eks-observability) |
| Check customer readiness before install | [Prerequisites checklist](./howto/prerequisites-checklist-for-customer) |
| Review AWS firewall and endpoint access | [Firewall requirements](./docs/firewall-requirements-eks) |

## Current Release Highlights

TIBCO Platform 1.18.0 on EKS keeps the 1.17 simplified DNS model and adds these operator-facing updates:

- **Simplified DNS continues:** use one Route 53 base domain and one ACM wildcard certificate for admin, subscription, and tunnel traffic.
- **Console-managed email:** configure SES, SMTP, SendGrid, or Microsoft Graph in Platform Console. Do not put deprecated email provider settings in `tibco-cp-base` Helm values.
- **Gateway API evaluation path:** Traefik Gateway API can be evaluated for supported BW5, BW6, and Flogo endpoint exposure.
- **Namespace-level RBAC:** Application Manager and Application Viewer access can be scoped by Data Plane namespace.
- **Alert Audit Trail:** alert health and rule-performance events are available in the UI.
- **Aurora PostgreSQL SSL guidance:** use `require` or `verify-full` when `rds.force_ssl=1` is enforced.

For details, see the [v1.18.0 release notes](./releases/v1.18.0), [v1.18 quick reference](./howto/v1.18/QUICK-REFERENCE), and [v1.18 documentation summary](./howto/v1.18/DOCUMENTATION-SUMMARY).

## Release Matrix

| Version | Status | Where to start |
|---------|--------|----------------|
| 1.18.0 | Current, recommended for new deployments | [Release notes](./releases/v1.18.0), [v1.18 overlay](./howto/v1.18/how-to-cp-and-dp-eks-setup-guide) |
| 1.17.0 | Previous release | [Release notes](./releases/v1.17.0), [v1.17 quick reference](./howto/v1.17/QUICK-REFERENCE) |
| 1.16.0 | Older reference | [Release notes](./releases/v1.16.0) |

## Deployment Paths

### Full Platform on EKS

Use this path for workshops, evaluations, demos, and standalone development environments. It deploys TIBCO Platform Control Plane and Data Plane into the same EKS cluster with Aurora PostgreSQL, EFS, EBS gp3, Route 53, ACM, ALB, and Nginx or Traefik.

Start with the [CP + DP setup guide](./howto/how-to-cp-and-dp-eks-setup-guide), then apply the [v1.18 overlay](./howto/v1.18/how-to-cp-and-dp-eks-setup-guide) for current-release changes.

### EKS Data Plane Only

Use this path when a Control Plane already exists, such as TIBCO Platform SaaS or a self-hosted Control Plane in another cluster. It sets up the EKS Data Plane, storage, ingress, DNS, and optional observability.

Start with the [Data Plane-only guide](./howto/how-to-dp-eks-setup-guide).

### Observability

Use this path when you need logs, metrics, traces, dashboards, and troubleshooting data for Data Plane workloads.

Start with the [Data Plane observability guide](./howto/how-to-dp-eks-observability).

## Required Tools

Install and configure these before starting:

| Tool | Recommended version |
|------|---------------------|
| AWS CLI | 2.27.0+ |
| eksctl | 0.210.0+ |
| kubectl | Latest stable |
| Helm | 3.13.0+ |
| jq | 1.8.0+ |
| yq | 4.45.4+ |
| envsubst | gettext 0.24.1+ |

You also need AWS permissions for EKS, IAM, EC2/VPC, Route 53, ACM, EFS, EBS, and RDS, plus access to the TIBCO container registry and Helm charts.

## Platform Baseline

| Area | Baseline |
|------|----------|
| Kubernetes | EKS 1.33+ |
| Worker nodes | 3+ `m5a.xlarge` or larger for CP + DP workshops |
| Database | Amazon Aurora PostgreSQL 16 recommended |
| Storage | Amazon EFS for shared files, Amazon EBS gp3 for block storage |
| DNS and TLS | Route 53 hosted zone and ACM wildcard certificate |
| Ingress | AWS ALB with Nginx or Traefik for platform routes |
| AWS identity | IAM Roles for Service Accounts (IRSA) |

## Repository Map

```text
workshop-tp-eks/
|-- howto/
|   |-- how-to-cp-and-dp-eks-setup-guide.md
|   |-- how-to-dp-eks-setup-guide.md
|   |-- how-to-dp-eks-observability.md
|   |-- how-to-add-dns-records-eks-aws.md
|   |-- prerequisites-checklist-for-customer.md
|   `-- v1.18/
|       |-- how-to-cp-and-dp-eks-setup-guide.md
|       |-- QUICK-REFERENCE.md
|       `-- DOCUMENTATION-SUMMARY.md
|-- docs/
|   `-- firewall-requirements-eks.md
|-- pipelines/azure-devops/
|-- releases/
`-- scripts/env.sh
```

## Automation

The [Azure DevOps pipeline folder](https://github.com/tibco-bnl/workshop-tp-eks/tree/main/pipelines/azure-devops) includes three ready-to-import pipelines:

| Pipeline | Purpose |
|----------|---------|
| [test-postgres-connectivity.yml](./pipelines/azure-devops/test-postgres-connectivity.yml) | Validate Aurora PostgreSQL connectivity from inside EKS before deploying Control Plane |
| [deploy-tibco-control-plane.yml](./pipelines/azure-devops/deploy-tibco-control-plane.yml) | Create prerequisites, generate `tibco-cp-base` values, deploy Control Plane, and verify access |
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

The guide also references upstream AWS helper scripts maintained in the official [tp-helm-charts EKS workshop directory](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks).

## Troubleshooting

Start with these checks before raising a support ticket:

1. Run [check-namespace-health.yml](./pipelines/azure-devops/check-namespace-health.yml) if you use Azure DevOps automation.
2. Review pod, event, PVC, ingress, and node-pressure findings in the affected namespace.
3. Verify Route 53 records, ACM certificate ARN, ALB status, EFS/EBS CSI drivers, and Aurora PostgreSQL connectivity.
4. Compare your generated Helm values with the current guide and [v1.18 quick reference](./howto/v1.18/QUICK-REFERENCE).

## Official References

- [TIBCO Platform Control Plane 1.18.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.18.0/doc/html/Default.htm)
- [TIBCO Helm Charts Repository](https://github.com/TIBCOSoftware/tp-helm-charts)
- [Official EKS workshop assets in tp-helm-charts](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks)
- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [eksctl Documentation](https://eksctl.io/)

## Related Workshops

- [TIBCO Platform on AKS Workshop](https://github.com/tibco-bnl/workshop-tp-aks)
- [TIBCO Platform on ARO Workshop](https://github.com/tibco-bnl/workshop-tp-aro)

## License

This project is licensed under the Apache License 2.0. See [LICENSE](https://github.com/tibco-bnl/workshop-tp-eks/blob/main/LICENSE) for details.

**Maintained by:** TIBCO-BNL Team
**Last updated:** June 11, 2026
