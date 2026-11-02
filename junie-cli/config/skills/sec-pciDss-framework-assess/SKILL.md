---
name: sec-pciDss-framework-assess
description: "Assess payment-card security evidence against the applicable PCI DSS requirements after defining the Cardholder Data Environment, payment flows, and assessment instrument. Use when asked about PCI DSS readiness, CDE scoping, QSA evidence, ROC/SAQ preparation, or PCI DSS control gaps."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/frameworks/pci-dss-compliance
  license: MIT
---

# PCI DSS evidence assessment

Use the defined payment scope and current PCI SSC materials to organize technical evidence. The QSA, acquirer, or applicable assessor determines scope, validation method, and compliance status.

## Triggers

- PCI DSS readiness, CDE scoping, ROC/SAQ preparation, or QSA evidence requests.
- Payment flows, cardholder data, segmentation, service-provider responsibilities, or PCI control gaps.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/compliance/pciDss.toml" exists
  REFERENCE "~/.junie/custom/configs/compliance/pciDss.toml"
ELSE
  USE the defaults below and ask for the missing scope decisions
REFERENCE "references/pci-dss-assessment.md"
CACHE only the confirmed CDE scope, assessment instrument, and evidence map
```

## Defaults

- Baseline: PCI DSS v4.0.1; source check date: 2026-10-28. Confirm the applicable release and supplemental materials with the QSA/PCI SSC before use.
- Do not infer that a system is in or out of scope; request approved payment flows, CDE boundaries, service-provider roles, and assessment instrument.
- Configuration template: `assets/config.example.toml`.

## Workflow

1. Document payment data flows and identify systems that store, process, transmit, or can affect the security of account data.
2. Confirm the assessment instrument, applicable requirements, segmentation assumptions, third-party responsibilities, and assessor instructions.
3. Collect minimum necessary, dated configuration and process evidence; test representative controls and scope boundaries with authorization.
4. Record requirement, population, test method, evidence location, result, exceptions, owner, and remediation/retest status.
5. Report gaps and unresolved scope questions to the responsible payment-security lead and QSA.

## Guardrails

- Never collect or paste PAN, sensitive authentication data, credentials, cryptographic keys, or unredacted cardholder data into evidence notes.
- Do not assume that card-data substitution or network separation removes scope; obtain assessor confirmation based on the actual implementation.
- Do not claim PCI compliance or QSA approval from a technical self-assessment.

## Related skills

- Other frameworks → `sec-gdpr-framework-assess`, `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, `sec-hipaa-framework-assess`, `sec-fedramp-framework-assess`
- Access review and asset scope → `sec-iam-accessReview-run`, `sec-ops-assetInventory-manage`
- Network and incident controls → the relevant firewall, TLS, and incident-response skills
