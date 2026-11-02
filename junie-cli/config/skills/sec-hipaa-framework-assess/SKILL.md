---
name: sec-hipaa-framework-assess
description: "Assess evidence for HIPAA Privacy, Security, and Breach Notification obligations where a covered entity or business associate and ePHI are in scope. Use when asked about HIPAA safeguards, ePHI risk analysis, BAA evidence, contingency planning, or HIPAA control gaps."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/frameworks/hipaa-compliance
  license: MIT
---

# HIPAA evidence assessment

Start by confirming the entity role and whether the scoped system creates, receives, maintains, or transmits ePHI. This workflow organizes evidence and is not legal advice or an OCR determination.

## Triggers

- HIPAA safeguard evidence, ePHI risk analysis, audit readiness, or remediation planning.
- Business Associate Agreement, access, audit controls, contingency planning, or breach-response evidence.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/compliance/hipaa.toml" exists
  REFERENCE "~/.junie/custom/configs/compliance/hipaa.toml"
ELSE
  USE the defaults below and ask for the missing scope decisions
REFERENCE "references/hipaa-assessment.md"
CACHE only confirmed entity role, ePHI scope, and applicable safeguards
```

## Defaults

- Baseline: applicable 45 CFR Parts 160 and 164; eCFR source checked 2026-10-28.
- Do not assume covered-entity/business-associate status, ePHI presence, service eligibility, or applicability of an addressable specification; obtain responsible officer/counsel confirmation.
- Configuration template: `assets/config.example.toml`.

## Workflow

1. Confirm entity roles, system boundary, ePHI categories, data flows, service providers, and applicable current regulatory text.
2. Map the administrative, physical, and technical safeguards to responsible owners and evidence; include risk analysis, access, audit, integrity, transmission, and contingency controls.
3. Verify BAA and service-specific eligibility where a cloud or other third party handles ePHI; separate inherited provider controls from customer duties.
4. Collect approved, minimum-necessary evidence and test a sample of procedures, access decisions, restore results, or incident processes.
5. Report evidence gaps, documented addressable-specification decisions, owners, remediation, and retest; route legal and breach determinations to responsible experts.

## Guardrails

- Do not paste ePHI, unnecessary identifiers, credentials, or key material into prompts, evidence summaries, or reports.
- Documentation-retention duties do not automatically establish a universal technical-log retention period.
- A provider agreement or attestation alone does not prove that a particular workload or service is eligible or compliant.

## Related skills

- Other frameworks → `sec-gdpr-framework-assess`, `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, `sec-pciDss-framework-assess`, `sec-fedramp-framework-assess`
- Access reviews and inventory → `sec-iam-accessReview-run`, `sec-ops-assetInventory-manage`
- Incident response and recovery → `sec-ops-incident-respond`, `infra-ops-drPlan-create`
