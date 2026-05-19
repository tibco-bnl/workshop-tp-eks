# TIBCO Platform v1.17.0 Quick Reference Guide — EKS

**TIBCO Platform Version**: 1.17.0 | **Platform**: Amazon EKS | **Status**: ✅ Production Ready

---

## Quick Access URLs

| Service | URL Pattern | Notes |
|---------|-------------|-------|
| **Admin Console** | `https://admin.<TP_BASE_DNS_DOMAIN>` | Simplified DNS (Option 1) |
| **Admin Console** | `https://admin.${CP_INSTANCE_ID}-my.<domain>` | Legacy DNS (Option 2) |
| **Subscription Portal** | `https://<hostPrefix>.<TP_BASE_DNS_DOMAIN>` | Simplified DNS |

---

## Essential Commands

### Get Admin Password
```bash
kubectl get secret tp-cp-web-server -n cp1-ns -o jsonpath='{.data.TSC_ADMIN_PASSWORD}' | base64 -d && echo
```

### Check All Pods
```bash
kubectl get pods -n cp1-ns
```

### View Helm Releases
```bash
helm list -n cp1-ns
```

### Check Ingress (ALB)
```bash
kubectl get ingress -n cp1-ns
kubectl get ingress -n cp1-ns -o jsonpath='{.items[*].status.loadBalancer.ingress[*].hostname}'
```

### View Logs (Control Plane Core)
```bash
kubectl logs -n cp1-ns -l app=tp-cp-infra --tail=100
```

### Check Database Connectivity
```bash
kubectl run psql-test -n cp1-ns --rm -it --image=postgres:15 -- \
  psql -h <aurora-writer-endpoint> -U postgres -d postgres
```

### EKS Cluster Info
```bash
kubectl get nodes -o wide
kubectl cluster-info
aws eks describe-cluster --name ${TP_CLUSTER_NAME} --region ${AWS_REGION}
```

---

## Helm Charts (v1.17.0)

### Control Plane Charts

| Chart | Version | Release Name |
|-------|---------|--------------|
| tibco-cp-base | 1.17.0 | tibco-cp-base |
| tibco-cp-bw | 1.17.0 | tibco-cp-bw |
| tibco-cp-flogo | 1.17.0 | tibco-cp-flogo |
| tibco-cp-devhub | 1.17.0 | tibco-cp-devhub |
| tibco-cp-addon-eventprocessing | 1.17.0 | tibco-cp-addon-eventprocessing |
| tp-dp-monitor-agent | 1.17.13 | tp-dp-monitor-agent |
| tp-dp-license-file | 1.17.0 | tp-dp-license-file |
| tp-cp-proxy | 1.17.4 | tp-cp-proxy |

---

## New in v1.17.0 — Quick Reference

### Webhook Receiver Setup
```bash
# Test egress connectivity from cp1-ns to your webhook endpoint
kubectl run curl-test -n cp1-ns --rm -it --image=curlimages/curl -- \
  curl -X POST <your-webhook-url> \
  -H "Content-Type: application/json" \
  -d '{"test": "tibco-platform-webhook-test"}'

# Check Security Group allows outbound HTTPS (443) from EKS node group to webhook endpoint
aws ec2 describe-security-groups --group-ids <node-sg-id>

# Check NetworkPolicy allows egress from cp1-ns (if restrictive policies in place)
kubectl get networkpolicy -n cp1-ns
```

### OpenSearch for Observability

#### Option A: Amazon OpenSearch Service (Recommended for EKS)
```bash
# Create Amazon OpenSearch Service domain in same VPC as EKS
aws opensearch create-domain \
  --domain-name tibco-platform-os \
  --engine-version OpenSearch_2.11 \
  --cluster-config InstanceType=r6g.large.search,InstanceCount=2 \
  --vpc-options SubnetIds=<subnet-id>,SecurityGroupIds=<os-sg-id> \
  --ebs-options EBSEnabled=true,VolumeType=gp3,VolumeSize=100

# Verify domain is active
aws opensearch describe-domain --domain-name tibco-platform-os \
  --query 'DomainStatus.Processing'

# Get VPC endpoint for configuration in TIBCO Platform UI
aws opensearch describe-domain --domain-name tibco-platform-os \
  --query 'DomainStatus.Endpoints.vpc'

# Apply TIBCO Platform index templates (required before connecting)
# See: https://docs.tibco.com/pub/platform-cp/latest/doc/html/UserGuide/jaeger-opensearch-index-template.htm
```

#### Option B: Self-Managed OpenSearch on EKS
```bash
# Deploy OpenSearch Operator for Kubernetes
kubectl apply -f https://opensearch-operator-release-url/opensearch-operator.yaml

# Create OpenSearch cluster in observability namespace
kubectl apply -f opensearch-cluster.yaml -n elastic-system

# Verify OpenSearch is running
kubectl get pods -n elastic-system -l app.kubernetes.io/name=opensearch

# Apply TIBCO Platform index templates
# See: https://docs.tibco.com/pub/platform-cp/latest/doc/html/UserGuide/jaeger-opensearch-index-template.htm
```

### BW5CE Hawk REST API (Port 8090)
```bash
# Test Hawk REST API in BW5CE pod
kubectl exec -it <bw5ce-pod-name> -n dp1-ns -- \
  curl -s http://localhost:8090/commands

# Check if Security Group allows port 8090 for BW5CE pods
aws ec2 describe-security-groups --group-ids <dp-sg-id> \
  --query 'SecurityGroups[*].IpPermissions[?FromPort==`8090`]'

# Add port 8090 NetworkPolicy if restrictive policies are in place
kubectl patch networkpolicy <bw5ce-netpol> -n dp1-ns \
  --type=json \
  -p='[{"op":"add","path":"/spec/ingress/-","value":{"ports":[{"port":8090,"protocol":"TCP"}]}}]'
```

