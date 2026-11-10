# TIBCO Platform 1.22.0 Quick Reference (EKS)

Use this page alongside the [1.22.0 release notes](../../releases/v1.22.0), the shared [EKS CP + DP setup guide](../how-to-cp-and-dp-eks-setup-guide), and the [official 1.22.0 documentation](https://docs.tibco.com/pub/platform-cp/1.22.0/doc/html/Default.htm).

## Upgrade sequence from 1.21.0

1. Back up Aurora PostgreSQL, Helm values, Kubernetes secrets, and record `helm history`.
2. For custom registries, mirror the 1.22.0 images from the official artifact manifests before upgrading.
3. Run the official [1.22.0 upgrade assistant](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/scripts/1.22.0). It requires a deployed Control Plane at `app_version` 1.21.0.
4. Upgrade decoupled Control Plane capability charts using the exact artifact versions.
5. Upgrade Data Plane infrastructure and capabilities through the Control Plane UI, including observability; prefer its generated commands.
6. Verify chart versions and workload health.
7. Optional: remove the stale `o11y-exporter.yaml` recipe described in the [official upgrade guide](https://docs.tibco.com/pub/platform-cp/1.22.0/doc/html/Installation/upgrading-from-previous-version.htm) (no functional impact if left).

The assistant requires Bash 4+, yq 4.45.4+, Helm 3.17+ and jq 1.8+ for Helm flows, and kubectl for readiness checks. It migrates `tp-cp-o11y.capabilities.o11y.default` / `.withResources` into `tp-cp-o11y.capabilities.o11y` (keeping `overwriteRecipe`); leaves all other values unchanged. Review values and custom-registry image contents before use.

## 1.22.0 reference chart versions

| Chart | Version |
|---|---:|
| `tibco-cp-base` | 1.22.0 |
| `tibco-cp-bw` / `tibco-cp-flogo` / `tibco-cp-devhub` | 1.22.0 |
| `tibco-cp-hawk` / `tibco-cp-messaging` | 1.22.14 / 1.22.14 |
| `tibco-cp-mcp-hub` / `tibco-cp-addon-eventprocessing` | 1.22.0 / 1.22.0 |
| `dp-configure-namespace` / `dp-core-infrastructure` | 1.22.3 / 1.22.5 |
| `tibco-developer-hub` | 1.22.12 |
| `tp-dp-monitor-agent` / `o11yservice` | 1.22.5 / 1.22.29 |
| `jaeger` / `opentelemetry-collector` | 4.8.5 / 0.156.5 |
| EMS / ActiveSpaces charts | `msg-ems-tp` 1.22.14 / `msg-activespaces-tp` 1.22.14 |

Consult all 1.22.0 artifact files for charts not listed here and for the exact images to mirror.

## 1.22 operations to account for

- NGINX Ingress Controller support is removed from TIBCO Operated Control Plane; TIBCO no longer officially supports or recommends it with Control Plane and Data Planes. Prefer Traefik or a supported Gateway API controller for new EKS deployments. If you keep an existing `dp-config-aws-nginx` Data Plane, see PCP-16403 below.
- Application Operator permission: start/stop/restart/scale and environment variables, no delete; can be scoped to a Data Plane namespace.
- Application logs (history as text/CSV, real-time as text) can be downloaded from the Control Plane UI. On a Data Plane that is not yet upgraded to 1.22 (including observability) the download returns 404 (PCP-25998).
- Infrastructure component resources (CPU, memory, storage) can be customized in the Data Plane configuration page. Customized observability values reset after an observability resource update (PCP-26766).
- The 1.21 Data Plane registration behavior is unchanged in 1.22: hybrid connectivity is enabled by default; if you disable it, **Reachable DP URL** must be the `cpdpproxy` service URL reachable from the Control Plane, not the ALB DNS name or application domain. AWS ALB is not listed as an ingress-controller type there. For capability Gateway API provisioning, choose **Other** for an unlisted Kubernetes Gateway API controller and provide its `GatewayClass` and Gateway details.
- TESSA can use Amazon Bedrock in your AWS account as an alternative to a customer-provided OpenAI key, and can query EMS through the EMS MCP server. TESSA write operations remain disabled until a subscription owner enables them.
- Keep the EKS-specific Aurora `rds.force_ssl` configuration, EFS/EBS storage, and AWS identity prerequisites. Kubernetes 1.35 certification is unchanged; confirm EKS availability.

## Known issue checks

- PCP-26766: customized observability values reset after updating observability resource configuration; no workaround.
- PCP-25998: log download returns 404 on a not-yet-upgraded Data Plane; upgrade the Data Plane (and its observability capability) to 1.22.
- PCP-27651: Capability Provisioner and Fluent Bit sidecar error logs on BW6 (Containers) after upgrading infrastructure to 1.22.0.
- PCP-16403: removing `use-forwarded-header:true` from `dp-config-aws-nginx-ingress-nginx-controller` breaks the BW app Swagger UI; no workaround.

Review the [official known issues](https://docs.tibco.com/pub/platform-cp/1.22.0/doc/html/Release-Notes/known-issues.htm) before upgrading.
