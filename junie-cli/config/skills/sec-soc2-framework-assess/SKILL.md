---
name: sec-soc2-framework-assess
description: "Prepare a scoped SOC 2 evidence assessment against the applicable AICPA Trust Services Criteria, including examination period, control design, operating-effectiveness samples, and gap reporting. Use when asked about SOC 2 readiness, Type I or Type II evidence, Trust Services Criteria, audit samples, or SOC 2 control gaps."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/frameworks/soc2-compliance
  license: MIT
---

# SOC 2 evidence assessment

Prepare evidence for the defined service organization and examination scope; the independent CPA determines the examination and report. Do not describe this assessment as a SOC 2 report or certification.

## Triggers

- SOC 2 readiness, Trust Services Criteria mapping, or audit evidence preparation.
- Type I design evidence, Type II operating-effectiveness samples, or gap reporting.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/compliance/soc2.toml" exists
  REFERENCE "~/.junie/custom/configs/compliance/soc2.toml"
ELSE
  USE the defaults below and ask for the missing scope decisions
REFERENCE "references/soc2-assessment.md"
CACHE only selected criteria, examination type, period, and evidence map
```

## Defaults

- Baseline: 2017 AICPA Trust Services Criteria with revised points of focus (2022); source check date: 2026-10-28.
- Default to no selected criteria, no system boundary, and no examination period. Ask the user/owner to confirm all three and whether the engagement is Type I or Type II.
- Configuration template: `assets/config.example.toml`.

## Workflow

1. Confirm the service boundary, applicable Trust Services Criteria, report type, examination period, and auditor instructions.
2. Inventory controls, owners, evidence sources, populations, and expected results; distinguish inherited provider controls from organization controls.
3. For Type II, sample across the entire defined period and inspect evidence of repeated operation, not a single configuration screenshot.
4. Record source, date, population, selection method, reviewer, result, exceptions, and restricted evidence location.
5. Report gaps and evidence limitations with owners and retest actions; let the auditor determine sufficiency and report wording.

## Guardrails

- Do not infer criteria selection, report type, sample size, or examination period.
- Separate policies and management assertions from system-generated evidence and observed operating results.
- Do not claim that provider attestations prove workload controls or that readiness work is an independent SOC 2 opinion.

## Related skills

- Other frameworks → `sec-gdpr-framework-assess`, `sec-iso27001-framework-assess`, `sec-pciDss-framework-assess`, `sec-hipaa-framework-assess`, `sec-fedramp-framework-assess`
- Access reviews and inventory → `sec-iam-accessReview-run`, `sec-ops-assetInventory-manage`
- Backup and recovery evidence → `infra-postgresql-backup-manage`, `infra-bigquery-backup-manage`, `infra-ops-drPlan-create`
