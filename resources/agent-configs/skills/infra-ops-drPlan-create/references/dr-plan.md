# Disaster recovery plan reference

## Define recovery objectives

- **RTO** is the approved time from incident declaration to an acceptable service state.
- **RPO** is the approved maximum data-loss interval measured against the last recoverable point.
- Derive targets from business impact, legal/contract requirements, data dependencies, and tested capability; never choose them solely from a technical default.

## Recovery patterns

| Pattern | Typical trade-off | Validate |
|---|---|---|
| Restore from backup | Lower standing cost; longer recovery | Backup freshness, restore duration, keys, rebuild dependencies |
| Pilot light | Some critical components remain ready | Promotion steps, capacity, credentials, replication lag |
| Warm standby | Faster service recovery; higher operating cost | Data consistency, routing, service health, failback path |
| Active-active | Fast regional continuity; high complexity | Conflict handling, consistency, shared dependencies, tested failover |

These patterns do not prescribe site targets. The service owner must choose based on approved business analysis.

## GCP example considerations

- Cloud SQL regional high availability covers a zone failure; it does not by itself protect against a region outage or logical corruption. Keep independent backups/PITR and test the actual restore path.
- A cross-region Cloud SQL replica can reduce recovery time, but promotion is a state-changing operation; confirm current behavior and rehearse failback before relying on it.
- Cloud DNS health-checked/failover routing or a controlled record change can redirect service traffic. Test resolver/client caching and the complete service path rather than assuming a DNS TTL is the measured recovery time.
- Replicate or make recoverable the service identities, encryption keys, certificates, configuration, images/artifacts, and IaC state needed to rebuild. Missing access or keys can invalidate otherwise usable backups.
- BigQuery replication, Pub/Sub replay, GCS retention, and VM snapshots have service-specific limitations; load their current references and do not count them as a complete application DR plan.

## Minimum plan contents

1. Scope, owner, activation authority, incident roles, contacts, assumptions, and exclusions.
2. Prioritized services and dependencies: identity, network, compute, data, keys, artifacts, vendors, people, and external integrations.
3. Approved recovery objectives, runbook links, data consistency criteria, required access, and recovery locations.
4. Activation criteria, communications, step-by-step restore/failover, validation, rollback/failback, and safe temporary-resource cleanup.
5. Recovery test schedule, expected outputs, evidence location, escalation, and action tracking.

## Exercise and evidence

Use tabletop exercises for decision and communication paths, component tests for recovery procedures, and end-to-end tests for the full service path. Run only in an approved environment and window. Record declaration time, key milestones, last recoverable point, validation results, actual RTO/RPO, problems, owners, and retest status.

Test failure and failback separately where promotion, DNS changes, or replication reconfiguration can be one-way or disruptive. Do not equate a provider availability zone or backup feature with a tested workload recovery plan.

## Evidence checklist

- Every in-scope data store has business-owner-approved RPO/RTO and retention.
- Backups are encrypted, isolated from the primary failure boundary, and written by least-privilege identities; deletion authority is separate where feasible.
- Monitoring alerts on job failure and stale recovery points, not just service status.
- Restore tests record actual recovery time, data point, integrity checks, scope, and remediation actions.
- The DR plan has named decision roles/contacts, current procedures, tested failback, and an owner-approved review cadence.
- Where applicable, continuity evidence may map to SOC 2 Availability, ISO/IEC 27001 continuity/backup controls, and HIPAA contingency planning; confirm exact criteria in the assessment.