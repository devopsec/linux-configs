---
name: infra-ops-drPlan-create
description: "Create or improve a disaster recovery plan with approved recovery objectives, dependency maps, failover/failback procedures, communication roles, and tested evidence. Use when asked for a DR plan, business recovery strategy, RPO/RTO, failover, failback, recovery runbook, or disaster recovery exercise."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/continuity/disaster-recovery
  license: MIT
---

# Disaster recovery plan

Create an owner-approved plan for restoring prioritized services after a disruption. A plan is not proof of recoverability until the procedures have been exercised and results recorded.

## Triggers

- Requests for a disaster recovery plan, recovery runbook, RPO/RTO targets, failover/failback, or DR testing.
- Significant changes to hosting, dependencies, regions, data stores, identity, or recovery capability.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/dr-plan.md"
CACHE only the approved scope, dependencies, objectives, and exercise steps
```

## Workflow

1. Set the service boundary, business owner, incident authority, stakeholders, and assumptions; ask owners for site-specific targets and contact details.
2. Classify critical services and dependencies, including identity, networking, data, keys, software artifacts, vendors, and people.
3. Obtain approved RPO/RTO values and select a recovery pattern proportionate to business impact, data consistency, and cost.
4. Document activation criteria, decision rights, communication, recovery sequence, validation, rollback/failback, and safe decommissioning.
5. Exercise components and full scenarios in isolated or approved targets; record timestamps, data checks, measured RPO/RTO, issues, and owners.
6. Track remediation to closure and review the plan after changes and on the organization-approved cadence.

## Guardrails

- Do not invent targets, contact lists, network ranges, locations, or failover destinations; ask owners or read approved configuration.
- Failover, replica promotion, DNS changes, and failback can be disruptive or one-way. Require incident authority and an approved change plan.
- Distinguish provider availability claims from workload recovery evidence; verify the complete service and data path.

## Related skills

- PostgreSQL, SQLite, BigQuery, and Linux file recovery → `infra-postgresql-backup-manage`, `infra-sqlite-backup-manage`, `infra-bigquery-backup-manage`, `infra-linux-fileBackup-manage`
- Writing the recovery runbook → `docs-ops-runbook-create`
- Incident command and evidence preservation → `sec-ops-incident-respond`
- Compliance continuity evidence → `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, or `sec-hipaa-framework-assess`
