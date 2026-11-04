---
name: "infra-pulumi-any-manage"
description: "Use when writing, reviewing, or debugging Pulumi programs (TypeScript, Python, Go, C#, Java, YAML), tests, Automation API orchestration, or ESC configuration — diagnoses failure modes (Output/apply misuse, identity churn, secrets leakage, stack drift, state locking) with version-aware guards for the `pulumi` CLI and Pulumi Cloud. Triggers on: pulumi cli, pulumi up, stack exports, component resource, automation api, pulumi esc."
---

# Pulumi Infrastructure Skill

Diagnose-first guidance for Pulumi. Uses the `pulumi` CLI. This skill prioritizes state safety, secrets handling via ESC, and component modularity.

**Runtime:** `pulumi` (Pulumi — Apache-2.0)
**Current stable:** Pulumi 3.x

## Response Contract

Every Pulumi response must include:

1. **Assumptions & Runtime** — Language (Python/TS/Go/etc), provider versions, backend (Pulumi Cloud/S3/GCS/Azure), execution path (Local/CI/Automation API), and environment criticality.
2. **Risk category addressed** — one or more of: Output/apply misuse (dependency cycles), identity churn (autonaming), secret exposure (plain-text config), blast radius (large stacks), stack drift, or state locking.
3. **Chosen remediation & tradeoffs** — Justification for the code pattern (e.g., ComponentResource vs direct resources, `apply` vs `pulumi.interpolate`).
4. **Validation plan** — Exact commands (`pulumi preview`, `pulumi up --yes`, `pulumi stack output`, `pulumi refresh`) tailored to the runtime and risk tier.
5. **Rollback notes** — How to undo, `pulumi stack import/export` instructions if state mutation is involved.

## Workflow

1. **Capture execution context** — Language, backend, Pulumi version, providers, stack name.
2. **Diagnose failure mode(s)** using the routing table below.
3. **Load only the matching reference file(s)** — do not preload depth the task does not need.
4. **Propose fix with risk controls** — Align with Pulumi's object model and provider lifecycle. Ensure correct handling of `Output<T>`.
5. **Generate artifacts** — Pulumi program code, `Pulumi.yaml`, `Pulumi.<stack>.yaml`, ESC environments, Automation API scripts.
6. **Validate before finalizing** — Recommend `preview` first to inspect the diff.
7. **Emit the Response Contract** at the end.

## Diagnose Before You Generate

| Failure category | Symptoms | Primary references |
|------------------|----------|--------------------|
| **Output/apply misuse** | Resource creation inside `apply()`, dependency cycles, "cannot use Output as string" errors | [Best Practices: Async & Output Handling](references/best-practices.md#async--output-handling) |
| **Identity churn** | Resource name changes causing recreation, autonaming collisions | [Best Practices: Resource Naming](references/best-practices.md#resource-naming) |
| **Secret exposure** | Plaintext in `Pulumi.<stack>.yaml`, unencrypted outputs in logs | [Best Practices: Secrets Management](references/best-practices.md#secrets-management), [State & Backend: ESC](references/state-management.md#pulumi-esc) |
| **State drift / locking** | Local stack != Reality, manual edits in cloud console, stuck lock | [State & Backend Management](references/state-management.md) |
| **CI/CD failures** | OIDC auth issues, concurrent stack locks, PR preview failures | [CI/CD & Automation API](references/automation-api.md) |
| **Component design** | "God" classes, hardcoded values in components, missing `Parent` options | [Best Practices: Component Resources](references/best-practices.md#component-resources) |
| **Testing blind spots** | No unit tests for logic, integration tests hitting real infra without mocks | [Testing Frameworks](references/testing-frameworks.md) |
| **Terraform Migration** | "How to do X in Pulumi", state import issues from TF | [Quick Reference: Pulumi vs Terraform](references/quick-reference.md#pulumi-vs-terraform-comparison) |

## Core Principles

### Component Hierarchy

| Type | When to Use | Scope |
|------|-------------|-------|
| **Resource** | Single cloud resource | `aws.s3.Bucket` |
| **ComponentResource** | Logical group of resources (Module equivalent) | `NetworkComponent` (VPC + Subnets) |
| **Stack** | Deployment unit / Environment | `prod`, `staging`, `dev` |
| **Project** | Collection of stacks | `my-app-infra` |

### Directory Layout

```
Pulumi.yaml         # Project metadata
Pulumi.dev.yaml     # Stack-specific config
main.py / index.ts  # Entry point
components/         # Reusable ComponentResources
tests/              # Unit and integration tests
```

### Naming Conventions

- **Autonaming:** Prefer Pulumi's autonaming (logical name in code != physical name in cloud).
- **Physical Names:** Only specify `name` argument if deterministic names are required for external systems.
- **Logical Names:** Use descriptive logical names (e.g., `web-server-sg`).

## Count vs Loops (General-Purpose Language)

Unlike Terraform's `count` and `for_each`, Pulumi uses native language constructs:
- **TypeScript:** `items.map(i => new Resource(...))`
- **Python:** `[Resource(f"res-{i}", ...) for i in range(n)]`

**Stability Rule:** Ensure logical names remain stable across loops to avoid recreation. Use a stable key from your data as part of the logical name.

## Reference Files

- [Best Practices](references/best-practices.md) — Output handling, naming, components, secrets.
- [State & Backend](references/state-management.md) — Backends, Stacks, ESC, Locking.
- [Testing Frameworks](references/testing-frameworks.md) — Unit, Property-based, Integration tests.
- [CI/CD & Automation API](references/automation-api.md) — Programmatic orchestration, CI integration.
- [Quick Reference](references/quick-reference.md) — CLI cheat sheet, Pulumi vs Terraform comparison.

## License

Apache License 2.0.
