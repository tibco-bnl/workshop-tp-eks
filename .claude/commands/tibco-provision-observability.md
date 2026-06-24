You are helping deploy the TIBCO Platform observability stack on Amazon EKS. This installs Elasticsearch/Kibana (via ECK operator) and Prometheus/Grafana (via kube-prometheus-stack) for logs, metrics, and traces.

## Before You Start

Verify Data Plane is deployed:
```bash
kubectl get pods -n ${DP_INSTANCE_ID}-ns
helm list -n ${DP_INSTANCE_ID}-ns
```

Confirm environment values:
```bash
echo "DP_INSTANCE_ID=${DP_INSTANCE_ID}"
echo "TP_BASE_DNS_DOMAIN=${TP_BASE_DNS_DOMAIN}"
echo "AWS_REGION=${AWS_REGION}"
echo "ACM_CERTIFICATE_ARN=${ACM_CERTIFICATE_ARN}"
echo "TP_CONTAINER_REGISTRY_URL=${TP_CONTAINER_REGISTRY_URL}"
INGRESS_CLASS=$(kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}')
echo "Ingress class: ${INGRESS_CLASS}"
```

## Step 1 — Create Observability Namespaces

```bash
for ns in elastic-system prometheus-system; do
  kubectl create namespace ${ns} --dry-run=client -o yaml | kubectl apply -f -
done
```

## Step 2 — ECK Operator

```bash
helm repo add elastic https://helm.elastic.co && helm repo update

helm upgrade --install --wait --timeout 10m \
  --create-namespace -n elastic-system eck-operator elastic/eck-operator \
  --set managedNamespaces="{${DP_INSTANCE_ID}-ns}" \
  --set installCRDs=true
```

Verify:
```bash
kubectl get pods -n elastic-system
kubectl get crd | grep elastic
```

## Step 3 — dp-config-es (Elasticsearch + Kibana)

Install the TIBCO Data Plane Elasticsearch chart. EKS uses EFS storage for Elasticsearch (ReadWriteMany required):

```bash
helm upgrade --install --wait --timeout 30m \
  -n ${DP_INSTANCE_ID}-ns \
  ${DP_INSTANCE_ID}-dp-config-es tibco-platform-public/dp-config-es \
  --set "global.tibco.dataPlane.id=${DP_INSTANCE_ID}" \
  --set "global.tibco.dataPlane.namespace=${DP_INSTANCE_ID}-ns" \
  --set "global.tibco.containerRegistry.url=${TP_CONTAINER_REGISTRY_URL}" \
  --set "global.tibco.containerRegistry.username=${TP_CONTAINER_REGISTRY_USER}" \
  --set "global.tibco.containerRegistry.password=${TP_CONTAINER_REGISTRY_PASSWORD}" \
  --set "global.tibco.createNetworkPolicy=false" \
  --set "global.imagePullSecrets[0].name=tibco-container-registry-credentials" \
  --set "dp-config-es.elasticsearch.enabled=true" \
  --set "dp-config-es.kibana.enabled=true" \
  --set "dp-config-es.elasticsearch.storageClass=efs-sc" \
  --set "dp-config-es.elasticsearch.storage=20Gi" \
  --set "dp-config-es.ingress.className=${INGRESS_CLASS}" \
  --set "dp-config-es.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn=${ACM_CERTIFICATE_ARN}" \
  --set "dp-config-es.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme=internet-facing" \
  --set "dp-config-es.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type=ip" \
  --set "dp-config-es.ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname=kibana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}"
```

Monitor Elasticsearch startup (3-5 minutes):
```bash
kubectl get elasticsearch -n ${DP_INSTANCE_ID}-ns -w
```

Wait for `HEALTH=green` and `PHASE=Ready`.

## Step 4 — kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update

helm upgrade --install --wait --timeout 30m \
  --create-namespace -n prometheus-system kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --set "alertmanager.enabled=true" \
  --set "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=efs-sc" \
  --set "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi" \
  --set "grafana.persistence.enabled=true" \
  --set "grafana.persistence.storageClassName=efs-sc" \
  --set "grafana.persistence.size=5Gi" \
  --set "grafana.ingress.enabled=true" \
  --set "grafana.ingress.ingressClassName=${INGRESS_CLASS}" \
  --set "grafana.ingress.hosts[0]=grafana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}" \
  --set "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn=${ACM_CERTIFICATE_ARN}" \
  --set "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme=internet-facing" \
  --set "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type=ip" \
  --set "grafana.ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname=grafana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}" \
  --set "prometheus.ingress.enabled=true" \
  --set "prometheus.ingress.ingressClassName=${INGRESS_CLASS}" \
  --set "prometheus.ingress.hosts[0]=prometheus.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}" \
  --set "prometheus.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn=${ACM_CERTIFICATE_ARN}" \
  --set "prometheus.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme=internet-facing" \
  --set "prometheus.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type=ip" \
  --set "prometheus.ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname=prometheus.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}"
