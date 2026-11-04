---
name: infra-opentofu-migration-run
description: "Plan and execute a controlled Terraform-to-OpenTofu migration, including feature compatibility, provider lockfiles, state backend continuity, validation, and CI changes. Use when requests mention migrating Terraform to OpenTofu, `tofu init`, provider registry changes, or OpenTofu adoption."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/iac/opentofu-migration
  license: MIT
---

# OpenTofu migration run

Use a staged, plan-only migration first. Do not combine runtime migration with backend moves, provider upgrades, or infrastructure redesign.

## Triggers

- Terraform-to-OpenTofu migration, `tofu init`, registry.opentofu.org, state compatibility
- Replacing Terraform CLI steps in local workflows or CI

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or infrastructure README if present
IF task involves runtime, state, lockfile, backend, or CI migration
  REFERENCE "references/migration-runbook.md"
IF configuration is GCP, AWS, or Azure specific
  REFERENCE the matching infra-terraform-{gcp,aws,azure}-manage skill
IF the source platform is Terraform and shared IaC guidance is needed
  REFERENCE skill "infra-terraform-any-manage"
IF the destination workflow uses OpenTofu features after migration
  REFERENCE skill "infra-opentofu-any-manage"
CACHE exact Terraform/OpenTofu versions, backend, workspace, lockfile, and state backup location
```

## Workflow

1. Inventory Terraform/OpenTofu versions, providers, modules, backends, workspaces, CI identities, features, and state ownership.
2. Capture a reviewed Terraform baseline plan and a protected, recoverable state snapshot; prevent concurrent operations.
3. Pin OpenTofu `1.13.2` (checked 2026-10-28) and test a copy/isolated workspace first; preserve provider versions and lockfile.
4. Compare feature use and provider resolution; remediate incompatibilities before sharing production state.
5. Validate and plan with OpenTofu; review every difference against the Terraform baseline and require no unexplained replacements.
6. Change CI to OpenTofu only after approval; retain the previous runner and tested recovery path until production verification.

Never apply the first OpenTofu plan to production automatically. Terraform and OpenTofu must not operate concurrently on the same state.

## Related skills

- `infra-opentofu-any-manage` — normal OpenTofu workflows and features.
- `infra-terraform-any-manage` — Terraform baseline and migration source.
- `infra-terraform-gcp-manage`, `infra-terraform-aws-manage`, `infra-terraform-azure-manage` — provider semantics.
- `sec-dev-threatModel-create` — assess migration identity, state, and supply-chain risks.
