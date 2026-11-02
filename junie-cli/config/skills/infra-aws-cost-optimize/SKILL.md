---
name: infra-aws-cost-optimize
description: "Analyze and reduce AWS infrastructure spend with Cost Explorer, budgets, anomaly detection, Compute Optimizer, Savings Plans, reservations, and waste reports. Use when requests mention AWS bills, Cost Explorer, budgets, cost anomaly, rightsizing, Savings Plans, idle resources, or cost allocation tags."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-cost-optimization
  license: MIT
---

# AWS cost optimize

Use this skill to investigate AWS spend and propose controlled savings. Cost findings are hypotheses until resource owners confirm the workload and service-level impact.

## Triggers

- Explain a bill, rising spend, budget alert, or cost anomaly.
- Find idle/underused resources or evaluate rightsizing and commitments.
- Design cost allocation tags, Cost Explorer exports, or budget alerts.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-cost.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-cost.toml"
ELSE use the defaults listed below
IF task involves AWS spend, budgets, cost recommendations, or unused resources
  REFERENCE "references/cost.md"
CACHE only the loaded cost guidance for this task
```

## Workflow

1. Query billing and resource metadata read-only; confirm payer/account, time window, region, currency, tag coverage, and owner context.
2. Attribute spend to services, resources, and tags; separate one-time charges, commitments, data transfer, and usage growth.
3. Prioritize reversible rightsizing and waste candidates. Show estimated savings, confidence, performance/availability effect, and rollback path.
4. Require owner confirmation before stopping, deleting, resizing, or purchasing commitments; run a plan/dry-run and preserve data before cleanup.
5. Verify changes against subsequent usage and budget/anomaly signals; avoid frequent billed API polling.

### Defaults when no config exists

- Read-only analysis: Cost Explorer, Cost Anomaly Detection, and Compute Optimizer; resource changes through IaC and the matching service workflow.
- No automatic deletion or commitment purchase. Require owner approval and an explicit savings horizon.
- Ask for account, billing period, region, workload owners, and acceptable risk when absent.

## Related skills

- AWS service changes → `infra-aws-ec2-manage`, `infra-aws-rds-manage`, `infra-aws-s3-manage`, `infra-aws-vpc-manage`, `infra-aws-lambda-manage`
- Cost estimation in IaC → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
- Recovery requirements → `infra-ops-drPlan-create`
