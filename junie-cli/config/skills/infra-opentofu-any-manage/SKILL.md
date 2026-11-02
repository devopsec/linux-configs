---
name: "infra-opentofu-any-manage"
description: "Use when writing, reviewing, or debugging OpenTofu modules, tests, CI pipelines, security scans, or state operations — diagnoses failure modes (identity churn, secrets, blast radius, CI drift, state corruption) with version-aware guards for the `tofu` binary. Triggers on: tofu binary, OpenTofu configurations, registry.opentofu.org, OpenTofu state encryption, tofu test."
license: "Apache-2.0"
metadata:
  author: "Anton Babenko (adapted for OpenTofu by Junie)"
  version: "1.17.0"
---

# OpenTofu Infrastructure Skill

Diagnose-first guidance for OpenTofu. Uses the `tofu` binary. Core file is a workflow; depth lives in references loaded on demand.

**Runtime:** `tofu` (OpenTofu — MPL 2.0, Linux Foundation governance)
**Starts at:** OpenTofu 1.6 (fork of Terraform at 1.5.x)

## Response Contract

Every OpenTofu response must include:

1. **Assumptions & version floor** — runtime (`tofu`), exact version, providers, state backend, execution path (local/CI/Spacelift/Atlantis), environment criticality. State assumptions explicitly if the user did not provide them.
2. **Risk category addressed** — one or more of: identity churn, secret exposure, blast radius, CI drift, compliance gaps, state corruption, provider upgrade risk, testing blind spots.
3. **Chosen remediation & tradeoffs** — what was chosen, what was traded off, why.
4. **Validation plan** — exact commands (`fmt -check`, `validate`, `plan -out`, policy check) using `tofu` binary, tailored to runtime and risk tier.
5. **Rollback notes** — for any destructive or state-mutating change: how to undo, what evidence to keep.

Never recommend direct production apply without a reviewed plan artifact and approval.

## Workflow

1. **Capture execution context** — `tofu` version, provider(s), backend, execution path, environment criticality.
2. **Diagnose failure mode(s)** using the routing table below. If intent spans categories, load both references.
3. **Load only the matching reference file(s)** — do not preload depth the task does not need.
4. **Propose fix with risk controls** — why this addresses the mode, what could still go wrong, guardrails (tests/approvals/rollback).
5. **Generate artifacts** — HCL, migration blocks (`moved`, `import`), CI changes, policy rules.
6. **Validate before finalizing** — run validation commands tailored to risk tier.
7. **Emit the Response Contract** at the end.

## Diagnose Before You Generate

