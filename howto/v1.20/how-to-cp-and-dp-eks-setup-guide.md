---
layout: default
title: TIBCO Platform 1.20.0 CP and DP Setup Overlay on EKS
---

# TIBCO Platform 1.20.0 CP and DP Setup Overlay on EKS

Use this guide as the 1.20.0 overlay for the common EKS CP+DP setup. The base EKS cluster, Route 53 hosted zone, ALB controller, External DNS, EFS/EBS storage, Aurora PostgreSQL, ACM certificate, and Traefik setup remain in the shared [CP and DP setup guide](../how-to-cp-and-dp-eks-setup-guide). Apply the differences below when deploying or upgrading to TIBCO Platform Control Plane 1.20.0.

## Start Here

1. Complete the shared baseline through EKS, ALB, External DNS, storage, Aurora PostgreSQL, Route 53, ACM, and ingress: [shared EKS CP + DP setup guide](../how-to-cp-and-dp-eks-setup-guide).
2. If upgrading, 1.19.0 is the only supported direct upgrade source. From 1.18.0, apply the [1.19.0 overlay](../v1.19/how-to-cp-and-dp-eks-setup-guide) first.
3. Apply the 1.20.0-specific changes below.
4. Refresh the Helm repository:

```bash
helm repo add tibco-platform https://tibcosoftware.github.io/tp-helm-charts
helm repo update tibco-platform
```

## 1.20.0 Chart Versions

These versions are from the 1.20.0 artifact manifests in the official `tp-helm-charts` repository.

| Area | Chart | Version |
|------|-------|---------|
| Control Plane | `tibco-cp-base` | `1.20.0` |
| Control Plane | `tp-cp-proxy` | `1.20.2` |
| Control Plane | `artifactmanager` | `1.20.0` |
| Control Plane | `o11yservice` | `1.20.5` |
| Control Plane | `tp-dp-monitor-agent` | `1.20.2` |
| Control Plane | `jaeger` | `4.8.3` |
| Data Plane | `dp-configure-namespace` | `1.20.0` |
| Data Plane | `dp-core-infrastructure` | `1.20.3` |
| BW | `tibco-cp-bw` | `1.20.0` |
| BW | `bwprovisioner` / `bw5provisioner` | `1.20.2` |
| BW | `dp-bwce-app` / `dp-bw5ce-app` | `1.20.4` |
| Flogo | `tibco-cp-flogo` | `1.20.0` |
| Flogo | `flogoprovisioner` | `1.20.10` |
| Flogo | `dp-flogo-app` | `1.20.8` |
| Developer Hub | `tibco-cp-devhub` | `1.20.0` |
| Developer Hub | `tibco-developer-hub` | `1.20.8` |
| Hawk | `tibco-cp-hawk` / `tp-dp-hawk-console` | `1.20.8` |
| Messaging | `tibco-cp-messaging` / `msg-ems-tp` | `1.19.23` (no 1.20.0 release) |
| MCP | `tp-dp-infra-mcp-server` | `1.20.0` |
| MCP | `tp-mcp-gateway` | `1.20.0` (MCP Hub, TIBCO Operated CP only) |

## 1.20.0 Changes to Apply

### Control Plane Base Chart

Use the 1.20.0 base chart:

```bash
helm upgrade --install --wait --timeout 1h --create-namespace \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco-cp-base \
  --labels layer=1 \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.20.0" \
  -f aws-tibco-cp-base-values.yaml
```

### Values File Changes Since 1.18.0

Review `aws-tibco-cp-base-values.yaml` for these keys before installing or upgrading:

```yaml
global:
  tibco:
    networkPolicy:
      # REMOVED in 1.19.0 - delete this key if present
      # createDeprecatedPolicies: true
      createClusterScopePolicies: true

    # NEW in 1.20.0 (chart default shown). MFT adapter is disabled by default.
    # Set to [] to keep every mandatory infra capability enabled.
    disabledInfraCapabilities: [MFTADAPTER]

otel-collector:
  # Chart default: false in 1.18.0, true in 1.19.0, false again in 1.20.0.
  # Set it explicitly. true requires global.external.logserver to point at a
  # reachable Elasticsearch/OpenSearch endpoint (audit log, CP Fluent Bit logging).
  enabled: true
```

