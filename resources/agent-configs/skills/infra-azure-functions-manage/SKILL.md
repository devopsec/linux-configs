---
name: infra-azure-functions-manage
description: "Build and operate Azure Functions apps, Flex Consumption plans, Python v2 handlers, triggers, identity-based connections, deployment slots, and rollouts with Azure CLI and Core Tools. Use when requests mention Azure Functions, Function App, Flex Consumption, `func`, Service Bus trigger, managed identity binding, or slot swap."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-azure/azure-functions
  license: MIT
---

# Azure Functions manage

Use this skill for Azure Functions app lifecycle and runtime integration. Keep source queue/service design and identity authorization with their specialist skills.

## Triggers

- Create, deploy, scale, or troubleshoot an Azure Function App.
- Choose a Functions plan/runtime, author Python v2 handlers, or configure triggers.
- Configure managed-identity connections, app settings, slots, or rollback.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/azure-functions.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/azure-functions.toml"
ELSE use the defaults listed below
IF task involves Azure Functions apps, triggers/bindings, plans, or Core Tools
  REFERENCE "references/functions.md"
CACHE only the loaded Functions guidance for this task
```

## Workflow

1. Confirm subscription, runtime, plan, region, trigger, scaling, network, deployment method, and whether the app is IaC-managed.
2. Prefer Terraform/OpenTofu; use Core Tools `4.16.0` (checked 2026-10-28) for local build/run and Azure CLI `2.91.0` for management.
3. Use Functions runtime 4.x and a supported language version; Flex Consumption is the default for new apps when its constraints fit. Use managed identity for storage and service connections.
4. Keep secrets out of code, local settings committed to source control, and public settings. Configure TLS, authentication, least-privilege data roles, and bounded scale.
5. Deploy immutable artifacts, test health and trigger delivery, and verify rollback. Slots are not supported on Flex Consumption; use a separate app/traffic switch where needed.

### Defaults when no config exists

- Current runtime baseline checked 2026-10-28: Functions host 4.x; Python 3.13; Core Tools `4.16.0`; Azure CLI `2.91.0`; AzureRM provider `5.11.0`.
- IaC: Terraform/OpenTofu; Core Tools for local development; Azure CLI for inspection/deployment when appropriate.
- Ask for runtime, plan, trigger semantics, identity, region, and deployment strategy when absent.

## Related skills

- Azure network and private access → `infra-azure-network-manage`
- Azure service identities and secrets → `infra-azure-vm-manage`, `sec-secrets-any-manage`
- IaC and AVM workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`, `infra-terraform-avmModule-develop`
- AWS serverless equivalent → `infra-aws-lambda-manage`
