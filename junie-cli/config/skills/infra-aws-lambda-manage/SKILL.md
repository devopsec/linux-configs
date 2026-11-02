---
name: infra-aws-lambda-manage
description: "Build, deploy, secure, and operate AWS Lambda functions, event-source mappings, Function URLs, and SAM applications with AWS CLI, SAM, and Terraform/OpenTofu. Use when requests mention Lambda, serverless functions, SAM, SQS triggers, EventBridge Scheduler, cold starts, concurrency, or function URLs."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-lambda
  license: MIT
---

# AWS Lambda manage

Use this skill for AWS Lambda function lifecycle and event integration; keep source-system design and IAM policy authoring with their specialist skills.

## Triggers

- Create, update, version, alias, or troubleshoot a Lambda function.
- Configure SQS, stream, S3, or schedule triggers and failure handling.
- Package Python code, use SAM, tune concurrency, or secure a Function URL.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-lambda.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-lambda.toml"
ELSE use the defaults listed below
IF task involves Lambda functions, SAM, triggers, or Function URLs
  REFERENCE "references/lambda.md"
CACHE only the loaded Lambda guidance for this task
```

## Workflow

1. Confirm account, region, runtime, architecture, event source, expected throughput, and whether IaC owns the function.
2. Default to Terraform/OpenTofu; use SAM for AWS Serverless Application Model deployments. Pin runtimes and dependencies in the deployment source and lockfiles.
3. Design least-privilege execution roles, bounded concurrency, structured logs, tracing, and idempotent event processing. Keep secrets in a secret store, never in function settings.
4. Deploy a version and shift traffic through an alias or supported staged rollout. Review replacement, permission, and cost effects before applying.
5. Verify health, event mapping state, failure destinations, alarms, and rollback path; do not expose payload secrets in logs.

### Defaults when no config exists

- IaC: Terraform/OpenTofu; AWS CLI for inspection; SAM only when using its application packaging/deploy workflow.
- Production runtime baseline (checked 2026-10-28): Python 3.14 and Node.js 24 are GA; Python 3.15 and Node.js 26 are preview and not production defaults.
- Ask for runtime, architecture, trigger, and failure-handling requirements when missing.

## Related skills

- Role and resource permissions → `infra-aws-iam-manage`
- S3 event source and bucket policy → `infra-aws-s3-manage`
- IaC workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
- Secret storage → `sec-secrets-any-manage`
