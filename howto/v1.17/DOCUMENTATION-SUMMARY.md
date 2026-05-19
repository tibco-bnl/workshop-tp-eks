# TIBCO Platform v1.17.0 Documentation Summary

**Date**: May 19, 2026  
**Status**: ✅ Documentation Updated

---

## What Was Updated

This document summarizes the documentation updates made for TIBCO Platform v1.17.0 in the workshop-tp-eks repository.

---

## 1. Files Created/Updated

### New Files
```
howto/v1.17/
├── QUICK-REFERENCE.md         # Quick commands and v1.17 snippets for EKS
└── DOCUMENTATION-SUMMARY.md  # This file

releases/
└── v1.17.0.md                 # Full release notes for v1.17.0 (EKS + CP features)
```

### Modified Files
- **README.md** — Updated current release to v1.17.0; added Control Plane capability features to v1.17 section; links to new v1.17 howto files
- **releases/v1.17.0.md** — Added Control Plane capability features section and EKS-specific considerations

---

## 2. Key Changes from v1.16.0 to v1.17.0

### EKS Deployment Improvements

#### 1. Simplified DNS Structure (Recommended)
- **Single base domain**: Admin UI, subscription portal, and hybrid-proxy tunnel share one domain (e.g., `aws.example.com`)
- **One ACM certificate**: A single `*.${TP_BASE_DNS_DOMAIN}` wildcard cert replaces two separate certs
- **EKS Impact**: `scripts/env.sh` restructured with Option 1 (Simplified, default) and Option 2 (Legacy) DNS blocks

#### 2. Optional Hybrid-Proxy
- **Resource savings**: Set `CP_HYBRID_CONNECTIVITY=false` to save ~50% CPU/RAM when multi-cloud DP connectivity is not needed
- **EKS Impact**: Supported only with Simplified DNS (Option 1)

#### 3. Enhanced OTEL Observability
- OpenTelemetry Collector updated to **0.140.0**; fluent-bit OTEL config centralized in top-level chart
- Prometheus updated to **v3.5.2**, Alertmanager to **v0.32.0**

#### 4. BW5CE/BWCE Provisioner V2 Job Templates
- New parallel execution templates for significantly faster BW5 and BWCE provisioner bootstrapping

### Control Plane Capability Features

#### 5. Webhook Receiver for Alerts
- **What**: HTTP webhook integration for alert notifications
- **Format**: Standardized JSON payload to any external endpoint
- **Use Cases**: PagerDuty, ServiceNow, Slack, Teams, custom notification systems
- **EKS Impact**: Ensure Security Group and NetworkPolicy allow egress from `cp1-ns` to webhook endpoints

#### 6. OpenSearch Support for Observability
- **What**: OpenSearch can now be used as the backend for Jaeger traces and service logs
- **Alternative to**: Elasticsearch (ECK) — existing ECK deployments continue to work
- **EKS Options**: Amazon OpenSearch Service (VPC mode, simplest) or self-managed via OpenSearch Operator
- **Index Templates**: Required for TIBCO Platform workloads — apply before connecting

#### 7. Capability Management APIs
- **Update API (PUT)**: Update existing capability instances without re-provisioning
- **Upgrade API**: Upgrade capability instances via REST — enables CI/CD and Azure DevOps automation

#### 8. BW6 (Containers) — Custom Fluentbit
- **What**: Set customized Fluentbit configurations during BW6 capability provisioning or update
- **Requires**: Capability version 1.17.0+
- **EKS Impact**: If routing to CloudWatch, ensure IAM role has required `logs:*` permissions

#### 9. BW6 Classic — Full Lifecycle Management UI
- **What**: Agent, Domain, AppSpace, AppNode, and Application management now in Control Plane UI
- **Scope**: Create, update, delete, start, stop, deploy, undeploy all BW6 classic entities
- **Audit**: Application Command History and Execution History available

#### 10. BW5 — Application History
- **What**: New History tab in Application Configuration shows deploy/undeploy audit trail

#### 11. BW5 (Containers) — Custom Fluentbit + Hawk REST API
- **Fluentbit**: Set customized log pipeline during BW5CE capability provisioning or update
- **Hawk REST API**: New endpoint on port 8090 (`/commands`) exposes 31 Hawk methods via REST
- **EKS Impact**: Add Security Group ingress rule for port 8090 for BW5CE pods if needed

