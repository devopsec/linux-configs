---
name: sec-linux-auditTrail-manage
description: "Configure and investigate Linux audit trails using auditd, journald, rsyslog, and structured application events. Use when a task mentions Linux audit logging, ausearch, journal persistence, remote syslog forwarding, host authentication events, or audit-log integrity."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/auditing/audit-logging
  license: MIT
---

# Linux audit trail management

Collect, retain, forward, and query host audit events while protecting evidence from local tampering and minimizing sensitive fields.

## Triggers

- Linux auditd, ausearch, aureport, journald, rsyslog, auth logs
- Host audit retention, remote forwarding, integrity, or structured application events

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves auditd, journald, rsyslog, host authentication, or app audit events
  REFERENCE "references/linux-audit-trails.md"
IF rules are being added or changed on a hardened host
  REFERENCE skill "sec-linux-host-harden"
IF logs are shipped into Cloud Logging
  REFERENCE skill "sec-gcp-auditLogs-manage"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Define events, host scope, retention, privacy limits, and a remote destination separate from the monitored host.
2. Configure the narrowest audit rules and persistent journal settings that satisfy the detection need; validate syntax before reload.
3. Forward logs over authenticated transport with buffering and bounded disk use; monitor shipper health and dropped events.
4. Query a known test event locally and remotely, verify timestamps and stable fields, and confirm access restrictions.
5. Review retention and tamper controls periodically; preserve incident evidence before changing a suspect host.

## Safety

- Avoid recording credentials, authentication values, or unnecessary personal data in application audit events.
- Local logs are not tamper-proof on a compromised host; ship evidence promptly to a restricted remote destination.
- Do not alter or delete evidence during incident response without the incident commander’s approval.

## Related skills

- GCP Cloud Audit Logs → `sec-gcp-auditLogs-manage`
- GCP log-based alerting → `sec-gcp-logAlerting-manage`
- Linux host hardening → `sec-linux-host-harden`
- Incident evidence collection → `sec-ops-forensics-collect`
