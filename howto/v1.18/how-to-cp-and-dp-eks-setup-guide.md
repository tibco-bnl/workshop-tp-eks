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
helm upgrade --install --wait --timeout 1h --create-namespace \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco/tibco-cp-base \
  --labels layer=1 \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.18.0" \
  -f aws-tibco-cp-base-values.yaml
```

### Email Server Configuration

Do not include deprecated email server values in `aws-tibco-cp-base-values.yaml`. In 1.18.0, configure SES, SMTP, SendGrid, or Microsoft Graph from the TIBCO Platform Console after installation or upgrade.

The `tibco-cp-base` chart still includes `global.tibco.networkPolicy.emailServer`, but that block is only for optional egress NetworkPolicy creation. Leave its `CIDR` empty unless you need an explicit allow rule to an email provider; it does not configure the provider itself.

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

`dnsDomain` and `dnsTunnelDomain` can use the same value in simplified DNS, but they represent different routing roles. `dnsDomain` is for normal Control Plane router traffic, while `dnsTunnelDomain` tells the platform what public domain to advertise for hybrid connectivity tunnel traffic handled by `hybrid-proxy`. In the baseline Ingress model, tunnel traffic uses the subscription host and `/infra/tunnel` path, so no separate tunnel domain or certificate is needed.

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

TIBCO Platform 1.18.0 adds Gateway API controller support for Control Plane and Control Tower data planes. The official requirements list NGINX Gateway Fabric 2.3.0, Istio 1.28.2, Traefik `traefik-39.0.7`, and NetScaler `netscaler-cpx-with-gateway-controller-2.0.0` for Control Plane and data plane Gateway API usage. Data planes can also use the `Other Gateway API Controller` option when the target controller is not listed explicitly.

For EKS workshops, continue using AWS ALB plus Nginx or Traefik ingress for the baseline. Evaluate Gateway API only when the target Control Plane, capability, and Data Plane are ready for Gateway API resources.

#### NGINX Gateway Fabric Example

Install NGINX Gateway Fabric and create a Gateway for route attachment:

```bash
export TP_GATEWAY_NAMESPACE="nginx-gateway"
export TP_GATEWAY_NAME="nginx-gateway"
export TP_GATEWAY_CLASS="nginx"
export TP_TUNNEL_DOMAIN="${CP_INSTANCE_ID}-tunnel.${TP_HOSTED_ZONE_DOMAIN}"

kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml

helm upgrade --install nginx-gateway-fabric \
  oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace ${TP_GATEWAY_NAMESPACE} \
  --create-namespace \
  --version 2.3.0

kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${TP_GATEWAY_NAME}
  namespace: ${TP_GATEWAY_NAMESPACE}
spec:
  gatewayClassName: ${TP_GATEWAY_CLASS}
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF
```

#### `tibco-cp-base` Gateway API Values

Use a second values file with the generated `aws-tibco-cp-base-values.yaml` file. This keeps the base CP values unchanged and only swaps router and hybrid-proxy routing from classic `Ingress` to Gateway API `HTTPRoute`.

> **Note:** From `tibco-cp-base` 1.19.0+, the `hybrid-proxy` chart renders only a `PathPrefix: /infra/tunnel` rule when `dnsDomain == dnsTunnelDomain` (simplified DNS mode). Set both `hybrid-proxy` and `router-operator` to use the same wildcard hostname (e.g. `*.aws.example.com`). Path specificity routes tunnel traffic to `hybrid-proxy` and all other traffic to `router-operator` — no separate tunnel hostname or extra DNS record required.
>
> To confirm the installed GatewayClass name: `kubectl get gatewayclass`

```yaml
router-operator:
  ingress:
    enabled: false
  gatewayRoute:
    enabled: true
    controllerName: nginx
    parentRefs:
      - name: nginx-gateway
        namespace: nginx-gateway
        sectionName: http
    hostnames:
      - "*.aws.example.com"

hybrid-proxy:
  enabled: true
  ingress:
    enabled: false
  gatewayRoute:
    enabled: true
    controllerName: nginx
    parentRefs:
      - name: nginx-gateway
        namespace: nginx-gateway
        sectionName: http
    hostnames:
      - "*.aws.example.com"

global:
  external:
    dnsTunnelDomain: "aws.example.com"    # same as dnsDomain — simplified DNS
```

Install with the Gateway API override:

```bash
helm upgrade --install --wait --timeout 1h --create-namespace \
  -n ${CP_INSTANCE_ID}-ns tibco-cp-base tibco/tibco-cp-base \
  --labels layer=1 \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.18.0" \
  -f aws-tibco-cp-base-values.yaml \
  -f aws-tibco-cp-base-gateway-api-values.yaml
```

Check Gateway API readiness when you enable it:

```bash
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
```

When registering a Control Tower data plane for Gateway API endpoint exposure, select NGINX Gateway Fabric, use GatewayClass `nginx`, Gateway name `nginx-gateway`, and namespace `nginx-gateway`. Supported BW5, BW6, and Flogo endpoint exposure can then create `HTTPRoute` resources instead of classic `Ingress` resources.

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
- [ ] SES, SMTP, SendGrid, or Microsoft Graph is configured from the Platform Console if notifications are needed.
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
