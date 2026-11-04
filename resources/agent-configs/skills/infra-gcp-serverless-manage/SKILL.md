---
name: infra-gcp-serverless-manage
description: "Design and operate Google Cloud Run services, jobs, and second-generation functions with gcloud, Eventarc, IAM, and private networking. Use when tasks mention Cloud Run, Cloud Run functions, serverless jobs, Eventarc triggers, service ingress, or serverless VPC egress."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-gcp/gcp-cloud-functions
  license: MIT
---

# GCP serverless manage

Choose the managed execution model that fits request, container, and job semantics; keep service identity and ingress explicit.

## Triggers

- Cloud Run service/job, Cloud Run functions (2nd gen), `gcloud run`, `gcloud functions`
- Eventarc trigger, authenticated ingress, Direct VPC egress, Serverless VPC Access

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file exists "~/.junie/custom/configs/infra/serverless.toml"
  REFERENCE "~/.junie/custom/configs/infra/serverless.toml"
ELSE
  use defaults: Cloud Run service for container workloads; function for a single event handler; job for finite batch work; authentication required and internal ingress unless explicitly justified
IF task involves Cloud Run/function/job networking, deploy, IAM, or operations
  REFERENCE "references/serverless.md"
IF task involves Pub/Sub topic/subscription or delivery semantics
  REFERENCE skill "infra-gcp-pubsub-manage"
IF task is infrastructure as code
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
CACHE project, region, runtime/image digest, identity, and ingress as runtime inputs
```

## Workflow

1. Confirm workload shape, project, region, data access, security boundary, request duration, and environment.
2. Inspect existing service, revisions, triggers, IAM, ingress, and network egress before editing.
3. Separate build, runtime, and invoker identities; grant only required resource-scoped roles.
4. Require authentication by default, keep secrets in Secret Manager, and deploy images by digest.
5. Review concurrency, maximum instances, timeout, retry/idempotency, and rollback settings before rollout.
6. Verify a ready revision, logs, request/trigger behavior, and rollback path.

## Related skills

- `infra-gcp-pubsub-manage` — Pub/Sub topics, subscriptions, DLQs, and delivery semantics.
- `infra-gcp-bigquery-manage` — data access for analytics handlers.
- `infra-gcp-vpc-manage` — Direct VPC egress, connectors, and private service access.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — deployment infrastructure.
