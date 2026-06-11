# TIBCO Platform v1.18.0 Quick Reference Guide - EKS

**TIBCO Platform Version**: 1.18.0 | **Platform**: Amazon EKS | **Status**: Current release

## Quick Access URLs

| Service | URL Pattern | Notes |
|---------|-------------|-------|
| Admin Console | `https://admin.<TP_BASE_DNS_DOMAIN>` | Simplified DNS |
| Subscription Portal | `https://<hostPrefix>.<TP_BASE_DNS_DOMAIN>` | Simplified DNS |
| Hybrid Tunnel | `https://<hostPrefix>.<TP_BASE_DNS_DOMAIN>/infra/tunnel` | Same base domain |
| Legacy Admin Console | `https://admin.${CP_INSTANCE_ID}-my.<domain>` | Split DNS only |

## Essential Commands

### Check All Pods

```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns
```

### View Helm Releases

```bash
helm list -n ${CP_INSTANCE_ID}-ns
```

### Check Ingress and ALB Hostname

```bash
kubectl get ingress -n ingress-system
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.status.loadBalancer.ingress[*].hostname}{"\n"}{end}'
```

### Check Route 53 Records

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id ${TP_HOSTED_ZONE_ID} \
  --query "ResourceRecordSets[?Type=='A'].[Name]" \
  --output text
```

### Test Simplified DNS

```bash
nslookup ${CP_ADMIN_HOST_PREFIX}.${TP_BASE_DNS_DOMAIN}
dig +short ${CP_SUBSCRIPTION}.${TP_BASE_DNS_DOMAIN}
```

## Helm Charts (v1.18.0)

| Chart | Version | Release Name |
|-------|---------|--------------|
| tibco-cp-base | 1.18.0 | tibco-cp-base |
| tibco-cp-bw | 1.18.0 | tibco-cp-bw |
| tibco-cp-flogo | 1.18.0 | tibco-cp-flogo |
| tibco-cp-devhub | 1.18.0 | tibco-cp-devhub |
| tibco-cp-hawk | 1.18.12 | tibco-cp-hawk |
| dp-configure-namespace | 1.18.3 | dp-configure-namespace |
| dp-core-infrastructure | 1.18.4 | dp-core-infrastructure |

## New in v1.18.0

### Email Configuration

Email server settings moved to the Platform Console. Remove deprecated Helm values before upgrade, then configure SES, SMTP, or SendGrid in the UI.

### Gateway API

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
```

Use Traefik Gateway API only where the capability and Data Plane are configured for Gateway API endpoint exposure.

### Namespace-Level RBAC

```bash
kubectl get namespaces
kubectl get rolebinding,clusterrolebinding -A | grep -i tibco || true
```

Review Application Manager and Application Viewer role assignments after upgrade.

### Aurora PostgreSQL SSL

```bash
# Minimum SSL for RDS clusters with rds.force_ssl=1
export TP_DB_SSL_MODE="require"

# Stronger certificate verification
export TP_DB_SSL_MODE="verify-full"
```

Download the regional RDS CA bundle when using `verify-full`:

```bash
curl -o rds-ca-bundle.pem \
  "https://truststore.pki.rds.amazonaws.com/${TP_CLUSTER_REGION}/${TP_CLUSTER_REGION}-bundle.pem"
```

## Upgrade to v1.18.0

```bash
# 1. Back up critical secrets
kubectl get secret session-keys -n ${CP_INSTANCE_ID}-ns -o yaml > session-keys-backup.yaml
kubectl get secret cporch-encryption-secret -n ${CP_INSTANCE_ID}-ns -o yaml > cporch-secret-backup.yaml

# 2. Update Helm repository
helm repo update

# 3. Upgrade base chart with email values removed
helm upgrade --install --wait --timeout 2h \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco-cp-base \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.18.0" \
  -f aws-tibco-cp-base-values.yaml
```

## References

- [1.18.0 Release Notes](../../releases/v1.18.0)
- [1.18.0 Setup Overlay](./how-to-cp-and-dp-eks-setup-guide)
- [Shared EKS Setup Guide](../how-to-cp-and-dp-eks-setup-guide)
