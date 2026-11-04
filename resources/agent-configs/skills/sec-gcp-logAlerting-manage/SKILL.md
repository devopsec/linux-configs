---
name: sec-gcp-logAlerting-manage
description: "Create and test Google Cloud Logging log-based metrics, alert policies, and notification routing for security and audit events. Use when a task mentions Cloud Logging alerts, log-based metrics, Cloud Monitoring policies, IAM-change detection, audit-pipeline tampering, or GCP security alert delivery."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/auditing/audit-logging
  license: MIT
---

# GCP log alerting management

Turn relevant GCP audit events into actionable, testable signals; avoid paging on an unbaselined or unverified filter.

## Triggers

- Cloud Logging log-based alert, metric, Cloud Monitoring policy, notification channel
- IAM, service-account key, firewall, audit-config, sink, or log-bucket change detection

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves GCP audit-event detection, event alerts, metric thresholds, or alert testing
  REFERENCE "references/log-detection-alerts.md"
IF task needs the underlying Cloud Audit Logs types or routing configuration
  REFERENCE skill "sec-gcp-auditLogs-manage"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. State the threat, expected event fields, scope, and response owner for each detection.
2. Test the Logging filter against representative events; confirm the destination project and log bucket where the policy evaluates.
3. Use event alerts for discrete high-value actions and metrics/thresholds for rates; baseline before setting paging thresholds.
4. Define notification channels with credentials stored outside policy files and document deduplication, rate limits, and auto-close behavior.
5. Trigger a safe test event, verify the incident and every notification path, then record results and tune noise.

## Safety

- Protect webhook credentials; never embed them in HCL, JSON, or skill output.
- Alert on changes to the alerting pipeline itself and on missing log ingestion.
- Do not silently suppress an alert because of volume; use a reviewed, narrow exclusion.

## Related skills

- Cloud Audit Logs enablement and routing → `sec-gcp-auditLogs-manage`
- Host audit trails → `sec-linux-auditTrail-manage`
- Incident triage and communications → `sec-ops-incident-respond`
