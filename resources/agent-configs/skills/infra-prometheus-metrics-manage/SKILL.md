---
name: infra-prometheus-metrics-manage
description: "Operate Prometheus metrics, exporters, PromQL, Alertmanager configuration, and Grafana dashboards/provisioning on Linux or GCP. Use when tasks mention Prometheus, PromQL, promtool, Alertmanager, amtool, Grafana, node_exporter, postgres_exporter, scrape configuration, or metric cardinality."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/prometheus-grafana
  license: MIT
---

# Prometheus metrics manage

Design and operate Prometheus-compatible metrics collection and Grafana visualization. Prefer managed Cloud Monitoring where it fits; add self-hosted components only for a concrete requirement.

## Triggers

- Scrape configuration, GCE discovery, exporters, PromQL, or recording rules
- Prometheus/Alertmanager operation, target health, or metrics cardinality
- Grafana data sources, dashboards as code, provisioning, or read-only backups

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or service README if present
IF task involves choosing the metrics backend or collection/storage defaults
  IF file "~/.junie/custom/configs/infrastructure/prometheus.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/prometheus.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves Prometheus, scrape configuration, exporters, or PromQL
  REFERENCE "references/prometheus-grafana.md"
IF task involves Alertmanager routing or metric-based notifications
  REFERENCE "references/prometheus-grafana.md"
IF task involves Grafana provisioning or dashboard backup
  REFERENCE "references/prometheus-grafana.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Identify signal owners, scrape targets, backend, retention/cost constraints, and existing Cloud Monitoring integration.
2. Keep labels bounded, bind admin/exporter endpoints to private interfaces, and source credentials from protected files or a secret store.
3. Validate changes with `promtool check config`, `promtool check rules`, and `amtool check-config` before rollout; verify series and routing end-to-end.
4. Use `scripts/prom-health-check.sh` for a read-only health summary. Use `scripts/grafana-backup.sh` to export metadata into a new private directory; treat its output as sensitive and verify completeness before relying on it.

## Safety

- Reference pins checked 2026-10-28: Prometheus `3.15.0` (LTS line `3.13.4`), Alertmanager `0.34.1`, Grafana `13.2.4`.
- Use HTTPS for remote authenticated endpoints; HTTP is for loopback only. Never enable anonymous Grafana admin or expose exporter ports publicly.
- Do not include user IDs, request IDs, credentials, or unbounded identifiers as metric labels.

## Tool defaults

- On GCP, prefer Managed Service for Prometheus/Cloud Monitoring when it meets retention, query, and export needs; add self-hosted Prometheus only for a concrete requirement.
- Use a 30-second scrape interval and 30-day retention as configurable starting points, not policy. Prefer the installed Grafana instance for dashboards.
- `assets/config.example.toml` shows optional preferences; it contains no project identifiers or endpoints.

## Related skills

- Tracing: `infra-otel-tracing-manage`
- SLO definitions and dashboards: `infra-sre-dashboard-create`
- Paging policy and runbooks: `infra-ops-alerting-manage`
- Database operations: database-specific sibling skills
- Project-specific SIP/Kamailio examples: load the matching project reference, not this global skill

## Scripts and assets

- `scripts/prom-health-check.sh`: read-only target, readiness, and firing-alert summary.
- `scripts/grafana-backup.sh`: exports folders, dashboards, and data-source metadata; credentials stay in `GRAFANA_TOKEN`.
- `assets/prometheus.yml` and `assets/alert-rules.yml`: generic GCE, host, and HTTP SLO templates; `assets/config.example.toml` contains optional defaults.

## References

- [Prometheus, Alertmanager, and Grafana](references/prometheus-grafana.md)
