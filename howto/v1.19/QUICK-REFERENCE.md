---
layout: default
title: TIBCO Platform v1.19.0 Quick Reference Guide - EKS
---

# TIBCO Platform v1.19.0 Quick Reference Guide - EKS

**TIBCO Platform Version**: 1.19.0 | **Platform**: Amazon EKS | **Status**: Previous release (upgrade hop to 1.20.0)

## Essential Commands

```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns
helm list -n ${CP_INSTANCE_ID}-ns
kubectl get ingress -A
kubectl get gatewayclass,gateway,httproute -A
```

## Helm Charts (v1.19.0)

| Chart | Version |
|-------|---------|
| tibco-cp-base | 1.19.0 |
| tibco-cp-bw | 1.19.0 |
| tibco-cp-flogo | 1.19.0 |
| tibco-cp-devhub | 1.19.0 |
| tibco-cp-hawk | 1.19.23 |
| tibco-cp-messaging | 1.19.23 |
| tp-cp-proxy | 1.19.1 |
| o11yservice | 1.19.16 |
| tp-dp-monitor-agent | 1.19.11 |
| jaeger | 4.8.2 |
| dp-configure-namespace | 1.19.10 |
| dp-core-infrastructure | 1.19.5 |
| tp-dp-infra-mcp-server | 1.19.0 |

## New in v1.19.0

### Values Check Before Upgrade

```bash
# Removed in 1.19.0 - must not be present
grep -n "createDeprecatedPolicies" aws-tibco-cp-base-values.yaml && echo "REMOVE this key"
# Default flipped to true in 1.19.0 - set explicitly
yq '.["otel-collector"].enabled' aws-tibco-cp-base-values.yaml
```

### PCP-23331 Workaround (CP logs missing in Elasticsearch after upgrade)

```bash
kubectl edit configmap otel-services -n ${CP_INSTANCE_ID}-ns
#   exporters.elasticsearch/log.mapping.mode: none
#   remove transform/es-bodymap from the logs pipeline
kubectl rollout restart deployment cp-otel-services -n ${CP_INSTANCE_ID}-ns
```

### Gateway API (hybrid-proxy route fixed)

```bash
kubectl get httproute -n ${CP_INSTANCE_ID}-ns hybrid-proxy \
  -o jsonpath='{.spec.rules[*].matches[*].path.value}{"\n"}'
# simplified DNS (dnsDomain == dnsTunnelDomain): /infra/tunnel
# split DNS:                                     /infra/tunnel /
```

### Infra MCP Server RBAC

```bash
kubectl get role,clusterrole -A | grep -i infra-mcp
# cluster-wide diagnostics: --set rbac.infraMcpClusterScoped=true on dp-configure-namespace
```

## Upgrade to v1.19.0 (from 1.18.0)

```bash
kubectl get secret session-keys -n ${CP_INSTANCE_ID}-ns -o yaml > session-keys-backup.yaml
kubectl get secret cporch-encryption-secret -n ${CP_INSTANCE_ID}-ns -o yaml > cporch-encryption-secret-backup.yaml
helm repo update

helm upgrade --install --wait --timeout 2h \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco-cp-base \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.19.0" \
  -f aws-tibco-cp-base-values.yaml

for c in tibco-cp-bw tibco-cp-flogo tibco-cp-devhub; do
  helm upgrade --install --wait -n ${CP_INSTANCE_ID}-ns $c $c \
    --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.19.0" -f ${c}-values.yaml
done
```

Then continue with the [1.20.0 quick reference](../v1.20/QUICK-REFERENCE).

## References

- [1.19.0 Release Notes](../../releases/v1.19.0)
- [1.19.0 Setup Overlay](./how-to-cp-and-dp-eks-setup-guide)
- [Shared EKS Setup Guide](../how-to-cp-and-dp-eks-setup-guide)
- [Official 1.19.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.19.0/doc/html/Default.htm)
