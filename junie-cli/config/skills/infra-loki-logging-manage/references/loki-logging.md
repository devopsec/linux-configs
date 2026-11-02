# Grafana Loki + Alloy

## Versions & migration notes

- Reference pins checked 2026-10-28 against [Loki releases](https://github.com/grafana/loki/releases) and [Alloy releases](https://github.com/grafana/alloy/releases): Loki **3.7.9** and Grafana Alloy **1.21.2**. **Promtail is removed** as of Loki 3.7.3 (deprecated since 3.0) — migrate with `alloy convert --source-format=promtail --output=config.alloy promtail.yaml`.
- Index: **TSDB + schema v13** (boltdb-shipper/v11 from upstream examples is deprecated). `table_manager` retention is gone → compactor retention.
- Install from Grafana's signed rpm/apt repo (`rpm.grafana.com`/`apt.grafana.com`); run as systemd services; bind to private IPs.

## Single-binary Loki on a VM with GCS storage

```yaml
# /etc/loki/config.yaml
auth_enabled: false            # single tenant behind private network; enable + gateway auth if multi-tenant/exposed
server:
  http_listen_address: <private-ip>
  http_listen_port: 3100
common:
  path_prefix: /var/lib/loki
  replication_factor: 1
  ring: { kvstore: { store: inmemory } }
  storage:
    gcs: { bucket_name: <loki-chunks-bucket> }     # VM SA needs roles/storage.objectAdmin on this bucket only
schema_config:
  configs:
    - from: 2026-01-01
      store: tsdb
      object_store: gcs
      schema: v13
      index: { prefix: index_, period: 24h }
compactor:
  working_directory: /var/lib/loki/compactor
  retention_enabled: true
  delete_request_store: gcs
limits_config:
  retention_period: 720h
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  allow_structured_metadata: true
  ingestion_rate_mb: 8
  per_stream_rate_limit: 5MB
ruler:
  storage: { type: local, local: { directory: /etc/loki/rules } }
  alertmanager_url: http://<alertmanager-host>:9093
```

Validate: `loki -config.file=/etc/loki/config.yaml -verify-config`.

## Alloy on each VM (journald + files → Loki)

```alloy
// /etc/alloy/config.alloy
loki.relabel "journal" {
  forward_to = []
  rule {
    source_labels = ["__journal__systemd_unit"]
    target_label  = "unit"
  }
}

loki.source.journal "units" {
  forward_to    = [loki.process.scrub.receiver]
  relabel_rules = loki.relabel.journal.rules
  labels        = { job = "journal", host = constants.hostname }
}

local.file_match "application" {
  path_targets = [{ __path__ = "/var/log/<service>/*.log", job = "application", host = constants.hostname }]
}

loki.source.file "application" {
  targets    = local.file_match.application.targets
  forward_to = [loki.process.scrub.receiver]
}

loki.process "scrub" {
  stage.replace {
    expression = "(?i)(token|password|api[_-]?key)=\\S+"
    replace    = "$1=REDACTED"
  }
  stage.drop {
    expression = "(?i)\\bdebug\\b"
  }
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://<loki-host>:3100/loki/api/v1/push"
  }
}
```

Alloy UI/debug on `127.0.0.1:12345`; `alloy fmt` to lint. Alloy can also replace node_exporter (`prometheus.exporter.unix`) and act as OTel collector (`otelcol.*` components) — one agent per VM.

## Label discipline

- Labels = low-cardinality stream selectors: `job`, `host`, `unit`, `env`, `level` (bounded). **Never** user_id, Call-ID, phone number, request ID as labels (upstream did `user_id` — cardinality explosion). Put those in the line or **structured metadata**.
- Target < ~100k active streams per tenant; check `loki_ingester_memory_streams`.

## LogQL

```logql
{job="application", host="<host>"} |= "ERROR"
{unit="<service>.service"} | json | level="error" | line_format "{{.msg}}"
sum by (host) (rate({job="application"} |~ "(?i)timeout" [5m]))
sum by (unit) (count_over_time({job="journal"} | json | level="error" [5m]))
quantile_over_time(0.95, {job="api"} | json | unwrap duration_ms [5m]) by (route)
{job="api"} | json | trace_id="<id>"                  # jump from a trace
```

Filter by labels first, then line filters (`|=`, `|~`) before parsers (`json`, `logfmt`).

## Alerting via ruler

```yaml
# /etc/loki/rules/fake/application.yaml   ("fake" = tenant dir when auth_enabled=false)
groups:
  - name: application-logs
    rules:
      - alert: ApplicationErrors
        expr: sum by (host) (count_over_time({job="application"} |= "ERROR" [5m])) > 0
        for: 2m
        labels: { severity: page, service: application }
        annotations:
          summary: "Application errors on {{ $labels.host }}"
          runbook_url: "<runbook link>"
```

## Grafana datasource

```yaml
apiVersion: 1
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://<loki-host>:3100
    jsonData:
      maxLines: 1000
      derivedFields:
        - name: trace_id
          matcherRegex: '"trace_id":"(\w+)"'
          url: '$${__value.raw}'
          datasourceUid: <traces-datasource-uid>
```

Upstream's `GF_AUTH_ANONYMOUS_ORG_ROLE=Admin` dropped — never enable anonymous admin.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| `429 rate limited` | `ingestion_rate_mb`, per-stream limit | raise limits or split streams |
| `too many outstanding requests` / slow queries | query range, label selectors | narrower selectors, shorter range, add `query_range` cache |
| logs missing from host | `alloy` UI component health, positions | fix path/permissions (Alloy user in `adm`/`systemd-journal` group) |
| `entry too far behind` | old logs replayed | `reject_old_samples_max_age` or skip backlog |
| high memory | stream cardinality | drop high-cardinality labels |