```

Verify:
```bash
kubectl get pods -n prometheus-system
kubectl get ingress -n prometheus-system
```

## Step 5 — Prometheus ServiceMonitor for DP

```bash
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: tibco-dp-metrics
  namespace: ${DP_INSTANCE_ID}-ns
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - ${DP_INSTANCE_ID}-ns
  selector:
    matchLabels:
      platform.tibco.com/dataplane-id: ${DP_INSTANCE_ID}
  endpoints:
    - port: metrics
      interval: 30s
EOF
```

## Step 6 — Verify DNS Records

External DNS should create Route 53 records from ingress annotations. Verify:

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${TP_BASE_DNS_DOMAIN}" \
  --query 'HostedZones[0].Id' --output text)

aws route53 list-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --query "ResourceRecordSets[?contains(Name, '${DP_INSTANCE_ID}')]" \
  --output table | grep -E "kibana|grafana|prometheus"
```

## Step 7 — Verify All Components

```bash
echo "=== ECK Operator ===" && kubectl get pods -n elastic-system
echo "=== Elasticsearch ===" && kubectl get elasticsearch -n ${DP_INSTANCE_ID}-ns
echo "=== Kibana ===" && kubectl get kibana -n ${DP_INSTANCE_ID}-ns
echo "=== Prometheus ===" && kubectl get pods -n prometheus-system -l app=prometheus
echo "=== Grafana ===" && kubectl get pods -n prometheus-system -l app.kubernetes.io/name=grafana
echo "=== Ingress ===" && kubectl get ingress -n ${DP_INSTANCE_ID}-ns && kubectl get ingress -n prometheus-system
```

## Step 8 — Access Dashboards

| Service | URL |
|---------|-----|
| Kibana | `https://kibana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}` |
| Grafana | `https://grafana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}` |
| Prometheus | `https://prometheus.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}` |

Get Grafana admin password:
```bash
kubectl get secret -n prometheus-system kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

Get Elasticsearch elastic user password:
```bash
ES_NAME=$(kubectl get elasticsearch -n ${DP_INSTANCE_ID}-ns -o jsonpath='{.items[0].metadata.name}')
kubectl get secret -n ${DP_INSTANCE_ID}-ns ${ES_NAME}-es-elastic-user \
  -o jsonpath='{.data.elastic}' | base64 -d && echo
```

## Step 9 — Register Observability in Control Plane

In the TIBCO Platform Admin UI → **Data Planes** → select your Data Plane → **Observability**:

1. **Elasticsearch**:
   - URL: `https://kibana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}` (or internal ES cluster URL)
   - Username: `elastic`
   - Password: from Step 8
2. **Prometheus**:
   - URL: `http://kube-prometheus-stack-prometheus.prometheus-system:9090`
3. **Grafana**:
   - URL: `https://grafana.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}`

## Troubleshooting

**Elasticsearch PVC pending**: EFS PVCs can take 2-3 minutes to bind. If they remain pending:
```bash
kubectl describe pvc -n ${DP_INSTANCE_ID}-ns | grep -E "Warning|ProvisioningFailed|WaitingForFirstConsumer"
```

Check EFS CSI driver is running:
```bash
kubectl get pods -n kube-system | grep efs-csi
```

Check EFS security group allows NFS (port 2049) from EKS node security group.

**ALB health check failing**: Prometheus and Grafana health endpoints may need `/healthz` or `/api/health`:
```bash
kubectl describe ingress -n prometheus-system | grep -i health
```

**ECR image pull for Elasticsearch**: If using ECR to mirror images, refresh the ECR token — it expires every 12 hours:
```bash
aws ecr get-login-password --region "${AWS_REGION}" | \
  kubectl create secret docker-registry ecr-registry-credentials \
    --docker-server="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com" \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region "${AWS_REGION}") \
    -n ${DP_INSTANCE_ID}-ns \
    --dry-run=client -o yaml | kubectl apply -f -
```

See `howto/how-to-dp-eks-observability.md` for the full observability setup guide.
