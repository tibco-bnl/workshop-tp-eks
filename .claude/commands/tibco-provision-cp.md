You are helping deploy the TIBCO Platform Control Plane on Amazon EKS. Follow these steps in order, running each command and verifying the output before continuing.

## Before You Start

Confirm `tibco-prerequisites` has passed. Then verify these values are set:

```bash
echo "CP_INSTANCE_ID=${CP_INSTANCE_ID}"
echo "TP_BASE_DNS_DOMAIN=${TP_BASE_DNS_DOMAIN}"
echo "TP_CLUSTER_NAME=${TP_CLUSTER_NAME}"
echo "AWS_REGION=${AWS_REGION}"
echo "ACM_CERTIFICATE_ARN=${ACM_CERTIFICATE_ARN}"
echo "CP_DB_HOST=${CP_DB_HOST}"
echo "TP_CONTAINER_REGISTRY_URL=${TP_CONTAINER_REGISTRY_URL}"
```

Check the latest available chart version:
```bash
helm search repo tibco-platform-public/tibco-cp-base --versions | head -5
```

## Step 1 — Verify Pre-Installed Components

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager not installed"
kubectl get storageclass | grep -E "efs|ebs|gp3"
```

## Step 2 — Cert-Manager (if not already installed)

```bash
helm repo add jetstack https://charts.jetstack.io && helm repo update

helm upgrade --install --wait --timeout 10m \
  --create-namespace -n cert-manager cert-manager jetstack/cert-manager \
  --set installCRDs=true

kubectl get pods -n cert-manager
```

## Step 3 — External DNS with IRSA

External DNS auto-creates Route 53 records for CP ingress. Verify IRSA service account exists:

```bash
kubectl get sa -n external-dns-system 2>/dev/null | grep external-dns || \
  echo "external-dns service account not found"
```

If missing, create IRSA and install:
```bash
# Create IRSA service account (requires Route53 IAM policy)
eksctl create iamserviceaccount \
  --cluster "${TP_CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --namespace external-dns-system \
  --name external-dns \
  --attach-policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/ExternalDNSPolicy \
  --approve

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ && helm repo update
helm upgrade --install --wait --timeout 10m --create-namespace \
  -n external-dns-system external-dns external-dns/external-dns \
  --set provider=aws \
  --set "domainFilters[0]=${TP_BASE_DNS_DOMAIN}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=external-dns \
  --set txtOwnerId="${TP_CLUSTER_NAME}"
```

## Step 4 — Ingress Controller (Nginx or Traefik)

Check if an ingress controller is running:
```bash
kubectl get pods -n ingress-system 2>/dev/null | head -5
kubectl get ingressclass
```

If missing, install Nginx Ingress with AWS ALB frontend:
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update
helm upgrade --install --wait --timeout 10m --create-namespace \
  -n ingress-system ingress-nginx ingress-nginx/ingress-nginx \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type=external" \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type=ip" \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme=internet-facing" \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert=${ACM_CERTIFICATE_ARN}" \
  --set "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-ports=443"
```

Get the ingress class name:
```bash
INGRESS_CLASS=$(kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}')
echo "Ingress class: ${INGRESS_CLASS}"
```

## Step 5 — Prepare Helm Values

```bash
cat > /tmp/tibco-cp-values.yaml << EOF
global:
  tibco:
    containerRegistry:
      url: ${TP_CONTAINER_REGISTRY_URL}
      username: ${TP_CONTAINER_REGISTRY_USER}
      password: ${TP_CONTAINER_REGISTRY_PASSWORD}
    serviceAccount: ${CP_INSTANCE_ID}-sa
    createNetworkPolicy: false
    enableLogging: true
  imagePullSecrets:
    - name: tibco-container-registry-credentials
  certificates:
    secretName: ""

tibco:
  controlPlane:
    baseConfig:
      cpInstanceId: ${CP_INSTANCE_ID}
      cpNamespace: ${CP_INSTANCE_ID}-ns
      serviceAccount: ${CP_INSTANCE_ID}-sa
    dnsConfig:
      baseDnsDomain: ${TP_BASE_DNS_DOMAIN}
    database:
      dbHost: ${CP_DB_HOST}
      dbPort: "5432"
      dbName: "${CP_INSTANCE_ID}postgres"
      secretRef: ${CP_INSTANCE_ID}-provider-cp-database
    sessionConfig:
      sessionKeysSecretRef: session-keys
    encryptionConfig:
      encryptionSecretRef: cporch-encryption-secret
    ingress:
      className: "${INGRESS_CLASS:-nginx}"
      annotations:
        kubernetes.io/ingress.class: "${INGRESS_CLASS:-nginx}"
        alb.ingress.kubernetes.io/certificate-arn: "${ACM_CERTIFICATE_ARN}"
        alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: ip
        external-dns.alpha.kubernetes.io/hostname: "*.${CP_INSTANCE_ID}-my.${TP_BASE_DNS_DOMAIN},*.${CP_INSTANCE_ID}-tunnel.${TP_BASE_DNS_DOMAIN}"
EOF
```

Review and confirm:
```bash
cat /tmp/tibco-cp-values.yaml
```

## Step 6 — Install TIBCO Control Plane

```bash
helm upgrade --install --wait --timeout 60m \
  --create-namespace -n ${CP_INSTANCE_ID}-ns \
  ${CP_INSTANCE_ID}-tibco-cp tibco-platform-public/tibco-cp-base \
  -f /tmp/tibco-cp-values.yaml
```

This takes 10-20 minutes. Monitor:
```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns -w
```

## Step 7 — Verify Deployment

```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns
kubectl get pvc -n ${CP_INSTANCE_ID}-ns
kubectl get ingress -n ${CP_INSTANCE_ID}-ns -o wide
```

Check for problem pods:
```bash
kubectl get pods -n ${CP_INSTANCE_ID}-ns \
  --field-selector='status.phase!=Running,status.phase!=Succeeded'
```

## Step 8 — Verify DNS and ALB

Check that external-dns created the Route 53 records:
```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id $(aws route53 list-hosted-zones-by-name \
    --dns-name "${TP_BASE_DNS_DOMAIN}" \
    --query 'HostedZones[0].Id' --output text) \
  --query "ResourceRecordSets[?contains(Name, '${CP_INSTANCE_ID}')]" \
  --output table
```

Check ALB provisioning:
```bash
kubectl describe ingress -n ${CP_INSTANCE_ID}-ns | grep -E "Address:|LoadBalancer"
```

## Step 9 — Access the Control Plane

Admin URL:
```
https://admin.${CP_INSTANCE_ID}-my.${TP_BASE_DNS_DOMAIN}
```

Get initial admin credentials:
```bash
kubectl get secret -n ${CP_INSTANCE_ID}-ns | grep -i admin
kubectl get secret -n ${CP_INSTANCE_ID}-ns tibco-cp-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d && echo
```

## Troubleshooting

**ALB not provisioned**: Check aws-load-balancer-controller logs:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50 | grep -i error
```

**DNS records not created**: Check external-dns logs:
```bash
kubectl logs -n external-dns-system -l app.kubernetes.io/name=external-dns --tail=50
```

**Aurora PostgreSQL connection refused**: Verify the security group allows port 5432 from the EKS node security group:
```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*rds*" \
  --query 'SecurityGroups[*].{ID:GroupId, Name:GroupName}' --output table
```

See the setup guide at `howto/how-to-cp-and-dp-eks-setup-guide.md` for detailed steps.
