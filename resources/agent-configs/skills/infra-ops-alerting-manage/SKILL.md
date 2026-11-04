---
name: infra-ops-alerting-manage
description: "Design and operate alert policies, paging severity, routing, escalation, on-call practices, dead-man switches, and incident runbooks. Use when tasks mention Alertmanager, paging, notification channels, PagerDuty, Opsgenie, Grafana OnCall, on-call rotation, alert fatigue, or alert runbooks."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/alerting-oncall
  license: MIT
---

# Operations alerting manage

Make alerts actionable and route them to a named owner with an appropriate response time. Separate user-impact paging from capacity and diagnostic tickets.

## Triggers

- Severity models, routes, inhibition, silence, or notification channels
- On-call rotations, escalation policies, or alert-fatigue reviews
- Dead-man switches, paging tests, or operational runbooks

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or service README if present
IF task involves selecting a notification provider or routing defaults
  IF file "~/.junie/custom/configs/infrastructure/alerting.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/alerting.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves paging, alert routing, on-call policies, or a runbook
  REFERENCE "references/alerting-oncall.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Name the service owner, symptom, expected action, severity, and response time for every proposed alert.
2. Route pages for immediate user impact; send slow degradation and capacity trends to ticket/chat paths.
3. Add grouping, inhibition, maintenance silences with expiry, escalation, and a tested dead-man signal.
4. Validate routes and perform an end-to-end test; review actionability, page volume, and MTTA/MTTR after use.

## Tool defaults

- Reuse the alert provider already operated by the service. If none exists, ask the owner to select Cloud Monitoring, Alertmanager, or an approved paging vendor; never invent a recipient or schedule.
- Page only for immediate user impact; keep tickets/diagnostics on non-paging channels. Require a runbook for every page.
- `assets/config.example.toml` contains preferences only, never notification URLs or keys.

## Safety

- Keep webhook URLs, PagerDuty keys, and provider tokens in Secret Manager or protected secret files, never in configs or output.
- Do not automate destructive remediation or production restarts from an alert without explicit approval and safeguards.
- Every paging alert needs a current runbook and a clear human action.

## Related skills

- Metrics and Alertmanager configuration: `infra-prometheus-metrics-manage`
- SLI/SLO and burn-rate definitions: `infra-sre-dashboard-create`
- Incident response: `sec-ops-incident-respond`
- Project-specific SIP response steps: use project-level references, if installed

## References

- [Alerting and on-call](references/alerting-oncall.md)