#### 12. Flogo — Fluentbit, Recipe Customization, New Connectors
- **Fluentbit**: Configure via Helm chart values (consistent with BW5/BW6 approach)
- **Recipe Editor**: YAML editor in Control Plane UI for capability provisioning/update
- **New Connectors**: Google Cloud Storage, TIBCO ActiveSpaces, TIBCO FTL

---

## 3. Component Versions

### Control Plane Components

| Component | v1.16.0 | v1.17.0 |
|-----------|---------|---------|
| tibco-cp-base | 1.16.0 | **1.17.0** |
| tibco-cp-bw | 1.16.0 | **1.17.0** |
| tibco-cp-flogo | 1.16.0 | **1.17.0** |
| tibco-cp-devhub | 1.16.0 | **1.17.0** |
| tibco-cp-addon-eventprocessing | 1.16.0 | **1.17.0** |
| tp-dp-monitor-agent | 1.16.x | **1.17.13** |
| tp-dp-license-file | 1.16.0 | **1.17.0** |
| tp-cp-proxy | 1.16.x | **1.17.4** |

### EKS Data Plane Components

| Component | v1.16.0 | v1.17.0 |
|-----------|---------|---------|
| dp-config-aws | 1.16.0 | **1.17.1+** |
| dp-configure-namespace | 1.16.x | **1.17.1** |
| dp-core-infrastructure | 1.16.x | **1.17.6** |
| o11y-service | 1.16.x | **1.17.16** |
| opentelemetry-collector-contrib | 0.116.x | **0.140.0** |
| infra-prometheus | v2.x | **v3.5.2** |
| infra-alertmanager | v0.27.x | **v0.32.0** |
| BW provisioner | 1.16.x | **1.17.6** |
| Flogo provisioner | 1.16.x | **1.17.11** |

---

## 4. EKS-Specific Considerations

### Container Registry
- No registry change from v1.16.0 — continue using `csgprdusw2reposaas.jfrog.io`

### Ingress (AWS ALB / Nginx)
- No ingress controller changes required for v1.17.0
- Existing ALB Ingress Controller and Nginx configurations remain compatible

### Storage (EFS/EBS)
- No storage class changes required for v1.17.0
- Existing Amazon EFS and EBS (gp3) configurations remain valid

### OpenSearch on EKS
- **Amazon OpenSearch Service** (recommended): Easiest option — deploy in same VPC, no operator needed
- **Self-managed**: Use OpenSearch Operator for Kubernetes
- Apply index templates before connecting TIBCO Platform

### Security Group Updates (if applicable)
- **BW5CE port 8090**: Add inbound rule for the new Hawk REST API endpoint in pod Security Group
- **Webhook Receiver**: Add outbound HTTPS (443) rule from Control Plane node group to webhook endpoint IPs/CIDRs

### NetworkPolicy Updates (if restrictive)
- **BW5CE port 8090**: Add ingress rule for port 8090 in Data Plane namespace
- **Webhook Receiver**: Add egress rule allowing outbound from `cp1-ns` to webhook endpoints

### CloudWatch Log Routing (Custom Fluentbit)
- If routing BW5/BW6/Flogo logs to CloudWatch, ensure the EKS node IAM role (or pod IRSA) has:
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`

---

## 5. Upgrade Considerations

### Recommended Upgrade Path
- **v1.16.0 → v1.17.0**: Direct upgrade supported
- **v1.15.0 → v1.17.0**: Not recommended — upgrade v1.15.0 → v1.16.0 first
- **v1.14.0 → v1.17.0**: Multi-step: v1.14.0 → v1.15.0 → v1.16.0 → v1.17.0

### Breaking Changes
1. **Simplified DNS is the new default** in `scripts/env.sh`. For upgrades with legacy DNS, use Option 2 block.
2. **Fluent-bit OTEL config removed from sub-charts**: Move custom overrides to top-level chart configuration.

### Post-Upgrade Checklist
- [ ] All pods running: `kubectl get pods -n cp1-ns`
- [ ] Helm releases healthy: `helm list -n cp1-ns`
- [ ] Ingress accessible: test admin console URL via Route 53 / ALB
- [ ] If using OpenSearch: apply index templates
- [ ] If using Webhook Alerts: configure Security Group/NetworkPolicy egress
- [ ] If using BW5CE: verify or update Security Group for port 8090
- [ ] If using Custom Fluentbit to CloudWatch: verify IAM permissions
