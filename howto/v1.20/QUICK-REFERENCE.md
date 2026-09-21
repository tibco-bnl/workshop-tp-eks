---
layout: default
title: TIBCO Platform v1.20.0 Quick Reference Guide - EKS
---

# TIBCO Platform v1.20.0 Quick Reference Guide - EKS

**TIBCO Platform Version**: 1.20.0 | **Platform**: Amazon EKS | **Status**: Current release

## Quick Access URLs

| Service | URL Pattern | Notes |
|---------|-------------|-------|
| Admin Console | `https://${CP_ADMIN_HOST_PREFIX}.${TP_BASE_DNS_DOMAIN}` | Simplified DNS |
| Subscription Portal | `https://${CP_SUBSCRIPTION}.${TP_BASE_DNS_DOMAIN}` | Simplified DNS |
| Hybrid Tunnel | `https://${CP_SUBSCRIPTION}.${TP_BASE_DNS_DOMAIN}/infra/tunnel` | Same base domain |
| Legacy Admin Console | `https://admin.${CP_INSTANCE_ID}-my.<domain>` | Split DNS only |

## Essential Commands

```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns
helm list -n ${CP_INSTANCE_ID}-ns
helm history tibco-cp-base -n ${CP_INSTANCE_ID}-ns        # keep for rollback
kubectl get ingress -A
kubectl get gatewayclass,gateway,httproute -A
```

### Check Route 53 Records

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Type=='A'].[Name]" \
  --output text
```

## Helm Charts (v1.20.0)

| Chart | Version | Release Name |
|-------|---------|--------------|
| tibco-cp-base | 1.20.0 | tibco-cp-base |
| tibco-cp-bw | 1.20.0 | tibco-cp-bw |
| tibco-cp-flogo | 1.20.0 | tibco-cp-flogo |
| tibco-cp-devhub | 1.20.0 | tibco-cp-devhub |
| tibco-cp-hawk | 1.20.8 | tibco-cp-hawk |
| tibco-cp-messaging | 1.19.23 (no 1.20 release) | tibco-cp-messaging |
| tp-cp-proxy | 1.20.2 | (recipe, installed by CP) |
| o11yservice | 1.20.5 | (recipe, installed by CP) |
| tp-dp-monitor-agent | 1.20.2 | (recipe, installed by CP) |
| dp-configure-namespace | 1.20.0 | dp-configure-namespace |
| dp-core-infrastructure | 1.20.3 | dp-core-infrastructure |

## New or Changed in v1.20.0

### Values File Keys

```bash
# Must be absent (removed in 1.19.0)
grep -n "createDeprecatedPolicies" aws-tibco-cp-base-values.yaml && echo "REMOVE this key"

# Decide explicitly (chart default is false in 1.20.0)
yq '.["otel-collector"].enabled' aws-tibco-cp-base-values.yaml

# New in 1.20.0 (chart default [MFTADAPTER])
yq '.global.tibco.disabledInfraCapabilities' aws-tibco-cp-base-values.yaml
```

### Control Plane Rollback

```bash
helm history tibco-cp-base -n ${CP_INSTANCE_ID}-ns
# manageDbSchema: true (default)
helm rollback tibco-cp-base <revision> -n ${CP_INSTANCE_ID}-ns --wait
# manageDbSchema: false -> run postgres-helper.bash rollbackDbSchema <chart-version> first
```

### Gateway API (fixed hybrid-proxy route since 1.19.0)

```bash
kubectl get httproute -n ${CP_INSTANCE_ID}-ns hybrid-proxy \
  -o jsonpath='{.spec.hostnames}{"  "}{.spec.rules[*].matches[*].path.value}{"\n"}'
# simplified DNS expected: ["*.<base-domain>"]  /infra/tunnel
```

### Aurora PostgreSQL Parameter Group

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "${CP_RESOURCE_PREFIX}-db-param" \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom parameter group for CP RDS cluster"
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "${CP_RESOURCE_PREFIX}-db-param" \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate"
export TP_DB_SSL_MODE="require"
```

## Upgrade to v1.20.0 (from 1.19.0 only)

```bash
# 1. Back up critical secrets
kubectl get secret session-keys -n ${CP_INSTANCE_ID}-ns -o yaml > session-keys-backup.yaml
kubectl get secret cporch-encryption-secret -n ${CP_INSTANCE_ID}-ns -o yaml > cporch-encryption-secret-backup.yaml

# 2. Update Helm repository
helm repo update

# 3. Upgrade base chart
helm upgrade --install --wait --timeout 2h \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco-cp-base \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.20.0" \
  -f aws-tibco-cp-base-values.yaml

# 4. Capability charts
for c in tibco-cp-bw tibco-cp-flogo tibco-cp-devhub; do
  helm upgrade --install --wait -n ${CP_INSTANCE_ID}-ns $c $c \
    --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.20.0" -f ${c}-values.yaml
done
helm upgrade --install --wait -n ${CP_INSTANCE_ID}-ns tibco-cp-hawk tibco-cp-hawk \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.20.*" -f tibco-cp-hawk-values.yaml

# 5. Verify against the official artifact list
CHECK_RELEASE_NAMESPACE=${CP_INSTANCE_ID}-ns CHECK_RELEASE_VERSION=1.20.0 \
CHECK_RELEASE_FOLDER=control-plane CHECK_RELEASE_NAME=tibco-cp-base \
  ./scripts/verify-release.sh    # from a tp-helm-charts checkout
```

From 1.18.0, upgrade to 1.19.0 first: [1.19.0 quick reference](../v1.19/QUICK-REFERENCE).

## Known Issues Quick Check

- PCP-23615: deleting a Data Plane observability configuration fails after the 1.20.0 upgrade (no workaround).
- PCP-20148: traces older than the Jaeger v2 move show as red dots.
- MSGDP-199: `gp2` does not support EMS shared logs on EKS.
- FLOGO-18866: use `wss://` for WebSocket public endpoints.

## References

- [1.20.0 Release Notes](../../releases/v1.20.0)
- [1.20.0 Setup Overlay](./how-to-cp-and-dp-eks-setup-guide)
- [Shared EKS Setup Guide](../how-to-cp-and-dp-eks-setup-guide)
- [Official 1.20.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.20.0/doc/html/Default.htm)
