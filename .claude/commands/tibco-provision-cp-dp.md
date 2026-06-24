You are helping deploy TIBCO Platform Control Plane **and** Data Plane on Amazon EKS. This skill assumes Control Plane is already installed (via `tibco-provision-cp`) and adds the Data Plane components to the same cluster.

## Before You Start

Verify Control Plane is healthy:
```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns
helm list -n ${CP_INSTANCE_ID}-ns
```

Confirm environment values:
```bash
echo "CP_INSTANCE_ID=${CP_INSTANCE_ID}"
echo "DP_INSTANCE_ID=${DP_INSTANCE_ID}"
echo "TP_BASE_DNS_DOMAIN=${TP_BASE_DNS_DOMAIN}"
echo "AWS_REGION=${AWS_REGION}"
echo "ACM_CERTIFICATE_ARN=${ACM_CERTIFICATE_ARN}"
INGRESS_CLASS=$(kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}')
echo "Ingress class: ${INGRESS_CLASS}"
```

## Step 1 — Create Data Plane Namespace

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${DP_INSTANCE_ID}-ns
  labels:
    platform.tibco.com/dataplane-id: ${DP_INSTANCE_ID}
    platform.tibco.com/controlplane-instance-id: ${CP_INSTANCE_ID}
EOF

kubectl create serviceaccount ${DP_INSTANCE_ID}-sa -n ${DP_INSTANCE_ID}-ns 2>/dev/null || echo "SA already exists"
```

## Step 2 — Create Image Pull Secret in DP Namespace

```bash
kubectl create secret docker-registry tibco-container-registry-credentials \
  --docker-server="${TP_CONTAINER_REGISTRY_URL}" \
  --docker-username="${TP_CONTAINER_REGISTRY_USER}" \
  --docker-password="${TP_CONTAINER_REGISTRY_PASSWORD}" \
  --docker-email="platform@company.com" \
  -n ${DP_INSTANCE_ID}-ns \
  --dry-run=client -o yaml | kubectl apply -f -
```

If using Amazon ECR, refresh the ECR login token (tokens expire after 12 hours):
```bash
aws ecr get-login-password --region "${AWS_REGION}" | \
  kubectl create secret docker-registry ecr-registry-credentials \
    --docker-server="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com" \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region "${AWS_REGION}") \
    -n ${DP_INSTANCE_ID}-ns \
    --dry-run=client -o yaml | kubectl apply -f -
```

## Step 3 — dp-config-aws (EKS-specific DP Infrastructure)

The `dp-config-aws` chart sets up EKS-specific storage classes, ingress configurations, and IRSA annotations for Data Plane components:

```bash
helm upgrade --install --wait --timeout 20m \
  -n ${DP_INSTANCE_ID}-ns \
  ${DP_INSTANCE_ID}-dp-config-aws tibco-platform-public/dp-config-aws \
  --set "global.tibco.dataPlane.id=${DP_INSTANCE_ID}" \
  --set "global.tibco.dataPlane.namespace=${DP_INSTANCE_ID}-ns" \
  --set "global.tibco.controlPlane.instanceId=${CP_INSTANCE_ID}" \
  --set "global.tibco.createNetworkPolicy=false" \
  --set "global.tibco.containerRegistry.url=${TP_CONTAINER_REGISTRY_URL}" \
  --set "global.tibco.containerRegistry.username=${TP_CONTAINER_REGISTRY_USER}" \
  --set "global.tibco.containerRegistry.password=${TP_CONTAINER_REGISTRY_PASSWORD}" \
  --set "global.imagePullSecrets[0].name=tibco-container-registry-credentials" \
  --set "ingress.className=${INGRESS_CLASS}" \
  --set "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn=${ACM_CERTIFICATE_ARN}" \
  --set "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme=internet-facing" \
  --set "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type=ip" \
  --set "ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname=*.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}"
```

## Step 4 — dp-configure-namespace

```bash
helm upgrade --install --wait --timeout 10m \
  -n ${DP_INSTANCE_ID}-ns \
  ${DP_INSTANCE_ID}-dp-configure-namespace tibco-platform-public/dp-configure-namespace \
  --set "global.tibco.dataPlane.id=${DP_INSTANCE_ID}" \
  --set "global.tibco.dataPlane.namespace=${DP_INSTANCE_ID}-ns" \
  --set "global.tibco.controlPlane.instanceId=${CP_INSTANCE_ID}" \
  --set "global.tibco.containerRegistry.url=${TP_CONTAINER_REGISTRY_URL}" \
  --set "global.tibco.containerRegistry.username=${TP_CONTAINER_REGISTRY_USER}" \
  --set "global.tibco.containerRegistry.password=${TP_CONTAINER_REGISTRY_PASSWORD}" \
  --set "global.tibco.serviceAccount=${DP_INSTANCE_ID}-sa" \
  --set "global.tibco.createNetworkPolicy=false" \
  --set "global.imagePullSecrets[0].name=tibco-container-registry-credentials"
