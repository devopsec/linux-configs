---
name: sec-iso27001-framework-assess
description: "Assess an information security management system against ISO/IEC 27001:2022, including scope, risk treatment, Statement of Applicability, Annex A controls, internal audit, and corrective-action evidence. Use when asked for ISO 27001 readiness, ISMS control mapping, SoA review, or ISO 27001 gap assessment."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/frameworks/iso27001-compliance
  license: MIT
---

# ISO/IEC 27001 evidence assessment

Assess the organization's defined ISMS and documented decisions. Do not substitute a generic Annex A checklist for the organization's scope, risk assessment, treatment plan, or SoA.

## Triggers

- ISO/IEC 27001 audit readiness, ISMS review, risk treatment, or SoA preparation.
- Annex A control evidence, internal audit findings, corrective actions, or scope changes.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/compliance/iso27001.toml" exists
  REFERENCE "~/.junie/custom/configs/compliance/iso27001.toml"
ELSE
  USE the defaults below and ask for the missing scope decisions
REFERENCE "references/iso27001-assessment.md"
CACHE only the approved ISMS scope, baseline, and applicable control evidence
```

## Defaults

- Baseline: ISO/IEC 27001:2022 with Amendment 1:2024; source check date: 2026-10-28.
- Do not default organization scope, risk method, control applicability, SoA rationale, or audit period; request the approved records.
- Configuration template: `assets/config.example.toml`.

## Workflow

1. Confirm the ISMS boundary, interested parties, interfaces, risk method, assessment period, and audit criteria.
2. Trace risks to treatment decisions, applicable controls, owners, implementation, and evidence; review exclusions and SoA rationale.
3. Sample implementation and operating evidence for the agreed period; include provider responsibility only where the service and control are in scope.
4. Report conformity evidence, nonconformities, opportunities for improvement, missing evidence, owner, action, and follow-up test.
5. Route interpretation of the standard and certification decisions to the ISMS owner and accredited auditor.

## Guardrails

- Do not copy a sample SoA or mark controls applicable without the organization's risk-treatment decision.
- Keep the main standard's requirements distinct from Annex A reference controls and from contract or legal obligations.
- Do not claim certification based on a self-assessment or provider attestation.

## Related skills

- Other frameworks → `sec-gdpr-framework-assess`, `sec-soc2-framework-assess`, `sec-pciDss-framework-assess`, `sec-hipaa-framework-assess`, `sec-fedramp-framework-assess`
- Identity reviews and inventory → `sec-iam-accessReview-run`, `sec-ops-assetInventory-manage`
- Security risk and recovery planning → `sec-dev-threatModel-create`, `infra-ops-drPlan-create`
