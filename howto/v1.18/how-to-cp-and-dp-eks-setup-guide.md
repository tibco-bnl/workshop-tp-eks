---
layout: default
title: TIBCO Platform 1.18.0 CP and DP Setup Overlay on EKS
---

# TIBCO Platform 1.18.0 CP and DP Setup Overlay on EKS

Use this guide as the 1.18.0 overlay for the common EKS CP+DP setup. The base EKS cluster, Route 53 hosted zone, ALB controller, External DNS, EFS/EBS storage, Aurora PostgreSQL, ACM certificate, and Nginx/Traefik setup remain in the shared [CP and DP setup guide](../how-to-cp-and-dp-eks-setup-guide). Apply the differences below when deploying or upgrading to TIBCO Platform Control Plane 1.18.0.

## Start Here

1. Complete the shared baseline through EKS, ALB, External DNS, storage, Aurora PostgreSQL, Route 53, ACM, and ingress: [shared EKS CP + DP setup guide](../how-to-cp-and-dp-eks-setup-guide).
2. Use 1.17.0 as the direct upgrade source when upgrading an existing environment: [1.17.0 release notes](../../releases/v1.17.0).
3. Apply the 1.18.0-specific changes below.

## 1.18.0 Changes to Apply

### Control Plane Base Chart

Use the 1.18.0 base chart:

```bash
helm upgrade --install --wait --timeout 2h --create-namespace \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco-cp-base \
  --labels layer=1 \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.18.0" \
  -f aws-tibco-cp-base-values.yaml
```

### Email Server Configuration

Do not include deprecated email server values in `aws-tibco-cp-base-values.yaml`. In 1.18.0, configure SES, SMTP, or SendGrid from the TIBCO Platform Console after installation or upgrade.

Remove these values if they exist in older files:

```yaml
global:
  external:
    emailServerType: "..."
    fromAndReplyToEmailAddress: "..."
    cronJobReportsEmailAlias: "..."
    platformEmailNotificationCcAddresses: "..."
    emailServer: {}
```

### Simplified DNS Continues

Keep the 1.17 simplified DNS model for new 1.18 EKS installs:

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

Use one Route 53 wildcard alias record and one ACM wildcard certificate:

```text
*.${TP_BASE_DNS_DOMAIN} -> AWS ALB
```

Expected host patterns:

```text
https://${CP_ADMIN_HOST_PREFIX}.${TP_BASE_DNS_DOMAIN}
https://${CP_SUBSCRIPTION}.${TP_BASE_DNS_DOMAIN}
https://${CP_SUBSCRIPTION}.${TP_BASE_DNS_DOMAIN}/infra/tunnel
```

Keep `cp1-my` and `cp1-tunnel` domains only for legacy split-domain deployments.

### Aurora PostgreSQL SSL

For production Aurora PostgreSQL, prefer TLS:

```bash
export TP_DB_SSL_MODE="require"
```

Use `verify-full` when certificate verification is required:

```bash
curl -o rds-ca-bundle.pem \
  "https://truststore.pki.rds.amazonaws.com/${TP_CLUSTER_REGION}/${TP_CLUSTER_REGION}-bundle.pem"

kubectl create secret generic ${TP_DB_SSL_CERT_SECRET} \
  -n ${CP_INSTANCE_ID}-ns \
  --from-file=${TP_DB_SSL_CERT_KEY}=rds-ca-bundle.pem

export TP_DB_SSL_MODE="verify-full"
```

Crossplane-created Aurora clusters may enforce `rds.force_ssl=1`; do not use `TP_DB_SSL_MODE=disable` in that case.

### Gateway API

TIBCO Platform 1.18.0 adds Gateway API controller support for Control Tower data planes. For EKS workshops, continue using AWS ALB plus Nginx or Traefik ingress for the baseline. Evaluate Traefik Gateway API for capability endpoint exposure only when the capability and target Data Plane are ready for Gateway API resources.

Check Gateway API readiness when you enable it:

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
```

### Namespace-Level RBAC

After upgrade, review Data Plane Configuration > Resources and Application Manager/Application Viewer assignments. Users may need explicit namespace grants for each Data Plane namespace.

```bash
kubectl get namespaces
kubectl get rolebinding,clusterrolebinding -A | grep -i tibco || true
```

### Alert Audit Trail

After upgrade, validate the Alerts Audit Trail page in the TIBCO Platform Console and confirm EKS network policies allow the Control Plane namespace to reach configured webhook endpoints.

## Post-Upgrade Checklist

- [ ] `tibco-cp-base` is upgraded to 1.18.0.
- [ ] Deprecated email Helm values are removed.
- [ ] SES, SMTP, or SendGrid is configured from the Platform Console if notifications are needed.
- [ ] Route 53 simplified DNS resolves for admin and subscription hosts.
- [ ] Aurora PostgreSQL SSL mode matches your RDS parameter group.
- [ ] Data Plane namespaces and RBAC assignments are reviewed.
- [ ] Gateway API resources are validated if used.
- [ ] Alerts Audit Trail is visible and recording events.

## Related Documentation

- [1.18.0 Release Notes](../../releases/v1.18.0)
- [1.18.0 Quick Reference](./QUICK-REFERENCE)
- [Shared EKS CP + DP Setup Guide](../how-to-cp-and-dp-eks-setup-guide)
- [Route 53 DNS Guide](../how-to-add-dns-records-eks-aws)