### Custom Fluentbit Config (BW5/BW6 Containers)

#### Route to CloudWatch
```bash
# Verify IAM permissions for CloudWatch log routing
aws iam get-role-policy --role-name <eks-node-role> --policy-name CloudWatchLogsPolicy

# Required permissions:
# logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
```

```yaml
# Example Helm values for custom Fluentbit in BW6 Capability routing to CloudWatch
fluentbit:
  customConfig: |
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        Parser docker
        Tag bw6.*
    [OUTPUT]
        Name  cloudwatch_logs
        Match bw6.*
        region ${AWS_REGION}
        log_group_name /tibco-platform/bw6-logs
        log_stream_prefix bw6-
        auto_create_group true
```

#### Route to OpenSearch / Elasticsearch
```yaml
# Example Helm values for custom Fluentbit routing to OpenSearch
fluentbit:
  customConfig: |
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        Parser docker
        Tag bw6.*
    [OUTPUT]
        Name  opensearch
        Match bw6.*
        Host  <opensearch-vpc-endpoint>
        Port  443
        TLS   On
        Index bw6-logs
```

### Flogo Recipe Customization
```yaml
# Navigate in Control Plane UI:
# Data Planes → <DP Name> → Capabilities → Flogo → Provision/Update
# Use the Recipe Editor to customize resource allocations:
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

---

## DNS Configuration Quick Reference

### Simplified DNS (Option 1 — Recommended)
```bash
# Key environment variables
export TP_BASE_DNS_DOMAIN="aws.example.com"
export CP_ADMIN_HOST_PREFIX="admin"
export CP_SUBSCRIPTION="dev"
export CP_HYBRID_CONNECTIVITY="true"   # set false to disable hybrid-proxy
export TP_BASE_DOMAIN_CERT_ARN="arn:aws:acm:us-east-1:123456789:certificate/..."

# Route 53 records needed (specific A-records per host)
# admin.aws.example.com → ALB address
# dev.aws.example.com   → ALB address
# tunnel.aws.example.com → ALB address (if hybrid-proxy enabled)
```

### Legacy DNS (Option 2 — Backward Compatible)
```bash
# Key environment variables
export TP_MY_DOMAIN="cp1-my.aws.example.com"
export TP_TUNNEL_DOMAIN="cp1-tunnel.aws.example.com"
```

### Route 53 Management
```bash
# Get current ALB hostname
kubectl get ingress -n cp1-ns -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# List Route 53 hosted zones
aws route53 list-hosted-zones-by-name --dns-name <your-domain>

# Check DNS propagation
nslookup admin.<TP_BASE_DNS_DOMAIN>
dig admin.<TP_BASE_DNS_DOMAIN>
```

---

## Upgrade to v1.17.0

```bash
# 1. Backup critical secrets
kubectl get secret session-keys -n cp1-ns -o yaml > session-keys-backup.yaml
kubectl get secret cporch-encryption-secret -n cp1-ns -o yaml > cporch-secret-backup.yaml

# 2. Update Helm repository
helm repo update

# 3. Upgrade Control Plane base
helm upgrade --install --wait --timeout 2h \
  -n cp1-ns tibco-cp-base tibco-cp-base \
  --repo "${TP_TIBCO_HELM_CHART_REPO}" --version "1.17.0" \
  -f aws-tibco-cp-base-values.yaml

# 4. Verify
kubectl get pods -n cp1-ns
helm list -n cp1-ns
```

---

## Troubleshooting

### Pods Not Starting
```bash
kubectl describe pod <pod-name> -n cp1-ns
kubectl get events -n cp1-ns --sort-by='.lastTimestamp'
```

### ALB Not Created / No Address
```bash
# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Check IAM role for ALB controller
aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole
```

### DNS Not Resolving
```bash
# Check External DNS (if used)
kubectl get pods -n external-dns
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50

# Manual Route 53 check
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?Name=='admin.<domain>.']"
```

### Helm Release in Failed State
```bash
# Check actual pod status (helm status may be misleading)
kubectl get pods -n cp1-ns
# If pods are running, the platform is operational
```

### Database Connection Issues
```bash
# Run psql test pod
kubectl run psql-test -n cp1-ns --rm -it --image=postgres:15 -- \
  psql -h <aurora-endpoint> -U postgres -d postgres

# Check Security Group rules allow EKS → Aurora (port 5432)
aws ec2 describe-security-groups --group-ids <aurora-sg-id>
```

### OpenSearch / Elasticsearch Connection
```bash
# If using Amazon OpenSearch Service
aws opensearch describe-domain --domain-name tibco-platform-os \
  --query 'DomainStatus.{Status:Processing,VpcEndpoint:Endpoints.vpc}'

# If self-managed on EKS
kubectl get pods -n elastic-system
kubectl logs -n elastic-system <opensearch-pod> --tail=50
```

---

## EKS vs AKS/ARO — CLI Differences

| Task | EKS | AKS | ARO |
|------|-----|-----|-----|
| CLI tool | `kubectl` | `kubectl` | `oc` |
| Ingress type | AWS ALB + Ingress | Traefik + Ingress | OpenShift Routes |
| Storage | EFS + EBS | Azure Files + Azure Disk | Azure Files + Azure Disk |
| DNS | Route 53 | Azure DNS | Azure DNS |
| Certs | ACM (ARN) | cert-manager | cert-manager |
| Security | Security Groups | Network Security Groups | SCC + Network Policies |
