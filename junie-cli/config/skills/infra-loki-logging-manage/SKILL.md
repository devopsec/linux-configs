---
name: infra-loki-logging-manage
description: "Operate Grafana Loki log storage and Grafana Alloy collection: TSDB schema, object storage, retention, LogQL, labels, pipelines, and migration from Promtail. Use when tasks mention Loki, LogQL, Grafana Alloy, Promtail migration, log streams, Loki retention, or Loki alert rules."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/loki-logging
  license: MIT
---

# Loki logging manage

Operate Loki with Grafana Alloy for log collection, indexing, retention, and query workflows. Keep stream labels low-cardinality and scrub sensitive data before remote storage.

## Triggers

- Loki deployment, object storage, tenant/auth configuration, or retention
- Alloy collection pipelines and Promtail migration
- LogQL, Loki ruler alerts, or Grafana Loki data sources

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or service README if present
IF task involves selecting Loki storage, tenancy, or retention defaults
  IF file "~/.junie/custom/configs/infrastructure/loki-logging.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/loki-logging.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves Loki, LogQL, Alloy, or Promtail migration
  REFERENCE "references/loki-logging.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Identify single/multi-tenant design, storage backend, expected ingestion rate, retention, and existing collector topology.
2. Use TSDB schema and object storage for persistent deployments; bind interfaces privately and configure auth at an appropriate gateway.
3. Collect from journald/files through Alloy; scrub secrets and PII before shipping and keep labels bounded.
4. Validate configuration, query performance, retention deletion behavior, and end-to-end log access.

## Tool defaults

- On GCP, prefer GCS object storage for persistent Loki. Use local single-binary storage only for a small private deployment or development.
- Keep multi-tenant auth enabled where required; disable Loki tenant auth only for a single-tenant service behind a private network or authenticated gateway. Retention is always a service/compliance input.
- `assets/config.example.toml` shows preferences only; bucket names and retention policy come from runtime configuration.

## Safety

- Reference pins checked 2026-10-28: Loki `3.7.9`, Grafana Alloy `1.21.2`; Promtail is removed from Loki `3.7.3` onward.
- Use least-privilege object-storage identity and restrict it to the intended bucket.
- Do not expose Grafana with anonymous administrator access; disable Loki tenant auth only for one tenant behind a private network or authenticated gateway. Never publish raw identifiers as labels.

## Related skills

- Elastic logging alternative: `infra-elk-logging-manage`
- Metrics and dashboards: `infra-prometheus-metrics-manage`
- Trace export and correlation: `infra-otel-tracing-manage`
- Alerting and incident runbooks: `infra-ops-alerting-manage`

## References

- [Loki and Alloy](references/loki-logging.md)
