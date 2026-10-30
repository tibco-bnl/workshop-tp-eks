# TIBCO Platform 1.21.0 Quick Reference (EKS)

Use this page alongside the [1.21.0 release notes](../../releases/v1.21.0), the shared [EKS CP + DP setup guide](../how-to-cp-and-dp-eks-setup-guide), and the [official 1.21.0 documentation](https://docs.tibco.com/pub/platform-cp/1.21.0/doc/html/Default.htm).

## Upgrade sequence from 1.20.0

1. Back up Aurora PostgreSQL, Helm values, Kubernetes secrets, and record `helm history`.
2. For custom registries, mirror the 1.21.0 images from the official artifact manifests before upgrading.
3. Run the official [1.21.0 upgrade assistant](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/scripts/1.21.0). It requires a deployed Control Plane at `app_version` 1.20.0.
4. Upgrade decoupled Control Plane capability charts using the exact artifact versions.
5. Upgrade Data Plane infrastructure and capabilities through the Control Plane UI; prefer its generated commands.
6. Verify chart versions and workload health.

The assistant requires Bash 4+, yq 4.45.4+, Helm 3.17+ and jq 1.8+ for Helm flows, and kubectl for readiness checks. The current assistant README defines no 1.21-specific value transformations. Review values and custom-registry image contents before use.

## 1.21.0 reference chart versions

| Chart | Version |
|---|---:|
| `tibco-cp-base` | 1.21.0 |
| `tibco-cp-bw` / `tibco-cp-flogo` / `tibco-cp-devhub` | 1.21.0 |
| `tibco-cp-hawk` / `tibco-cp-messaging` | 1.21.23 / 1.21.23 |
| `tibco-cp-mcp-hub` | 1.21.0 |
| `dp-configure-namespace` / `dp-core-infrastructure` | 1.21.4 / 1.21.4 |
| `tibco-developer-hub` | 1.21.11 |
| `tp-dp-monitor-agent` / `o11yservice` | 1.21.8 / 1.21.9 |
| `jaeger` / `opentelemetry-collector` | 4.8.3 / 0.156.3 |
| EMS / ActiveSpaces charts | `msg-ems-tp` 1.21.20 / `msg-activespaces-tp` 1.21.20 |

Consult all 1.21.0 artifact files for charts not listed here and for the exact images to mirror.

## 1.21 operations to account for

- Kubernetes Secret authentication for a custom registry is configured through cluster registration; create the secret in every applicable Data Plane namespace.
- Hybrid connectivity is configurable per Data Plane. Registration can use an existing ingress or Gateway API controller; inspect the generated commands.
- Native Control Tower is Preview for supported Linux x86_64 hosts and does not require Kubernetes.
- TESSA writes remain disabled until a subscription owner enables them and configures appropriate per-tool guardrails.
- Maintenance Mode blocks user-initiated writes; it does not stop applications, agents, or internal platform services.
- Keep the EKS-specific Aurora `rds.force_ssl` configuration, EFS/EBS storage, and AWS identity prerequisites.

## Known issue checks

- PCP-24968: reconfigure LDAP group permissions after changing an LDAP configuration if login is denied.
- PCP-24894: ActiveSpaces incorrectly appears in two user-role assignment flows; no workaround is documented.
- PCP-24555: use the UI, not `tibcop --ems-use`, to provision EMS in the Production Kubernetes environment.

Review the [official known issues](https://docs.tibco.com/pub/platform-cp/1.21.0/doc/html/Release-Notes/known-issues.htm) before upgrading.
