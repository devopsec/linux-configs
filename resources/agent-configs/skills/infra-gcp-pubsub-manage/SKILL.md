---
name: infra-gcp-pubsub-manage
description: "Manage Google Cloud Pub/Sub topics, pull/push/export subscriptions, ordering, retries, dead-letter topics, IAM, replay, and monitoring. Use when requests mention Pub/Sub, `gcloud pubsub`, subscription backlog, ack deadline, DLQ, message ordering, replay/seek, or Pub/Sub push to Cloud Run."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: []
  license: MIT
---

# GCP Pub/Sub manage

In-house guidance for Pub/Sub resource lifecycle, message delivery, failure routing, and operational safety.

## Triggers

- Topic, subscription, publisher, subscriber, pull/push/export subscription
- Ack deadline, redelivery, ordering key, exactly-once, dead-letter topic, seek/replay

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file exists "~/.junie/custom/configs/infra/pubsub.toml"
  REFERENCE "~/.junie/custom/configs/infra/pubsub.toml"
ELSE
  use pull delivery by default; choose authenticated push or export only when a requirement justifies it
IF task involves Pub/Sub topology, IAM, delivery, DLQ, replay, or monitoring
  REFERENCE "references/pubsub-operations.md"
IF a subscription exports data into BigQuery
  REFERENCE skill "infra-gcp-bigquery-manage"
IF messages trigger Cloud Run or Cloud Run functions
  REFERENCE skill "infra-gcp-serverless-manage"
IF Pub/Sub resources are managed by HCL
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
CACHE project, topic, subscription, region, retention, and retry policy as runtime inputs
```

## Workflow

1. Confirm publisher, subscriber, delivery mode, ordering/latency requirements, retention, and data sensitivity.
2. Inspect topic/subscription configuration, service-agent IAM, backlog, and consumer behavior before changing resources.
3. Assume at-least-once delivery; require idempotent consumers and an explicit poison-message strategy.
4. Grant publisher/subscriber roles at the topic/subscription boundary; use authenticated push and a dedicated invoker identity.
5. Treat delete, seek, retention changes, and DLQ reconfiguration as high impact; explain replay/loss effects and request approval.
6. Verify delivery, acknowledgements, dead-letter routing, backlog age, and consumer error rate.

## Stack notes

Cloud Build validation identities should not publish operational events or edit production subscriptions. Follow the repository’s generic separation pattern: PR checks validate only, publishers are narrowly scoped, and release verification is read-only.

## Related skills

- `infra-gcp-bigquery-manage` — BigQuery export and analytics tables.
- `infra-gcp-serverless-manage` — Cloud Run/Eventarc consumers.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — Pub/Sub infrastructure as code.
