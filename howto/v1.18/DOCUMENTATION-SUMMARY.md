---
layout: default
title: TIBCO Platform v1.18.0 Documentation Summary - EKS
---

# TIBCO Platform v1.18.0 Documentation Summary - EKS

**Date**: June 11, 2026
**Status**: Documentation updated for 1.18.0 release

## Files Added

```text
howto/v1.18/
├── how-to-cp-and-dp-eks-setup-guide.md
├── QUICK-REFERENCE.md
└── DOCUMENTATION-SUMMARY.md

releases/
└── v1.18.0.md
```

## Key Changes from v1.17.0 to v1.18.0

| Area | 1.18.0 Change | EKS Impact |
|------|---------------|------------|
| Gateway API | Gateway API Controller support for Control Tower data planes | EKS Traefik users can evaluate Gateway API endpoint exposure |
| RBAC | Namespace-level RBAC for Application Manager and Application Viewer | Review Data Plane namespaces and role assignments after upgrade |
| Email | Email server configuration moved to Platform Console | Remove deprecated Helm values; configure SES, SMTP, or SendGrid in UI |
| Alerts | Alerts Audit Trail page | Add alert audit validation to post-upgrade checks |
| Developer Hub | Self-service flows | Upgrade Developer Hub charts with the release |
| DNS | Simplified DNS continues | Keep one Route 53 base domain and one ACM wildcard certificate |
| Database | Aurora PostgreSQL SSL guidance clarified | Use `require` or `verify-full` when `rds.force_ssl=1` is enforced |

## Component Versions

| Component | v1.17.0 | v1.18.0 |
|-----------|---------|---------|
| `tibco-cp-base` | `1.17.0` | `1.18.0` |
| `tibco-cp-bw` | `1.17.0` | `1.18.0` |
| `tibco-cp-flogo` | `1.17.0` | `1.18.0` |
| `tibco-cp-devhub` | `1.17.0` | `1.18.0` |
| `tibco-cp-hawk` | `1.17.x` | `1.18.12` |
| `tp-cp-proxy` | `1.17.4` | `1.18.0` |
| `dp-configure-namespace` | `1.17.1` | `1.18.3` |
| `dp-core-infrastructure` | `1.17.6` | `1.18.4` |

## EKS-Specific Updates

### Route 53 and ACM

Simplified DNS remains the recommended path. Use one wildcard Route 53 alias record and one ACM wildcard certificate for `*.${TP_BASE_DNS_DOMAIN}`. Keep legacy `cp1-my` and `cp1-tunnel` domains only for upgrades or explicitly separated deployments.

### Amazon Aurora PostgreSQL

The shared guide now calls out that Crossplane-created Aurora clusters may enforce `rds.force_ssl=1`. Set `TP_DB_SSL_MODE=require` for encrypted connections or `verify-full` when certificate verification is required.

### Email

The 1.18 examples no longer emit `global.external.emailServerType`, `global.external.emailServer`, `global.external.fromAndReplyToEmailAddress`, `global.external.cronJobReportsEmailAlias`, or `global.external.platformEmailNotificationCcAddresses` values. Configure SES, SMTP, or SendGrid from the Platform Console after deployment. The remaining `global.tibco.networkPolicy.emailServer` block in `tibco-cp-base` is only for optional egress NetworkPolicy creation.

### Gateway API

The docs keep the existing ALB plus Nginx or Traefik ingress as the baseline and describe Gateway API as an optional 1.18 evaluation path for supported capabilities.

## Updated Files

- `README.md` - current release, release matrix, and EKS documentation index
- `howto/how-to-cp-and-dp-eks-setup-guide.md` - 1.18 baseline notes, email changes, and chart version
- `howto/how-to-add-dns-records-eks-aws.md` - simplified DNS and Route 53 guidance
- `docs/firewall-requirements-eks.md` - explicit 1.18 TIBCO documentation links
- `howto/prerequisites-checklist-for-customer.md` - chart version references
- `scripts/env.sh` - comments for 1.18 email, RDS SSL behavior, and upstream AWS helper script location
- `pipelines/azure-devops/deploy-tibco-control-plane.yml` - avoids deprecated 1.18 email Helm values

## Upstream Helper Scripts

The AWS provisioning helper scripts used by the shared guide remain maintained in the upstream [tp-helm-charts EKS scripts directory](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks/scripts). This workshop references them with direct download commands instead of copying them locally.

Relevant upstream helpers:

- `get-cluster-details.sh`
- `create-crossplane-role.sh`
- `create-efs-control-plane.sh`
- `create-rds.sh`
- `create-efs-data-plane.sh`

## Validation Checklist

- [ ] Internal links use GitHub Pages extensionless routes.
- [ ] `git diff --check` passes.
- [ ] 1.18 release and overlay links are reachable on GitHub Pages after `gh-pages` publishes.
- [ ] Helm values generated for 1.18 do not include deprecated email fields.