The shared guide's generated values files already set `otel-collector.enabled: true` together with the `global.external.logserver` block, so the default change does not affect them. If you skip log server configuration, set `otel-collector.enabled: false`.

### Email Server Configuration

Unchanged since 1.18.0: do not include `global.external.emailServerType`, `emailServer`, `fromAndReplyToEmailAddress`, `cronJobReportsEmailAlias`, or `platformEmailNotificationCcAddresses`. Configure SES, SMTP, SendGrid, or Microsoft Graph in the TIBCO Platform Console after install or upgrade. `global.tibco.networkPolicy.emailServer` is still only an optional egress NetworkPolicy.

### Aurora PostgreSQL Parameter Group

The upstream EKS Control Plane workshop for 1.20.0 creates the Aurora cluster parameter group with the AWS CLI instead of Crossplane. If you use the `dp-config-aws` Crossplane claims from the shared guide, run this before `helm upgrade --install crossplane-claims-aws`:

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "${CP_RESOURCE_PREFIX}-db-param" \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom parameter group for CP RDS cluster"

aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "${CP_RESOURCE_PREFIX}-db-param" \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate"
```

Then, in the claim values, replace `dbParameterGroupFamily: "aurora-postgresql16"` and the `groupFamilyParameters` block with:

```yaml
dbClusterParameterGroupName: "${CP_RESOURCE_PREFIX}-db-param"
```

Because SSL stays enforced, keep:

```bash
export TP_DB_SSL_MODE="require"     # or verify-full with the regional RDS CA bundle
```

The upstream `clean-up-control-plane.sh` script falls back to `${CP_RESOURCE_PREFIX}-db-param` when no Crossplane-managed parameter group exists.

### Simplified DNS and Gateway API

Keep the simplified DNS model:

```yaml
global:
  tibco:
    adminHostPrefix: "${CP_ADMIN_HOST_PREFIX}"
    hybridConnectivity:
      enabled: ${CP_HYBRID_CONNECTIVITY}
  external:
    dnsDomain: "${TP_BASE_DNS_DOMAIN}"
    dnsTunnelDomain: "${TP_BASE_DNS_DOMAIN}"
```

Since `tibco-cp-base` 1.19.0 the `hybrid-proxy` chart renders `PathPrefix: /infra/tunnel` in its HTTPRoute and only adds the catch-all `PathPrefix: /` when `dnsDomain` and `dnsTunnelDomain` differ (fix for PCP-21362). With simplified DNS you can therefore attach both HTTPRoutes to the same wildcard hostname on one Gateway. Gateway API precedence sends `/infra/tunnel` to `hybrid-proxy` because it is the longer path match; everything else goes to `router-operator`.

The chart does not read a `gatewayRoute.rules` value in any version; remove any explicit rules left from the 1.18 workaround.

```yaml
hybrid-proxy:
  enabled: true
  ingress:
    enabled: false
  gatewayRoute:
    enabled: true
    controllerName: "${TP_GATEWAY_CLASS}"     # nginx
    hostnames:
    - '*.${TP_BASE_DNS_DOMAIN}'
    parentRefs:
    - name: "${TP_GATEWAY_NAME}"
      namespace: "${TP_GATEWAY_NAMESPACE}"

router-operator:
  ingress:
    enabled: false
  gatewayRoute:
    enabled: true
    controllerName: "${TP_GATEWAY_CLASS}"
    hostnames:
    - '*.${TP_BASE_DNS_DOMAIN}'
    parentRefs:
    - name: "${TP_GATEWAY_NAME}"
      namespace: "${TP_GATEWAY_NAMESPACE}"

global:
  external:
    dnsDomain: "${TP_BASE_DNS_DOMAIN}"
    dnsTunnelDomain: "${TP_BASE_DNS_DOMAIN}"
