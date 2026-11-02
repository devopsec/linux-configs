---
name: sec-gcp-auditLogs-manage
description: "Configure, route, retain, and query Google Cloud Audit Logs, including Admin Activity, Data Access, System Event, and Policy Denied logs. Use when a task mentions GCP auditConfigs, Data Access logging, Cloud Logging sinks, audit log buckets, BigQuery exports, or investigating GCP control-plane activity."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/auditing/gcp-audit-logs
    - compliance/auditing/audit-logging
  license: MIT
---

# GCP audit logs management

Enable the required Cloud Audit Logs, route them to controlled destinations, and verify retention and queryability without granting broad logging or destination access.

## Triggers

- GCP Cloud Audit Logs, `auditConfigs`, Admin Activity, Data Access, Policy Denied
- Cloud Logging sinks, log buckets, BigQuery audit export, audit log query

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves log types, Data Access enablement, exemptions, or gcloud logging read
  REFERENCE "references/cloud-audit-logs.md"
IF task involves routing, BigQuery analysis, Cloud Storage archive, Pub/Sub, buckets, or retention
  REFERENCE "references/routing-and-retention.md"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Define scope, data residency, sensitive services, required log classes, and retention obligations with the security/compliance owner.
2. Keep `auditConfigs` in infrastructure as code; enable Data Access narrowly and estimate ingestion cost before broad rollout.
3. Route using a least-privilege sink writer identity to a dedicated dataset or archive; isolate audit data from application data.
4. Treat retention locks as irreversible: test on a disposable destination and obtain explicit approval before locking.
5. Generate a harmless test event, confirm Logs Explorer and the destination receive it, and document access controls and retention evidence.

## Safety

- `set-iam-policy` replaces the full policy; use a fresh policy/etag and prefer dedicated audit-config resources in infrastructure as code.
- Do not write credentials, authentication material, or unnecessary personal data into audit events.
- Restrict logging administration and alert on changes to sinks, exclusions, buckets, and audit configuration.

## Related skills

- GCP log-based metrics and alert policies → `sec-gcp-logAlerting-manage`
- Linux auditd and journal trails → `sec-linux-auditTrail-manage`
- Infrastructure-as-code operations → `infra-opentofu-any-manage` / `infra-terraform-any-manage`
