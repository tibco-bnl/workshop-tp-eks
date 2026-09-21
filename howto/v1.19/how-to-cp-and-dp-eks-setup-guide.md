---
layout: default
title: TIBCO Platform 1.19.0 CP and DP Setup Overlay on EKS
---

# TIBCO Platform 1.19.0 CP and DP Setup Overlay on EKS

Use this guide as the 1.19.0 overlay for the common EKS CP+DP setup. The base EKS cluster, Route 53 hosted zone, ALB controller, External DNS, EFS/EBS storage, Aurora PostgreSQL, ACM certificate, and Traefik setup remain in the shared [CP and DP setup guide](../how-to-cp-and-dp-eks-setup-guide).

1.19.0 is the mandatory intermediate step between 1.18.0 and the current 1.20.0 release. For new installations go straight to the [1.20.0 overlay](../v1.20/how-to-cp-and-dp-eks-setup-guide).

## Start Here

1. Complete the shared baseline: [shared EKS CP + DP setup guide](../how-to-cp-and-dp-eks-setup-guide).
2. Use 1.18.0 as the direct upgrade source: [1.18.0 release notes](../../releases/v1.18.0).
3. Apply the 1.19.0-specific changes below, then continue with the [1.20.0 overlay](../v1.20/how-to-cp-and-dp-eks-setup-guide).

```bash
helm repo add tibco-platform https://tibcosoftware.github.io/tp-helm-charts
helm repo update tibco-platform
```

## 1.19.0 Chart Versions

From the 1.19.0 artifact manifests in the official `tp-helm-charts` repository.

| Area | Chart | Version |
|------|-------|---------|
| Control Plane | `tibco-cp-base` | `1.19.0` |
| Control Plane | `tp-cp-proxy` | `1.19.1` |
| Control Plane | `artifactmanager` | `1.19.4` |
| Control Plane | `o11yservice` | `1.19.16` |
| Control Plane | `tp-dp-monitor-agent` | `1.19.11` |
| Control Plane | `jaeger` | `4.8.2` |
| Data Plane | `dp-configure-namespace` | `1.19.10` |
| Data Plane | `dp-core-infrastructure` | `1.19.5` |
| BW | `tibco-cp-bw` | `1.19.0` |
| BW | `bwprovisioner` / `bw5provisioner` | `1.19.7` |
| BW | `dp-bwce-app` / `dp-bw5ce-app` | `1.19.6` |
| Flogo | `tibco-cp-flogo` | `1.19.0` |
| Flogo | `flogoprovisioner` | `1.19.11` |
| Flogo | `dp-flogo-app` | `1.19.13` |
| Developer Hub | `tibco-cp-devhub` | `1.19.0` |
| Developer Hub | `tibco-developer-hub` | `1.19.8` |
| Hawk | `tibco-cp-hawk` / `tp-dp-hawk-console` | `1.19.23` |
| Messaging | `tibco-cp-messaging` / `msg-ems-tp` / `msg-activespaces-tp` | `1.19.23` |
| MCP | `tp-dp-infra-mcp-server` | `1.19.0` |

## 1.19.0 Changes to Apply

### Control Plane Base Chart

```bash
helm upgrade --install --wait --timeout 1h --create-namespace \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco-cp-base \
  --labels layer=1 \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.19.0" \
  -f aws-tibco-cp-base-values.yaml
```

Or use the assistant from `tp-helm-charts`, which validates that the release is `deployed` at `app_version` 1.18.0 before upgrading:

```bash
cd tp-helm-charts/scripts/1.19.0 && ./upgrade.sh
```

### Remove `createDeprecatedPolicies`

`tibco-cp-base` 1.19.0 removes `global.tibco.networkPolicy.createDeprecatedPolicies` and the deprecated policy templates. Delete the key from `aws-tibco-cp-base-values.yaml`:

```yaml
global:
  tibco:
    networkPolicy:
      # createDeprecatedPolicies: true   # REMOVED in 1.19.0
      createClusterScopePolicies: true
```

The upgrade assistant does not remove it for you.

### otel-collector Default

The chart default for `otel-collector.enabled` changes from `false` to `true` in 1.19.0 (and back to `false` in 1.20.0). The shared guide sets it explicitly to `true` with a `global.external.logserver` block. If your values file omits the key and you have no log server, add `otel-collector.enabled: false` before upgrading.

### Jaeger v2

The observability recipe moves Jaeger from chart 0.72.41 (Jaeger 1.66.0) to chart 4.8.2 (Jaeger 2.19.0) and OpenTelemetry Collector to 0.156.2. Traces recorded before the upgrade appear as red dots in the dashboard (PCP-20148). Elasticsearch 8.15.2 and OpenSearch 2.14.0 remain the tested backends.

