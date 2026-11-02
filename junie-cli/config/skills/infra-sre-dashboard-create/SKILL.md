---
name: infra-sre-dashboard-create
description: "Define service-level indicators/objectives and create operational dashboards with error-budget and multi-window burn-rate views. Use when tasks mention SLI, SLO, error budget, burn rate, RED/USE dashboards, latency percentiles, or service health dashboards."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/sre-dashboards
  license: MIT
---

# SRE dashboard create

Create dashboards that answer user-impact and service-health questions, grounded in explicit SLIs and SLOs rather than infrastructure metrics alone.

## Triggers

- SLI/SLO selection, target windows, or error-budget policies
- Multi-window burn-rate alerts and recording rules
- Service overview, RED/USE, or diagnostic dashboards

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or service README if present
IF task involves selecting a dashboard backend or SLO rule generator
  IF file "~/.junie/custom/configs/infrastructure/slo-dashboard.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/slo-dashboard.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves SLI/SLO, error budgets, burn-rate alert thresholds, or dashboards
  REFERENCE "references/slo-dashboards.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Clarify user-visible reliability objectives, valid-event denominator, exclusions, and measurement source with service owners.
2. Define SLIs from stable counters/histograms; verify numerator and denominator semantics before choosing a target.
3. Design overview, service, and drill-down panels with units, links to traces/logs, and a runbook; keep cardinality and retention cost bounded.
4. Test recording/alert rules and dashboard queries against representative traffic, then document ownership and review cadence.

## Safety

- Do not turn infrastructure saturation into a user SLI; use it as a diagnostic or capacity signal.
- Avoid high-cardinality identifiers in series and dashboards; use normalized routes and bounded attributes.
- Make SLO thresholds, error-budget alerts, ownership, and review cadence explicit rather than treating examples as policy.

## Tool defaults

- Prefer the telemetry backend and dashboard system already in use; on GCP, Cloud Monitoring SLOs or the existing Prometheus/Grafana stack are the defaults.
- Use Sloth or Pyrra only when the service owner wants generated rules. Never infer an SLO target or valid-event denominator from an example.
- `assets/config.example.toml` shows optional preferences; objectives remain service-owner inputs.

## Related skills

- Metrics and dashboard implementation: `infra-prometheus-metrics-manage`
- Paging policy and runbooks: `infra-ops-alerting-manage`
- Trace instrumentation: `infra-otel-tracing-manage`
- Project-specific SIP SLOs: use the project-level reference, if installed

## References

- [SLOs and dashboards](references/slo-dashboards.md)
