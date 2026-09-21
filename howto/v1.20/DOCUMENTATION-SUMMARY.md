---
layout: default
title: TIBCO Platform v1.20.0 Documentation Summary - EKS
---

# TIBCO Platform v1.20.0 Documentation Summary - EKS

**Date**: September 21, 2026
**Status**: Documentation updated for the 1.20.0 release (and the skipped 1.19.0 release)

## Files Added

```text
howto/v1.19/
├── how-to-cp-and-dp-eks-setup-guide.md
├── QUICK-REFERENCE.md
└── DOCUMENTATION-SUMMARY.md

howto/v1.20/
├── how-to-cp-and-dp-eks-setup-guide.md
├── QUICK-REFERENCE.md
└── DOCUMENTATION-SUMMARY.md

releases/
├── v1.19.0.md
└── v1.20.0.md
```

## Key Changes from v1.18.0 to v1.20.0

| Area | Change | Release | EKS Impact |
|------|--------|---------|------------|
| Helm values | `global.tibco.networkPolicy.createDeprecatedPolicies` removed | 1.19.0 | Delete from `aws-tibco-cp-base-values.yaml` before upgrading |
| Helm values | `otel-collector.enabled` default `false` -> `true` -> `false` | 1.19.0 / 1.20.0 | Set explicitly; `true` needs a reachable log server |
| Helm values | `global.tibco.disabledInfraCapabilities: [MFTADAPTER]` added | 1.20.0 | MFT off by default; set `[]` to enable all |
| Gateway API | `hybrid-proxy` HTTPRoute renders `/infra/tunnel`; `/` only when `dnsDomain != dnsTunnelDomain` (PCP-21362 fixed) | 1.19.0 | Shared wildcard hostname works with simplified DNS; hostname separation optional |
| Observability | Jaeger recipe moved to v2 (chart 4.8.x, Jaeger 2.19.0); OpenTelemetry Collector 0.156.2; OTLP custom headers | 1.19.0 / 1.20.0 | Old traces show as red dots (PCP-20148) |
| Rollback | Control Plane rollback via `helm rollback` (schema handled automatically when `manageDbSchema: true`) | 1.20.0 | Record `helm history` before upgrading |
| Data Plane RBAC | `dp-configure-namespace` adds `rbac.infraMcp*`, `rbac.mcpGateway`, `rbac.springboot`; drops `networkPolicy.createDeprecatedPolicies` | 1.19.10 | Remove the old `--set` from saved commands |
| Aurora | Upstream workshop creates the cluster parameter group with the AWS CLI (`dbClusterParameterGroupName`) | 1.20.0 docs | Keep `TP_DB_SSL_MODE=require` or `verify-full` |
| AI / MCP | TESSA (Preview), Infra MCP Server, MCP Hub with MCP Gateway (Preview) | 1.19.0 / 1.20.0 | TESSA and MCP Hub are TIBCO Operated CP only; Infra MCP Server can be provisioned on EKS Data Planes |
| Capabilities | ActiveSpaces capability; Flogo build Jobs and app-init resources; Developer Hub Backstage 1.51.0, MCP server, MCP Catalog | 1.19.0 / 1.20.0 | Upgrade capability charts with the release |
| Ingress | NGINX Ingress Controller support removed (wording unchanged since 1.18.0) | 1.19.0 / 1.20.0 | Use Traefik or Gateway API |

## Component Versions