### Elasticsearch Log Export After Upgrade (PCP-23331)

On self-hosted Control Planes, CP service logs can stop reaching Elasticsearch after the 1.18.0 to 1.19.0 upgrade (`document_parsing_exception`, HTTP 400). Workaround:

```bash
kubectl edit configmap otel-services -n ${CP_INSTANCE_ID}-ns
# 1. under exporters.elasticsearch/log set   mapping: { mode: none }
# 2. remove transform/es-bodymap from service.pipelines.logs.processors
kubectl rollout restart deployment cp-otel-services -n ${CP_INSTANCE_ID}-ns
```

This is fixed in 1.20.0.

### Gateway API: hybrid-proxy Route Fixed

`tibco-cp-base` 1.19.0 changes the `hybrid-proxy` HTTPRoute template: it always renders `PathPrefix: /infra/tunnel` and only adds `PathPrefix: /` when `dnsDomain != dnsTunnelDomain`. This fixes PCP-21362. With simplified DNS (`dnsDomain == dnsTunnelDomain`) you can attach both `hybrid-proxy` and `router-operator` HTTPRoutes to `*.${TP_BASE_DNS_DOMAIN}` on the same Gateway; the longer `/infra/tunnel` match wins for tunnel traffic.

The chart never reads `gatewayRoute.rules` from values, so remove the explicit rules that the 1.18 workaround added. See the [1.20.0 overlay](../v1.20/how-to-cp-and-dp-eks-setup-guide#simplified-dns-and-gateway-api) for the values snippet.

### Data Plane Infrastructure

Use the commands generated by the Control Plane UI (`dp-configure-namespace` 1.19.10, `dp-core-infrastructure` 1.19.5). `dp-configure-namespace` 1.19.10 removes `networkPolicy.createDeprecatedPolicies` and adds RBAC for the Infra MCP Server, MCP Gateway, and Spring Boot (`rbac.infraMcp`, `rbac.infraMcpClusterScoped`, `rbac.infraMcpServiceAccountName`, `rbac.infraMcpExtraRules`, `rbac.mcpGateway`, `rbac.springboot`).

### Infra MCP Server Capability

The TIBCO Platform Infra MCP Server can be provisioned on the Data Plane from Data Planes > Capabilities > Add Capability. It provides read-only `kubectl get/describe/logs` and `helm list/status/get/history` through the Data Plane proxy. It exists to serve TESSA, which in 1.19.0 is only available on TIBCO Operated Control Plane (US region), so it is optional for self-hosted EKS.

### Flogo App-Init Resources

If Flogo app pods are slow to start on smaller EKS nodes, tune the new `flogoprovisioner` chart `config` values `APP_INIT_CPU_REQUEST` (100m), `APP_INIT_MEMORY_REQUEST` (100Mi), `APP_INIT_CPU_LIMIT` (200m), `APP_INIT_MEMORY_LIMIT` (400Mi).

### Email, DNS, Aurora SSL

Unchanged from 1.18.0: email is configured in the Platform Console, simplified DNS uses one Route 53 base domain and one ACM wildcard certificate, and `TP_DB_SSL_MODE` must be `require` or `verify-full` when `rds.force_ssl=1` is enforced.

## Post-Upgrade Checklist

- [ ] `tibco-cp-base` is at 1.19.0 and `createDeprecatedPolicies` is gone from the values file.
- [ ] `otel-collector.enabled` is set explicitly.
- [ ] CP logs still arrive in Elasticsearch (apply the PCP-23331 workaround if not).
- [ ] Capability charts are at 1.19.0 (`tibco-cp-hawk` and `tibco-cp-messaging` 1.19.23).
- [ ] Data Plane infrastructure is at `dp-configure-namespace` 1.19.10 and `dp-core-infrastructure` 1.19.5, then capabilities.
- [ ] HTTPRoutes validated if Gateway API is used.
- [ ] Ready to continue to [1.20.0](../v1.20/how-to-cp-and-dp-eks-setup-guide).

## Related Documentation

- [1.19.0 Release Notes](../../releases/v1.19.0)
- [1.19.0 Quick Reference](./QUICK-REFERENCE)
- [1.20.0 Setup Overlay](../v1.20/how-to-cp-and-dp-eks-setup-guide)
- [Shared EKS CP + DP Setup Guide](../how-to-cp-and-dp-eks-setup-guide)
- [TIBCO Platform Control Plane 1.19.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.19.0/doc/html/Default.htm)
