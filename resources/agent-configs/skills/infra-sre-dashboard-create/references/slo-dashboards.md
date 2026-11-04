# SLOs & dashboards

## Define SLIs (good events / valid events)

| Service type | SLI | Example source |
|---|---|---|
| HTTP API (Python) | availability: non-5xx / all; latency: requests < 300ms / all | OTel `http.server.request.duration` histogram |
| Batch / pipeline (Pub/Sub, BigQuery loads) | freshness: runs finished within N min of schedule; correctness: rows validated | textfile metric / Cloud Monitoring custom metric |
| Database | not a user SLI — use as saturation signal under service SLOs | |

SLO = target over a window, e.g. 99.9% over 30 days → error budget 0.1% (≈ 43 min of full outage).

## Recording rules (Prometheus)

```yaml
groups:
  - name: slo-api
    rules:
      - record: slo:sli_error:ratio_rate5m
        expr: |
          sum(rate(http_server_request_duration_seconds_count{job="api",http_response_status_code=~"5.."}[5m]))
          / sum(rate(http_server_request_duration_seconds_count{job="api"}[5m]))
      # repeat for 30m, 1h, 2h, 6h, 1d, 3d windows (or use sloth / pyrra to generate)
```

Generators: **Sloth** or **Pyrra** produce full recording + multi-window alert sets from a short SLO spec — prefer them over hand-written rules. Cloud Monitoring has native SLO objects + burn-rate alert policies (manage via OpenTofu `google_monitoring_slo`).

## Multi-window, multi-burn-rate alerts (SLO 99.9%)

| Severity | Long window | Short window | Burn rate | Budget spent at trigger |
|---|---|---|---|---|
| page | 1h | 5m | 14.4 | 2% |
| page | 6h | 30m | 6 | 5% |
| ticket | 3d | 6h | 1 | 10% |

Alert fires when **both** windows exceed `burn_rate × (1 − SLO)`. Template in `assets/alert-rules.yml`.

## Dashboard layers

1. **Overview** (one per platform): SLO attainment + budget remaining per service, active alerts, deploy annotations.
2. **Service** (RED + USE): rate, errors, duration p50/p95/p99; saturation (CPU, memory, connections, DB pool); dependencies (DB latency, queue backlog).
3. **Deep dive**: per-route/per-method breakdowns, exemplars → traces (Cloud Trace / Tempo), logs panel (Cloud Logging / Loki) filtered by `trace_id`.

Panel rules: units on every axis; percentiles from aggregated buckets; default ranges 1h/6h/24h; ≤ 12–15 panels per dashboard; panel description links the runbook; colors: green ok / amber degrading / red breach; deploy markers from CI (Cloud Build step posting a Grafana annotation or Cloud Monitoring event).

## Review cadence

Weekly: budget burn, top alerting rules, noisy/never-actioned alerts → tune or delete. Monthly: SLO target still matches user expectation?
