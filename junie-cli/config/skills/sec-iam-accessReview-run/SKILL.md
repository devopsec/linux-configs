---
name: sec-iam-accessReview-run
description: "Run a scoped, evidence-based review of human and non-human identities, effective permissions, exceptions, and remediation. Use when asked for an IAM access review, access certification, periodic entitlement review, service-account review, privileged access recertification, joiner/mover/leaver sampling, or access-review evidence."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/governance/access-review
  license: MIT
---

# IAM access review

Run an authorized review of identity populations and effective grants. This is a review workflow, not an automatic account-revocation mechanism.

## Triggers

- Requests for IAM/access certification, privileged-access review, or recertification evidence.
- Reviews of human accounts, groups, service identities, database roles, CI/CD identities, or host access.
- Audit requests for review population, approvals, exceptions, and remediation records.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/access-review.md"
CACHE only the review checklist and applicable source-system details
```

## Workflow

1. Set the boundary, review period, owner, independent reviewer, evidence repository, and completion date.
2. Define every identity source and reconcile populations before sampling; include inherited group and resource-level permissions.
3. Collect dated, read-only grants and activity metadata. Never export credentials, private keys, or key material.
4. Prioritize administrators, production/data access, external identities, non-human identities, dormant accounts, and exceptions.
5. Record each decision (retain, modify, revoke, or exception), rationale, approver, owner, due date, and evidence link.
6. Track approved changes in the authoritative system; independently verify high-risk changes and preserve before/after evidence.
7. Report population completeness, reviewed counts, overdue items, decisions, exceptions, remediation status, and the period covered.

## Guardrails

- Do not revoke or disable access solely because an inventory flag looks stale; obtain owner authorization and check operational impact.
- Separate the reviewer from the access owner where policy requires independence; time-limit exceptions and assign an expiry.
- Minimize personal data in review exports, restrict evidence access, and expire evidence under the approved policy.
- Treat missing or unreliable last-used data as unknown, not proof of inactivity.

## Related skills

- Framework-specific control evidence → `sec-gdpr-framework-assess`, `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, `sec-pciDss-framework-assess`, `sec-hipaa-framework-assess`, or `sec-fedramp-framework-assess`
- Resource discovery and ownership → `sec-ops-assetInventory-manage`
- Identity implementation and cloud IAM changes → the relevant provider-specific infrastructure skill
