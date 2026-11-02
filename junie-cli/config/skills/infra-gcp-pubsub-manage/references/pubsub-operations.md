# Pub/Sub topics and subscriptions

Project, topic/subscription IDs, region, retention, message size/rate, and consumer identity are runtime inputs. Pub/Sub service APIs are managed; pin client libraries in the consuming project’s dependency lockfile.

## Delivery model

Each subscription receives messages published after it is created. The optional config at `~/.junie/custom/configs/infra/pubsub.toml` may set a delivery preference; absent a config, default to pull for a custom consumer. Select authenticated push for an HTTP consumer or an export subscription when a supported Google destination is preferable to custom processing.

Default behavior is at-least-once delivery without ordering guarantees. A message can be redelivered, including after an acknowledgement response, so handlers must be idempotent using a stable message/business key. Ordering requires ordering keys and compatible regional publishing/consumption. Exactly-once has API and subscription-type constraints; keep idempotency even when it is enabled.

## Create and secure resources

```bash
gcloud pubsub topics create "$TOPIC" --project="$PROJECT_ID"
gcloud pubsub subscriptions create "$SUBSCRIPTION" \
  --project="$PROJECT_ID" --topic="$TOPIC" \
  --ack-deadline="$ACK_DEADLINE_SECONDS" \
  --message-retention-duration="$RETENTION_DURATION"
```

Grant publisher permission only to authorized producers and subscriber permission only to consumers. For authenticated push to Cloud Run, use a dedicated push identity with `roles/run.invoker` on that service; do not grant public invocation to avoid configuring authentication.

## Retries and dead-letter routing

Set retry behavior and an explicit maximum delivery attempt policy for poison messages. Configure a separate DLQ topic and a restricted inspection subscription. The Pub/Sub service agent must have publisher access to the DLQ topic and subscriber access on the source subscription for dead-letter forwarding to work. Confirm that the service agent and both bindings target the correct project/resources.

Dead-letter forwarding is best-effort: attempts can differ from the configured delivery count, so do not treat the DLQ threshold as an exact processing guarantee. Alert on dead-letter count, oldest unacked age, backlog size, and subscriber errors.

## Retention, replay, and ordering

Choose message and subscription retention from recovery needs and cost. Topic retention is needed when a new subscription must replay older topic messages. `seek` changes which messages are delivered and can replay or skip data; inspect timestamp/snapshot and consumer idempotency before any use.

**Destructive/high impact:** deleting a topic removes its subscriptions and message history; deleting a subscription loses its backlog; `seek` can replay or skip messages; changing retention may expire unrecoverable data. Confirm the exact resource and user intent before acting.

## Operations

```bash
gcloud pubsub topics describe "$TOPIC" --project="$PROJECT_ID"
gcloud pubsub subscriptions describe "$SUBSCRIPTION" --project="$PROJECT_ID"
gcloud pubsub subscriptions pull "$SUBSCRIPTION" --project="$PROJECT_ID" --limit=5
```

Use pull inspection without auto-ack unless consuming/acknowledging is explicitly intended. Review backlog age, unacked message count, delivery latency, redelivery, and dead-letter metrics. Tune ack deadline and flow control from handler latency and concurrency measurements.

## Python event handler pattern

For Cloud Run functions, export the locked application dependencies from the project’s `uv.lock` into the runtime-supported format during the reviewed build; keep that generated file aligned with the lock. Use a stable Pub/Sub message/business identifier as an idempotency key, write structured logs without message payloads, and raise only for retryable failures.

```python
import base64
import json

import functions_framework
from cloudevents.http import CloudEvent


@functions_framework.cloud_event
def handle_event(event: CloudEvent) -> None:
    message = event.data["message"]
    payload = json.loads(base64.b64decode(message["data"]).decode("utf-8"))
    message_id = message["messageId"]
    process_idempotently(payload, message_id)
    print(json.dumps({"severity": "INFO", "message_id": message_id}))
```

Do not log full payloads. Use an outbox/deduplication record or transactional write when downstream effects must occur exactly once from the business perspective.

## Cloud Build boundary

Use Cloud Build for reviewable application/config validation, not to publish production business events as a side effect of a PR. Keep validation, artifact publishing, and release verification identities distinct; runtime publishers use their service identity and minimum topic permissions.

## References

- [Subscription overview](https://cloud.google.com/pubsub/docs/subscription-overview) — documentation last updated 2026-10-13; checked 2026-10-28.
- [Dead-letter topics](https://cloud.google.com/pubsub/docs/dead-letter-topics) — checked 2026-10-28.
- [Message ordering](https://cloud.google.com/pubsub/docs/ordering) — checked 2026-10-28.