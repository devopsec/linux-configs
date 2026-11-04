# LLM and agent telemetry

OpenTelemetry GenAI semantic conventions are still development-stage (checked 2026-10-28; no stable convention release to pin). Treat `gen_ai.*` names as a replaceable instrumentation contract and test backend compatibility during upgrades.

## Signals and labels

Collect end-to-end agent latency, model-call latency/TTFT, prompt/completion/cached tokens, estimated cost, retries/errors, tool outcomes, and retrieval latency/score. Keep labels bounded: model alias, provider, status, and coarse error class. Do not label raw user/tenant IDs, prompt text, exception messages, or document content.

| Signal | Suggested metric |
|---|---|
| Agent turn duration | `agent_request_duration_seconds` histogram |
| Model latency | `llm_call_duration_seconds` histogram by model/provider/status |
| Token usage | `llm_prompt_tokens_total`, `llm_completion_tokens_total` counters |
| Cost estimate | `llm_cost_dollars_total` by model and bounded service/team class |
| Errors/retries | `llm_errors_total`, `llm_retries_total` with allowlisted error types |
| In-flight work | `agent_active_requests` gauge |

Use a private OTLP collector path. Local plaintext may be acceptable only on loopback; remote OTLP must use TLS and authenticated transport. Propagate trace context across gateway, model, retrieval, and tool calls. Record model alias, operation, token counts, status, and timing; prompt/response content stays off by default.

On GCP, route the OpenTelemetry Collector to Cloud Trace and Managed Prometheus; emit structured JSON to stdout for Cloud Logging. Include service name/version/environment and Cloud trace correlation fields, with project and region supplied at runtime from approved config.

## SLOs and spend alerts

Define availability and p95 latency objectives with multi-window burn-rate alerts. Set warning and hard-budget thresholds from approved budgets rather than embedding one team's site-specific spend values in shared config. Alert on unknown model pricing; never silently turn missing cost data into zero.

```promql
histogram_quantile(0.95, sum by (le) (rate(agent_request_duration_seconds_bucket[5m])))
sum by (model) (rate(llm_prompt_tokens_total[5m]))
sum by (error_type) (rate(llm_errors_total[5m]))
```

## Structured logs and redaction

Emit structured JSON to stdout with timestamp, severity, service, request ID, bounded model alias, status, duration, token counts, and trace ID. Remove authorization headers and redact before setting span attributes, formatting logs, or exporting content. Regex redaction is only a backstop; regulated workloads should disable content capture and apply approved DLP controls.

Optional Langfuse or Helicone backends add a third party to the data path. Use the current OTLP integration surface rather than copying an unpinned SDK decorator example; complete data-processing, residency, retention, and access review first. Keep credentials in Secret Manager/environment injection.

## Validation and troubleshooting

Test a successful request, timeout, provider error, tool failure, and retrieval path; confirm no prompt, secret, or raw identifier reaches logs/traces. Check label cardinality and collector export errors. For latency, inspect the slowest trace span; for token/cost spikes, check repeated retries, history growth, oversized retrieval context, and cache behavior. Keep SLO and cost dashboards resilient to GenAI attribute renames.