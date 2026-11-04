---
name: sec-fedramp-framework-assess
description: "Assess evidence for a federal information system or cloud service pursuing or maintaining a FedRAMP authorization, including boundary, impact level, baseline, control inheritance, SSP, assessment, POA&M, and continuous monitoring. Use when asked for FedRAMP readiness, authorization evidence, Rev 5 controls, or federal cloud control gaps."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/frameworks/fedramp-compliance
  license: MIT
---

# FedRAMP evidence assessment

Only use this workflow for an identified federal system or cloud service and its approved authorization path. A cloud provider's authorization does not confer authorization on a customer workload.

## Triggers

- FedRAMP authorization, continuous monitoring, assessment evidence, or POA&M review.
- Federal system boundary, impact level, baseline selection, control inheritance, or SSP evidence.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/compliance/fedramp.toml" exists
  REFERENCE "~/.junie/custom/configs/compliance/fedramp.toml"
ELSE
  USE the defaults below and ask for the authorization path and baseline
REFERENCE "references/fedramp-assessment.md"
CACHE only the confirmed authorization boundary, baseline, and evidence requirements
```

## Defaults

- Reference baseline: FedRAMP Rev 5 guidance using NIST SP 800-53 Rev. 5.2.0 in the FedRAMP 2026 reference; source check date: 2026-10-28.
- Do not default authorization path, impact level, agency, boundary, tailoring, or assessment cadence. Confirm the current FedRAMP rules and agency/3PAO instructions.
- Configuration template: `assets/config.example.toml`.

## Workflow

1. Confirm agency, system owner, authorization path, boundary, impact level, selected baseline, and responsible AO/3PAO.
2. Map requirements to system implementation, provider inheritance, customer evidence, owners, and current assessment procedures.
3. Reconcile the component inventory and data flows to the authorization boundary; sample evidence and continuous-monitoring results.
4. Maintain the approved SSP, assessment artifacts, POA&M, owners/milestones, and retest or closure proof.
5. Report gaps and uncertainty against the exact authorized baseline; obtain authority direction for exceptions and status claims.

## Guardrails

- Do not infer authorization from a cloud provider's listing or reuse control parameters from an obsolete baseline.
- Treat FedRAMP Rev 5 and other authorization paths as distinct; do not merge control sets without approval.
- Keep federal system evidence in the approved repository and avoid exposing sensitive or controlled information in reports.

## Related skills

- Other framework assessments → `sec-gdpr-framework-assess`, `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, `sec-pciDss-framework-assess`, `sec-hipaa-framework-assess`
- Access and asset evidence → `sec-iam-accessReview-run`, `sec-ops-assetInventory-manage`
- Risk analysis and recovery planning → `sec-dev-threatModel-create`, `infra-ops-drPlan-create`
