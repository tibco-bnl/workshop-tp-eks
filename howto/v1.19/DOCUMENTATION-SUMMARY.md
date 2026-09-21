---
layout: default
title: TIBCO Platform v1.19.0 Documentation Summary - EKS
---

# TIBCO Platform v1.19.0 Documentation Summary - EKS

**Date**: September 21, 2026
**Status**: Documentation added retroactively together with the 1.20.0 update

## Files Added

```text
howto/v1.19/
├── how-to-cp-and-dp-eks-setup-guide.md
├── QUICK-REFERENCE.md
└── DOCUMENTATION-SUMMARY.md

releases/
└── v1.19.0.md
```

## Key Changes from v1.18.0 to v1.19.0

| Area | 1.19.0 Change | EKS Impact |
|------|---------------|------------|
| Helm values | `global.tibco.networkPolicy.createDeprecatedPolicies` removed | Delete from values files |
| Helm values | `otel-collector.enabled` default `false` -> `true` | Set explicitly |
| Gateway API | `hybrid-proxy` HTTPRoute fixed (PCP-21362): `/infra/tunnel` always, `/` only for split DNS | Hostname separation no longer required with simplified DNS |
| Observability | Jaeger v2 (chart 4.8.2), OpenTelemetry Collector 0.156.2, PromQL cards | PCP-20148 red dots for old traces; PCP-23331 Elasticsearch export workaround |
| AI / MCP | TESSA (Preview, TIBCO Operated CP US only), Infra MCP Server capability | Infra MCP Server optional on self-hosted EKS |
| Capabilities | ActiveSpaces capability, BW5/BW6 updates, Flogo build cleanup API and app-init resources, Developer Hub Backstage 1.51.0 + MCP server, EMS API | Upgrade capability charts with the release |
| Data Plane RBAC | `dp-configure-namespace` 1.19.10 adds `rbac.infraMcp*`, `rbac.mcpGateway`, `rbac.springboot`; removes `networkPolicy.createDeprecatedPolicies` | Update saved DP install commands |
| Ingress | NGINX Ingress Controller support removed (unchanged wording since 1.18.0) | Traefik or Gateway API |

## Component Versions

| Component | v1.18.0 | v1.19.0 |
|-----------|---------|---------|
| `tibco-cp-base` | `1.18.0` | `1.19.0` |
| `tibco-cp-bw` | `1.18.0` | `1.19.0` |
| `tibco-cp-flogo` | `1.18.0` | `1.19.0` |
| `tibco-cp-devhub` | `1.18.0` | `1.19.0` |
| `tibco-cp-hawk` | `1.18.12` | `1.19.23` |
| `tibco-cp-messaging` | `1.15.31` | `1.19.23` |
| `tp-cp-proxy` | `1.18.0` | `1.19.1` |
| `o11yservice` | `1.18.13` | `1.19.16` |
| `tp-dp-monitor-agent` | `1.18.9` | `1.19.11` |
| `jaeger` | `0.72.41` | `4.8.2` |
| `dp-configure-namespace` | `1.18.3` | `1.19.10` |
| `dp-core-infrastructure` | `1.18.4` | `1.19.5` |

## Upstream Scripts

- `scripts/1.19.0/upgrade.sh` in `tp-helm-charts`: interactive 1.18.0 to 1.19.0 assistant; no value transformations.
- `scripts/verify-release.sh` (new): validates deployed images and chart versions against `artifacts/<folder>/<folder>-1.19.0-{images,charts}.txt`.
- `scripts/database/postgres`: `postgres-helper.bash upgradeDbSchema <chart-version>` and `rollbackDbSchema <chart-version>`; version map adds 1.19.0 (`tscutd` 22, `idm` 8).
- `scripts/sync-artifacts/sync-images.sh`: registry-to-registry copy via Docker Buildx; the air-gapped guide now recommends it over `docker pull/push`.

## Official Sources

- [TIBCO Platform Control Plane 1.19.0 Documentation](https://docs.tibco.com/pub/platform-cp/1.19.0/doc/html/Default.htm)
- [Official 1.19.0 New Features](https://docs.tibco.com/pub/platform-cp/1.19.0/doc/html/Release-Notes/new-features.htm)
- [Official 1.19.0 Known Issues](https://docs.tibco.com/pub/platform-cp/1.19.0/doc/html/Release-Notes/known-issues.htm)
- [TIBCO tp-helm-charts repository](https://github.com/TIBCOSoftware/tp-helm-charts)