```

Hostname separation (`${CP_INSTANCE_ID}-tunnel.${TP_BASE_DNS_DOMAIN}` for `hybrid-proxy`) still works if you prefer it, but it is no longer required. The official Gateway API controller matrix is unchanged: NGINX Gateway Fabric 2.3.0, Istio 1.28.2, Traefik `traefik-39.0.7`, NetScaler `netscaler-cpx-with-gateway-controller-2.0.0`.

Verify after deployment:

```bash
kubectl get httproute -n ${CP_INSTANCE_ID}-ns
kubectl get httproute -n ${CP_INSTANCE_ID}-ns hybrid-proxy -o jsonpath='{.spec.rules[*].matches[*].path.value}{"\n"}'
# expected with simplified DNS: /infra/tunnel
```

### Data Plane Infrastructure

Use the commands generated by the Control Plane UI. For 1.20.0 they reference `dp-configure-namespace` 1.20.0 and `dp-core-infrastructure` 1.20.3. `dp-configure-namespace` no longer accepts `networkPolicy.createDeprecatedPolicies`; remove that `--set` from any saved commands. New RBAC toggles (`rbac.infraMcp`, `rbac.infraMcpClusterScoped`, `rbac.mcpGateway`, `rbac.springboot`) default to `true`, `false`, `true`, `true`.

### Control Plane Rollback

New in 1.20.0. Before upgrading, record the current revision:

```bash
helm history tibco-cp-base -n ${CP_INSTANCE_ID}-ns
```

If the upgrade fails and `global.tibco.manageDbSchema` is `true` (workshop default):

```bash
helm rollback tibco-cp-base <revision> -n ${CP_INSTANCE_ID}-ns --wait
```

If `manageDbSchema` is `false`, run `postgres-helper.bash rollbackDbSchema <chart-version>` from `tp-helm-charts/scripts/database` first. Roll back the Control Plane before upgrading any Data Plane or capability.

### OTLP Exporters with Custom Headers

When an OTLP exporter or query service in Data Plane Configuration > Observability needs tenant or authorization headers (for example a SaaS backend fronted by an AWS ALB with header-based auth), add them in the new Custom Header fields. The secondary exporter supports OTLP only.

### MCP Hub, Infra MCP Server, and TESSA

MCP Hub and TESSA are TIBCO Operated Control Plane features in 1.20.0 and do not apply to a self-hosted EKS Control Plane. The Infra MCP Server can still be provisioned as a Data Plane capability; it exposes read-only `kubectl` and `helm` diagnostics through the Data Plane proxy and uses RBAC created by `dp-configure-namespace`.

## Post-Upgrade Checklist

- [ ] `tibco-cp-base` is upgraded to 1.20.0 and `helm history` shows the previous revision for rollback.
- [ ] `global.tibco.networkPolicy.createDeprecatedPolicies` is absent from values files.
- [ ] `otel-collector.enabled` and `global.tibco.disabledInfraCapabilities` are set intentionally.
- [ ] Capability charts are at 1.20.0 (`tibco-cp-hawk` 1.20.8, `tibco-cp-messaging` stays 1.19.23).
- [ ] Data Plane infrastructure is upgraded to `dp-configure-namespace` 1.20.0 and `dp-core-infrastructure` 1.20.3, then capabilities.
- [ ] Route 53 simplified DNS resolves for admin and subscription hosts; HTTPRoutes validated if Gateway API is used.
- [ ] Aurora PostgreSQL SSL mode matches the `rds.force_ssl=1` parameter group.
- [ ] `scripts/verify-release.sh` from `tp-helm-charts` passes for `control-plane` 1.20.0.

## Related Documentation

- [1.20.0 Release Notes](../../releases/v1.20.0)
- [1.20.0 Quick Reference](./QUICK-REFERENCE)
- [1.19.0 Setup Overlay](../v1.19/how-to-cp-and-dp-eks-setup-guide)
- [Shared EKS CP + DP Setup Guide](../how-to-cp-and-dp-eks-setup-guide)
- [Route 53 DNS Guide](../how-to-add-dns-records-eks-aws)
- [TIBCO Platform Control Plane 1.20.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.20.0/doc/html/Default.htm)