```

## Step 5 — dp-core-infrastructure

```bash
helm upgrade --install --wait --timeout 20m \
  -n ${DP_INSTANCE_ID}-ns \
  ${DP_INSTANCE_ID}-dp-core-infrastructure tibco-platform-public/dp-core-infrastructure \
  --set "global.tibco.dataPlane.id=${DP_INSTANCE_ID}" \
  --set "global.tibco.dataPlane.namespace=${DP_INSTANCE_ID}-ns" \
  --set "global.tibco.controlPlane.instanceId=${CP_INSTANCE_ID}" \
  --set "global.tibco.controlPlane.host=https://admin.${CP_INSTANCE_ID}-my.${TP_BASE_DNS_DOMAIN}" \
  --set "global.tibco.containerRegistry.url=${TP_CONTAINER_REGISTRY_URL}" \
  --set "global.tibco.containerRegistry.username=${TP_CONTAINER_REGISTRY_USER}" \
  --set "global.tibco.containerRegistry.password=${TP_CONTAINER_REGISTRY_PASSWORD}" \
  --set "global.tibco.serviceAccount=${DP_INSTANCE_ID}-sa" \
  --set "global.tibco.createNetworkPolicy=false" \
  --set "global.imagePullSecrets[0].name=tibco-container-registry-credentials" \
  --set "global.tibco.dataPlane.dnsDomain=${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}" \
  --set "ingress.className=${INGRESS_CLASS}" \
  --set "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn=${ACM_CERTIFICATE_ARN}" \
  --set "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme=internet-facing" \
  --set "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type=ip" \
  --set "ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname=*.${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}"
```

Monitor:
```bash
kubectl get pods -n ${DP_INSTANCE_ID}-ns -w
```

## Step 6 — DNS Records for Data Plane

External DNS should auto-create Route 53 records from the ingress annotations. Verify:

```bash
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${TP_BASE_DNS_DOMAIN}" \
  --query 'HostedZones[0].Id' --output text)

aws route53 list-resource-record-sets \
  --hosted-zone-id "${HOSTED_ZONE_ID}" \
  --query "ResourceRecordSets[?contains(Name, '${DP_INSTANCE_ID}')]" \
  --output table
```

If records are missing, check external-dns logs:
```bash
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns --tail=50
```

## Step 7 — Register Data Plane in Control Plane

Open the Control Plane admin UI:
```
https://admin.${CP_INSTANCE_ID}-my.${TP_BASE_DNS_DOMAIN}
```

1. Go to **Infrastructure** → **Data Planes** → **Add Data Plane**
2. Fill in:
   - **Name**: `${DP_INSTANCE_ID}`
   - **Namespace**: `${DP_INSTANCE_ID}-ns`
   - **Ingress class**: `${INGRESS_CLASS}`
   - **DNS domain**: `${DP_INSTANCE_ID}.${TP_BASE_DNS_DOMAIN}`

## Step 8 — Verify

```bash
kubectl get pods -n ${DP_INSTANCE_ID}-ns
kubectl get pvc -n ${DP_INSTANCE_ID}-ns
kubectl get ingress -n ${DP_INSTANCE_ID}-ns -o wide
```

Check DP agent connectivity to CP:
```bash
kubectl logs -n ${DP_INSTANCE_ID}-ns \
  $(kubectl get pods -n ${DP_INSTANCE_ID}-ns -l app=dp-agent -o name | head -1) \
  --tail=50 | grep -E "connected|registered|error" | tail -20
```

## Troubleshooting

**ECR pull authentication**: ECR tokens expire after 12 hours. For production, set up IRSA for the DP service account with `ecr:GetAuthorizationToken` and related permissions, then use a token refresh CronJob.

**ALB not creating for DP ingress**: Check the ALB controller can see the new namespace and the ingress class annotation matches:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50 | grep ${DP_INSTANCE_ID}
```

**EFS PVC pending**: Verify the EFS security group allows port 2049 from the EKS node security group:
```bash
kubectl describe pvc -n ${DP_INSTANCE_ID}-ns | grep -E "Warning|ProvisioningFailed"
```

See `howto/how-to-cp-and-dp-eks-setup-guide.md` and `howto/how-to-dp-eks-setup-guide.md` for detailed guidance.
