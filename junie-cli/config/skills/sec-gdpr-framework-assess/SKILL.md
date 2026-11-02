---
name: sec-gdpr-framework-assess
description: "Assess privacy-control evidence against Regulation (EU) 2016/679 (GDPR), including processing records, data-subject rights, processor transfers, retention, and incident decision evidence. Use when asked for a GDPR assessment, privacy audit readiness, personal-data mapping, DSAR evidence, or GDPR control gap analysis."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/frameworks/gdpr-compliance
  license: MIT
---

# GDPR evidence assessment

Use the applicable GDPR text and approved organizational decisions to assess a defined processing activity. This workflow is not legal advice, a DPIA determination, or a compliance certification.

## Triggers

- GDPR control evidence, privacy gap analysis, audit preparation, or processing records.
- Personal-data mapping, DSAR/erasure testing, processor and transfer evidence, or breach decision records.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/compliance/gdpr.toml" exists
  REFERENCE "~/.junie/custom/configs/compliance/gdpr.toml"
ELSE
  USE the defaults below and ask for the missing scope decisions
REFERENCE "references/gdpr-assessment.md"
CACHE only the applicable evidence map and confirmed assessment scope
```

## Defaults

- Baseline: Regulation (EU) 2016/679; source check date: 2026-10-28.
- Do not default the controller/processor role, lawful basis, jurisdiction, system boundary, processing period, or retention rule; obtain owner/privacy-lead confirmation.
- Configuration template: `assets/config.example.toml`.

## Workflow

1. Confirm entity roles, jurisdiction, processing purpose, data categories, data subjects, systems, recipients, transfers, and assessment period.
2. Map applicable requirements to the processing record, privacy/security controls, DSAR and retention procedures, processor arrangements, and incident decisions.
3. Collect dated, minimized, read-only evidence; test representative procedures without copying unnecessary personal data into the report.
4. Record applicability, evidence location and period, test result, confirmed gap, missing evidence, exclusions, owner, action, and retest date.
5. Route lawful-basis, transfer, notification, retention, and data-subject-rights interpretations to the privacy lead or counsel.

## Guardrails

- Identify personal data based on the context and linkability of the data; pseudonymized data is not automatically anonymous.
- Evidence may itself contain personal data. Restrict access, redact identifiers, and retain only under the approved evidence policy.
- Do not claim legal compliance or determine a reportable breach from technical evidence alone.

## Related skills

- Other framework mappings → `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, `sec-pciDss-framework-assess`, `sec-hipaa-framework-assess`, `sec-fedramp-framework-assess`
- Identity review and scope inventory → `sec-iam-accessReview-run`, `sec-ops-assetInventory-manage`
- Incident response and continuity → `sec-ops-incident-respond`, `infra-ops-drPlan-create`
