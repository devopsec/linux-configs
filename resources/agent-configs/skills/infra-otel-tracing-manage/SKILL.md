---
name: infra-otel-tracing-manage
description: "Instrument Python services and operate OpenTelemetry collectors that export traces to Google Cloud Trace; includes OTLP, SDK setup, auto-instrumentation, sampling, redaction, and systemd wiring. Use when tasks mention OpenTelemetry, OTel, OTLP, spans, trace context, Cloud Trace, otelcol-contrib, or Python instrumentation."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/opentelemetry
  license: MIT
---

# OpenTelemetry tracing manage

Instrument Python services and route telemetry through a local OpenTelemetry Collector or Google Cloud Ops Agent to Cloud Trace. Keep credentials and high-cardinality or sensitive attributes out of telemetry.

## Triggers

- Python auto/manual instrumentation, tracing, and W3C trace propagation
- OTLP endpoints, Collector pipelines, Cloud Trace export, or Ops Agent config
- Sampling, trace context correlation, redaction, or collector validation

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or service README if present
IF task involves selecting instrumentation, collector, destination, or sampling defaults
  IF file "~/.junie/custom/configs/infrastructure/otel.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/otel.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves Python instrumentation, sampling, propagation, or SDK behavior
  REFERENCE "references/opentelemetry-gcp.md"
IF task involves an OpenTelemetry Collector or Cloud Ops Agent pipeline
  REFERENCE "references/opentelemetry-gcp.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Inventory service runtime, hosting, existing telemetry agents, authentication path, and destination project.
2. Choose one instrumentation path per library (manual or automatic); configure service identity and endpoints through protected environment settings.
3. Bound sampling and attributes, redact secrets/PII before export, and assign least-privilege telemetry-writer roles.
4. Validate collector configuration, propagate trace context across service boundaries, and verify traces in the destination before deployment.

## Safety

- Pin Collector `0.163.2` (checked 2026-10-28) only as a reference version; validate compatibility before upgrades.
- Use local loopback for local OTLP endpoints; require TLS and authentication for cross-host export.
- Do not record credentials, raw URLs with secrets, user identifiers, or other sensitive values in spans.

## Tool defaults

- Prefer the already-installed Cloud Ops Agent for a simple single-backend GCP VM deployment; use Collector `0.163.2` when processors, multiple destinations, or explicit local control are needed.
- Use local OTLP and Cloud Trace as the default path on GCP. Start head sampling at 10% only as a configurable baseline; the service owner sets the production rate and tail-sampling policy.
- `assets/config.example.toml` shows optional preferences; it contains no credentials or site values.

## Related skills

- Metrics/exporters: `infra-prometheus-metrics-manage`
- SLO dashboards: `infra-sre-dashboard-create`
- GCP VM resources and service-account IAM: `infra-gcp-compute-manage`
- Logs and trace correlation: `infra-loki-logging-manage` / `infra-elk-logging-manage`

## References

- [OpenTelemetry for Python and Google Cloud](references/opentelemetry-gcp.md)