| Component | v1.18.0 | v1.19.0 | v1.20.0 |
|-----------|---------|---------|---------|
| `tibco-cp-base` | `1.18.0` | `1.19.0` | `1.20.0` |
| `tibco-cp-bw` | `1.18.0` | `1.19.0` | `1.20.0` |
| `tibco-cp-flogo` | `1.18.0` | `1.19.0` | `1.20.0` |
| `tibco-cp-devhub` | `1.18.0` | `1.19.0` | `1.20.0` |
| `tibco-cp-hawk` | `1.18.12` | `1.19.23` | `1.20.8` |
| `tibco-developer-hub` | `1.18.12` | `1.19.8` | `1.20.8` |
| `tibco-cp-messaging` | `1.15.31` | `1.19.23` | `1.19.23` |
| `tp-cp-proxy` | `1.18.0` | `1.19.1` | `1.20.2` |
| `artifactmanager` | `1.18.1` | `1.19.4` | `1.20.0` |
| `o11yservice` | `1.18.13` | `1.19.16` | `1.20.5` |
| `tp-dp-monitor-agent` | `1.18.9` | `1.19.11` | `1.20.2` |
| `jaeger` | `0.72.41` | `4.8.2` | `4.8.3` |
| `dp-configure-namespace` | `1.18.3` | `1.19.10` | `1.20.0` |
| `dp-core-infrastructure` | `1.18.4` | `1.19.5` | `1.20.3` |
| `bwprovisioner` / `bw5provisioner` | `1.18.4` | `1.19.7` | `1.20.2` |
| `flogoprovisioner` | `1.18.4` | `1.19.11` | `1.20.10` |
| `dp-flogo-app` | `1.18.10` | `1.19.13` | `1.20.8` |
| `tp-dp-infra-mcp-server` | n/a | `1.19.0` | `1.20.0` |
| `tp-mcp-gateway` | n/a | n/a | `1.20.0` |

## Supported Versions (official 1.20.0 documentation)

- Highest certified Kubernetes for the Control Plane cluster: Amazon EKS 1.35.
- Helm 3.17.0 or later; PostgreSQL 16 with `uuid-ossp`.
- Ingress: Traefik 3.3.4. Gateway API: NGINX Gateway Fabric 2.3.0, Istio 1.28.2, Traefik `traefik-39.0.7`, NetScaler `netscaler-cpx-with-gateway-controller-2.0.0`.
- Upstream EKS workshop tooling: kubectl v1.34.3, aws-cli 2.27.31, eksctl 0.210.0, Helm v3.18.0, `TP_KUBERNETES_VERSION="1.33"`.

## Updated Files

- `README.md` - current release 1.20.0, release matrix with 1.19.0, EKS documentation index, official links
- `howto/how-to-cp-and-dp-eks-setup-guide.md` - 1.20.0 chart version, Gateway API section rewritten for the fixed hybrid-proxy route, values notes, 1.20.0 documentation links
- `howto/how-to-dp-eks-setup-guide.md`, `howto/how-to-dp-eks-observability.md`, `howto/how-to-add-dns-records-eks-aws.md`, `howto/prerequisites-checklist-for-customer.md`, `docs/firewall-requirements-eks.md`, `howto/how-to-sync-images.md`, `howto/topology-options.md` - 1.20.0 documentation links and chart versions
- `scripts/env.sh` - 1.20.0 references
- `pipelines/azure-devops/deploy-tibco-control-plane.yml` - default `tibco-cp-base` chart version 1.20.0
- `releases/v1.18.0.md`, `howto/v1.18/QUICK-REFERENCE.md` - status changed to previous release

## Upstream Helper Scripts

The AWS provisioning helper scripts remain in the upstream [tp-helm-charts EKS scripts directory](https://github.com/TIBCOSoftware/tp-helm-charts/tree/main/docs/workshop/eks/scripts). New since 1.18.0 in `tp-helm-charts/scripts`: `verify-release.sh` (validates deployed images and chart versions against the `artifacts/` manifests), `1.19.0/upgrade.sh`, `1.20.0/upgrade.sh`, and the `database/postgres` `upgradeDbSchema` / `rollbackDbSchema` commands.

## Validation Checklist

- [ ] Internal links use GitHub Pages extensionless routes.
- [ ] `git diff --check` passes.
- [ ] 1.19 and 1.20 release and overlay links are reachable on GitHub Pages after `gh-pages` publishes.
- [ ] Helm values generated for 1.20.0 do not include `createDeprecatedPolicies` or deprecated email fields.
