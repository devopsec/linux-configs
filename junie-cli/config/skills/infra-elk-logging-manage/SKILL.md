---
name: infra-elk-logging-manage
description: "Operate Elastic Stack log pipelines with Elasticsearch, Kibana, Filebeat/Elastic Agent, Logstash, data streams, ILM, and query/alert workflows. Use when tasks mention Elasticsearch, Logstash, Kibana, Beats, Filebeat, Elastic Agent, ES|QL, index lifecycle, or Elastic log ingestion."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/elk-stack
  license: MIT
---

# Elastic logging manage

Build and operate an Elastic-based log pipeline when full-text search, Kibana analytics, or an existing Elastic estate justifies its operational cost.

## Triggers

- Elasticsearch/Kibana or Logstash deployment and security
- Filebeat/Elastic Agent inputs, ingest pipelines, or data streams
- ILM, Query DSL/ES|QL, or Elastic log alerts

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or service README if present
IF task involves choosing Elastic versus another log backend
  IF file "~/.junie/custom/configs/infrastructure/elk-logging.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/elk-logging.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves Elasticsearch, Kibana, Beats, Logstash, ILM, or Elastic log queries
  REFERENCE "references/elk-stack.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Confirm Elastic is needed versus Cloud Logging or Loki; inventory versions, deployment topology, log sources, and retention requirements.
2. Secure transport and authentication first; create scoped writer/reader identities and keep secrets in the product keystore or protected secret store.
3. Normalize structured fields, scrub sensitive data before indexing, and use data streams plus lifecycle policy for retention.
4. Validate ingestion, mappings, access, alert routing, and retention behavior; estimate disk and shard impact before rollout.

## Tool defaults

- Choose Elastic when full-text search, Kibana analytics, or an existing Elastic estate justifies its operating cost. For basic GCP VM log collection, prefer Cloud Logging; for a Grafana-centric stack, prefer Loki.
- Reuse the existing pipeline and retention policy; ask the owner if retention or destination is unspecified.
- `assets/config.example.toml` contains preferences only; never put credentials or site endpoints in it.

## Safety

- Reference pin: Elastic Stack `9.5.5` (checked 2026-10-28); upgrade an 8.x deployment only along the documented supported path.
- Never disable security outside an isolated throwaway environment or use the `elastic` superuser for application writers.
- Avoid storing raw secrets, tokens, phone numbers, or user identifiers in searchable fields.

## Related skills

- Prometheus metrics and dashboards: `infra-prometheus-metrics-manage`
- Loki logging: `infra-loki-logging-manage`
- Trace correlation: `infra-otel-tracing-manage`
- Alert policy and on-call: `infra-ops-alerting-manage`

## References

- [Elastic Stack](references/elk-stack.md)