| Failure category | Symptoms | Primary references |
|------------------|----------|--------------------|
| **Identity churn** | Resource addresses shift after refactor, `count` index churn, missing `moved` blocks | [Code Patterns: count vs for_each](references/code-patterns.md#count-vs-for_each-deep-dive), [Code Patterns: moved blocks](references/code-patterns.md#moved-blocks), [Code Patterns: LLM mistakes](references/code-patterns.md#llm-mistake-checklist) |
| **Secret exposure** | Secrets in defaults, state, logs, CI artifacts | [Security & Compliance](references/security-compliance.md), [Code Patterns: write-only](references/code-patterns.md#write-only-arguments), [State Management](references/state-management.md) |
| **Blast radius** | Oversized stacks, shared prod/non-prod state, unsafe applies | [State Management](references/state-management.md), [Module Patterns](references/module-patterns.md) |
| **CI drift** | Local plan ≠ CI plan, apply without reviewed artifact, unpinned versions | [CI/CD Workflows](references/ci-cd-workflows.md), [Code Patterns: versions](references/code-patterns.md#version-management) |
| **Compliance gaps** | Missing policy stage, no approval model, no evidence retention | [Security & Compliance](references/security-compliance.md), [CI/CD Workflows](references/ci-cd-workflows.md) |
| **Testing blind spots** | Plan-only validation of computed values, set-type indexing, mock/real confusion | [Testing Frameworks](references/testing-frameworks.md) |
| **State corruption / recovery** | Stuck lock, backend migration, drift reconciliation | [State Management](references/state-management.md) |
| **Provider upgrade risk** | Breaking-change provider bump, unpinned modules | [Code Patterns: versions](references/code-patterns.md#version-management), [Module Patterns](references/module-patterns.md) |
| **Provider lifecycle** | Removing a provider with resources still in state, orphaned resources, `removed` block usage | [State Management: Provider Removal](references/state-management.md#provider-removal) |
| **Bootstrap / orchestration misuse** | `null_resource` + `local-exec` for bootstrap, `remote-exec` for setup scripts, provisioner stdout leaking secrets in CI logs | [Code Patterns: Provisioners as Last Resort](references/code-patterns.md#provisioners-as-last-resort) |
| **Navigation / safe-rename blind spots** | Cannot locate symbol defs/refs semantically, value-symbol rename done as blind text replace, grep-only refactor missing refs | [Code Intelligence](references/code-intelligence-lsp.md#terraform-ls-capability-matrix) |
| **Cross-cloud / provider mapping** | "What's the Azure/GCP equivalent of X", picking a backend/auth model per cloud | [State Management: Cross-cloud equivalents](references/state-management.md#cross-cloud-equivalents) |

## When to Use This Skill

**Activate when:** creating or reviewing OpenTofu configurations or modules, setting up or debugging `tofu test`, structuring multi-environment deployments, implementing IaC CI/CD with the `tofu` binary, choosing module patterns or state organization, configuring or migrating remote state backends, evaluating OpenTofu-specific features (state encryption, community registry at `registry.opentofu.org`).

**Don't use for:** basic HCL syntax questions already known, provider API reference (link to docs), cloud-platform questions unrelated to OpenTofu, Terraform-specific workflows like HCP Terraform/Terraform Cloud.

## OpenTofu-Specific Features

OpenTofu diverges from Terraform post-1.6 with additions not available in HashiCorp's Terraform:

| Feature | OpenTofu Version | Notes |
|---------|-----------------|-------|
| **State encryption** | 1.7+ | Built-in AES-GCM / PBKDF2 / AWS KMS / GCP KMS encryption at rest — no Terraform equivalent |
| **Provider-defined functions** | 1.7+ | Provider HCL functions callable in expressions |
| **`tofu test` with encryption** | 1.8+ | Test framework aware of encryption config |
| **Registry** | — | `registry.opentofu.org` — OpenTofu's own provider/module registry |

For the full feature comparison with Terraform, see [Quick Reference: OpenTofu vs Terraform](references/quick-reference.md#opentofu-vs-terraform-comparison).

## Core Principles

### Module Hierarchy

| Type | When to Use | Scope |
|------|-------------|-------|
| **Resource module** | Single logical group of connected resources | VPC + subnets, SG + rules |
| **Infrastructure module** | Collection of resource modules for a purpose | Multiple resource modules in one region/account |
| **Composition** | Complete infrastructure | Spans multiple regions/accounts |

Flow: resource → resource module → infrastructure module → composition.

### Directory Layout

```
environments/   # prod/ staging/ dev/  — per-env configurations
modules/        # networking/ compute/ data/ — reusable modules
examples/       # minimal/ complete/ — docs + integration fixtures
```

Separate **environments** from **modules**. Use `examples/` as both documentation and test fixtures. Keep modules small and single-responsibility.

See [Module Patterns](references/module-patterns.md) for architecture principles, naming conventions, variable/output contracts.

### Naming Conventions (summary)

- Descriptive resource names (`aws_instance.web_server`, not `aws_instance.main`)
- Reserve `this` for genuine singleton resources only
- Prefix variables with context (`vpc_cidr_block`, not `cidr`)
- Standard files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`

### Block Ordering (summary)

Resource blocks: `count`/`for_each` first → arguments → `tags` → `depends_on` → `lifecycle`.
Variable blocks: `description` → `type` → `default` → `validation` → `nullable` → `sensitive`.

See [Code Patterns: Block Ordering & Structure](references/code-patterns.md#block-ordering--structure) for the full rules and examples.

## Testing Strategy

### Decision Matrix: Which Testing Approach?

| Situation | Approach | Tools | Cost |
|-----------|----------|-------|------|
| Quick syntax check | Static analysis | `tofu validate`, `tofu fmt` | Free |
| Pre-commit validation | Static + lint | `tofu validate`, `tflint`, `trivy`, `checkov` | Free |
| OpenTofu 1.6+, simple logic | Native test framework | `tofu test` | Free-Low |
| Pre-1.6, or Go expertise | Integration testing | Terratest | Low-Med |
| Security/compliance focus | Policy as code | OPA | Free |
| Cost-sensitive workflow | Mock providers (1.7+) | `tofu test` + mocks | Free |
| Multi-cloud, complex | Full integration | Terratest + real infra | Med-High |

### Native Test Rules (1.6+)

- `command = plan` — fast, for input-derived values only
- `command = apply` — required for **computed values** (ARNs, generated names) and **set-type nested blocks**
- Set-type blocks cannot be indexed with `[0]` — use `for` expressions or materialize via `command = apply`

See [Testing Frameworks](references/testing-frameworks.md) for static-analysis pipelines, native-test patterns, Terratest integration, mock providers, and the full LLM-mistake checklist.

## Count vs For_Each — Quick Rule

| Scenario | Use | Why |
|----------|-----|-----|
| Boolean condition (create / don't) | `count = condition ? 1 : 0` | Optional singleton toggle |
| Items may be reordered or removed | `for_each = toset(list)` | Stable resource addresses |
| Reference by key | `for_each = map` | Named access |
| Multiple named resources | `for_each` | Better identity stability |

**Never** use list index as long-lived identity. See [Code Patterns: count vs for_each](references/code-patterns.md#count-vs-for_each-deep-dive).

## Module Development

Standard layout:

```
my-module/
├── README.md       # Usage documentation
├── main.tf         # Primary resources
├── variables.tf    # Typed inputs with descriptions
├── outputs.tf      # Output values
├── versions.tf     # required_version + required_providers
├── examples/
│   ├── minimal/
│   └── complete/
└── tests/
    └── module_test.tftest.hcl   # or Go for Terratest
```

**Variable contracts**: always `description`, always explicit `type`, use `validation` for complex constraints, use `sensitive = true` for secrets, prefer `optional()` with typed defaults (1.3+) over untyped `map(any)`.

**Output contracts**: always `description`, mark sensitive outputs, expose stable subsets (not whole provider objects).

See [Module Patterns](references/module-patterns.md) for the full contract patterns, module release checklist, and LLM-mistake checklist.

## CI/CD

Pipeline stages: **validate** → **test** → **plan** → **apply** (with environment protection).

Cost control: mock providers on PR validation, real-cloud integration only on main or scheduled, tag test resources, auto-cleanup.

Drift prevention: pin runtime and providers, commit `.terraform.lock.hcl`, apply the **reviewed plan artifact** from the plan stage (do not re-run `plan` inside the apply job).

Use `tofu` binary in all CI steps. Spacelift, env0, and Atlantis support OpenTofu natively.

See [CI/CD Workflows](references/ci-cd-workflows.md) for GitHub Actions, GitLab CI, and Atlantis templates plus the LLM-mistake checklist.

## Security & Compliance

**Essential checks:**

```bash
trivy config .
checkov -d .
```

**State Encryption (OpenTofu 1.7+ — not available in Terraform):**

```hcl
terraform {
  encryption {
    key_provider "pbkdf2" "my_passphrase" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "my_method" {
      keys = key_provider.pbkdf2.my_passphrase
    }
    state {
      method = method.aes_gcm.my_method
    }
  }
}
```

**Don't:** store secrets in variables or `.tfvars`, use default VPC, skip encryption, open security groups to `0.0.0.0/0`.

**Do:** source secrets from a cloud secret manager or use `write_only` arguments (1.8+), create dedicated VPCs, enforce encryption at rest and TLS, least-privilege SGs.

See [Security & Compliance](references/security-compliance.md) for trivy/checkov pipelines, state-file hardening, compliance mappings, and the LLM-mistake checklist.

## State Management

**Never use local state in teams or production.**

### Choosing a Remote Backend

```hcl
terraform {
  backend "s3" {
    bucket        = "my-opentofu-state"
    key           = "prod/vpc/terraform.tfstate"
    region        = "us-east-1"
    encrypt       = true
    use_lockfile  = true   # Native S3 locking, OpenTofu 1.8+
  }
}
```

On OpenTofu < 1.8, use `dynamodb_table = "terraform-state-lock"` for S3 locking. Azure Storage, GCS, and Terraform-compatible backends all offer built-in locking.

See [State Management](references/state-management.md) for locking, migration, multi-team isolation, disaster recovery, and the LLM-mistake checklist.

## Version Management

| Component | Strategy | Example |
|-----------|----------|---------|
| OpenTofu runtime | Pin minor | `required_version = "~> 1.8"` |
| Providers | Pin major | `version = "~> 5.0"` |
| Modules (prod) | Pin exact | `version = "5.1.2"` |
| Modules (dev) | Allow patch | `version = "~> 5.1"` |

Commit `.terraform.lock.hcl` intentionally. Keep provider/runtime upgrades in a separate PR from functional changes. See [Code Patterns: Version Management](references/code-patterns.md#version-management).

## OpenTofu Feature Timeline

| Feature | Min version | Common use |
|---------|-------------|------------|
| `try()` | 0.13+ | Safe fallbacks |
| `nullable = false` | 1.1+ | Prevent null override |
| `moved` blocks | 1.1+ | Refactor without destroy/recreate |
| `optional()` with defaults | 1.3+ | Typed object attributes |
| `import` blocks | 1.5+ | Declarative imports |
| `check` blocks | 1.5+ | Runtime assertions |
| Native `tofu test` | 1.6+ | Built-in test framework |
| **State encryption** | **1.7+** | **OpenTofu-only** |
| Mock providers | 1.7+ | Cost-free unit testing |
| `removed` blocks | 1.7+ | Declarative resource removal |
| **Provider-defined functions** | **1.7+** | **Provider HCL functions** |
| Cross-variable validation | 1.8+ | Reference other `var.*` in `validation` |
| `write_only` arguments | 1.8+ | Secrets never stored in state |
| S3 native lock-file | 1.8+ | State locking without DynamoDB |

Before emitting a feature, verify the `tofu` version floor. See [Code Patterns: Feature Guard Table](references/code-patterns.md#feature-guard-table--version-floor--common-llm-errors).

## Code Intelligence (terraform-ls)

Semantic navigation for HCL. terraform-ls works with OpenTofu configurations.

| Goal | Use | Tradeoff |
|------|-----|----------|
| Find definition / all references | terraform-ls `goToDefinition` / `findReferences` | Needs `tofu init` + a position anchor |
| Rename value symbol (var/local/output/provider alias) | Manual: `findReferences` -> per-file fresh Read -> edit -> `tofu validate` | No rename provider |
| Rename resource/module address | `moved` block + `tofu plan` shows 0 destroy | Text rename forces destroy/recreate |
| Exact text / known name / `.tfvars` / non-HCL | `rg` + Read | No semantic scope |

✅ Prereq: `tofu` on PATH, `tofu init` run.
✅ LSP calls are position-anchored (`file:line:character`) — anchor with `rg` first.
❌ Do not claim "LSP broken, using rg" until the [Degradation Gate](references/code-intelligence-lsp.md#degradation-gate) passes.

Depth: [Code Intelligence](references/code-intelligence-lsp.md#terraform-ls-capability-matrix).

## Reference Files

Progressive disclosure — essentials here, depth on demand:

- [Testing Frameworks](references/testing-frameworks.md) — static analysis, `tofu test`, Terratest, mock providers
- [Module Patterns](references/module-patterns.md) — structure, variable/output contracts, `terraform_remote_state` rules, release checklist
- [CI/CD Workflows](references/ci-cd-workflows.md) — GitHub Actions, GitLab CI, Atlantis (tofu binary)
- [Security & Compliance](references/security-compliance.md) — trivy/checkov, state encryption, secrets handling, compliance mappings
- [State Management](references/state-management.md) — backends, locking, migration, multi-team, recovery
- [Code Patterns](references/code-patterns.md) — block ordering, `count`/`for_each` deep dive, modern features, version management, locals
- [Code Intelligence](references/code-intelligence-lsp.md) — terraform-ls capabilities, position-anchored calls, manual rename, degradation gate
- [Quick Reference](references/quick-reference.md) — `tofu` command cheat sheets, flowcharts, OpenTofu vs Terraform comparison

## Related skills

- `infra-opentofu-migration-run` — plan-only Terraform-to-OpenTofu migration.
- `infra-terraform-any-manage` — shared Terraform concepts and source baseline.
- `infra-terraform-gcp-manage`, `infra-terraform-aws-manage`, `infra-terraform-azure-manage` — provider-specific HCL.
- `sec-dev-threatModel-create` — threat-model state, identity, and infrastructure migration risks.

## License

Apache License 2.0.

**Original skill Copyright © 2026 Anton Babenko**
