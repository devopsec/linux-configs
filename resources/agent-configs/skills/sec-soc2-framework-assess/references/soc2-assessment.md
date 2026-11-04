# SOC 2 evidence map

Baseline checked 2026-10-28: AICPA 2017 Trust Services Criteria with revised points of focus (2022). The service organization selects applicable criteria; the independent CPA determines examination procedures and report sufficiency.

| Criteria | Evidence examples | Test focus |
|---|---|---|
| CC1–CC5 — control environment, communication, risk, monitoring, control activities | Approved policies, roles/training, risk and exception registers, review minutes, metrics | Verify approval, review cadence, owners, and follow-through on identified risks. |
| CC6 — logical access and system protection | Identity/group/role exports, MFA/SSO configuration, service identity records, data-store grants, source/build permissions, access reviews | Sample joiners, movers, leavers, privileged access, service identities, and revocations; compare effective permissions with approvals. |
| CC7 — operations and incidents | Audit logs, alerts, patch/vulnerability records, incident tickets, timelines, and postmortems | Trace alert through triage, decision, remediation, escalation, and retest. |
| CC8 — change management | Change requests, repository approvals, build/test/scan results, artifact provenance, deployment approvals, and database migration records | Sample production changes end to end; check emergency changes receive retrospective review. |
| CC9 — risk mitigation and third parties | Vendor inventory, reviews, contracts/attestations, service dependencies, and exceptions | Match provider evidence to the precise service, region, and inherited control claimed. |
| Availability, processing integrity, confidentiality, or privacy (when selected) | Objectives, operational metrics, backup/restore tests, validation results, privacy/retention tests | Tie evidence to a selected criterion and objective; do not infer criteria applicability. |

## Sampling and reporting

For Type II, the sample must cover the defined examination period and demonstrate sustained operation; a point-in-time configuration screenshot alone is insufficient. For each sample retain the criterion, population and period, selection method, source, dated evidence reference, reviewer, result, and exception. Keep raw exports restricted and redact identifiers in assessment summaries.

Separate system-generated evidence, policies, owner attestations, and provider-inherited controls. Do not claim that a readiness assessment is an independent SOC 2 report.

Official source: [AICPA 2017 Trust Services Criteria with revised points of focus — 2022](https://www.aicpa-cima.com/resources/download/2017-trust-services-criteria-with-revised-points-of-focus-2022).