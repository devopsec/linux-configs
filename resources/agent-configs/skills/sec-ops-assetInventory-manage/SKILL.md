---
name: sec-ops-assetInventory-manage
description: "Establish and maintain a reconciled inventory of systems, software, data stores, identities, dependencies, and data flows with ownership and scope evidence. Use when asked for an asset inventory, cloud-resource discovery, system boundary, data-flow mapping, software inventory, or audit scope reconciliation."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/governance/asset-inventory
  license: MIT
---

# Security asset inventory

Build a traceable inventory from multiple authoritative sources. No single cloud discovery export proves complete coverage of applications, identities, data, software, vendors, or manually managed resources.

## Triggers

- Requests for system, cloud, software, data, or dependency inventory.
- Assessment scoping, ownership reconciliation, data-flow mapping, or retirement evidence.
- Cloud-resource discovery or reconciliation of discovered assets to deployed services.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/asset-inventory.md"
CACHE only the confirmed inventory scope, sources, and required fields
```

## Workflow

1. Define the organizational and technical boundary, environments, discovery period, owners, and intended compliance or operational use.
2. Enumerate authoritative discovery sources for cloud resources, hosts, software, identities, data stores, build/release systems, vendors, and data flows.
3. Capture stable identifiers, type, owner, environment, location, status, classification, dependencies, exposure, source, and last-seen date where applicable.
4. Reconcile discovered items with service owners, application and host records, identity sources, data flows, and deployment targets.
5. Assign owners and discovery actions for missing, unsupported, ephemeral, orphaned, or manually managed assets; document exclusions and confidence limits.
6. Track changes, access removal, data disposition, and inventory status through approved retirement; preserve dated exports and query parameters.

## Guardrails

- Do not invent IP addresses, CIDRs, storage names, network ranges, targets, or ownership; request approved data or read an authorized configuration source.
- Never include credentials, private keys, other sensitive values, or unnecessary personal data in inventory records.
- Treat labels and tags as metadata, not as proof of access control or complete classification.
- Describe coverage and blind spots honestly; an incomplete source export is not a full inventory.

## Related skills

- Periodic access certification → `sec-iam-accessReview-run`
- Framework assessment → `sec-gdpr-framework-assess`, `sec-soc2-framework-assess`, `sec-iso27001-framework-assess`, `sec-pciDss-framework-assess`, `sec-hipaa-framework-assess`, or `sec-fedramp-framework-assess`
- Threat modeling and recovery dependencies → `sec-dev-threatModel-create`, `infra-ops-drPlan-create`
