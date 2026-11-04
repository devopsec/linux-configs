---
name: infra-llm-observability-manage
description: "Instrument and operate LLM/agent telemetry for latency, token usage, errors, cost, traces, SLOs, and privacy-preserving logs. Use when a request mentions GenAI OpenTelemetry, TTFT, token/cost metrics, Langfuse, LLM traces, prompt redaction, or LLM SLOs."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [devops/ai/agent-observability]
  license: MIT
---

# LLM observability

## Triggers

- Add metrics/traces for model, retrieval, tool, or agent calls.
- Diagnose latency, token/cost anomalies, error rates, SLOs, or unsafe telemetry capture.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/llm-observability.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/llm-observability.toml"
ELSE
  use the defaults below and in "references/llm-observability.md"
REFERENCE "references/llm-observability.md" for telemetry, SLOs, or redaction
CACHE only the loaded observability guidance
```

## Workflow

1. Define request-level latency, token/cost, error, tool, retrieval, and availability signals with bounded labels.
2. Emit OTLP traces and structured logs to the configured private backend; confirm trace context propagation.
3. Redact PII/secrets before telemetry leaves the process; disable content capture unless an approved need and retention exist.
4. Add spend alerts and multi-window SLO alerts; validate queries with known-good and error cases.
5. Test cardinality, backend access controls, and data-retention behavior.

## Defaults

- OTLP traces/logs to a private backend; remote export uses TLS and authenticated transport.
- Prometheus metrics, bounded labels, and no prompt/response content capture.

## Safety

- Never use prompts, response text, raw user identifiers, or secrets as metric labels.
- GenAI semantic conventions remain development-stage; keep dashboards tolerant of schema changes.
- A third-party observability service receives data; complete data-processing review first.

## Related skills

- Generic Prometheus, Grafana, and OTel infrastructure → `infra-observability-any-manage`
- Gateway cost budgets → `infra-llm-gateway-manage`
- RAG and model evaluation → `infra-rag-pipeline-manage`, `dev-agents-evals-create`

## Reference

- LLM metrics, traces, SLOs, and redaction: [references/llm-observability.md](references/llm-observability.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
