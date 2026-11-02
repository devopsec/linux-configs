# Cloud Run and Cloud Run functions

The project, region, runtime, image digest, service account, instance limits, timeout, ingress, and VPC path are runtime inputs. Keep CI validation separate from production deployment and data mutation.

## Choose the execution model

| Workload | GCP service |
|---|---|
| Containerized HTTP service, multiple routes, or custom runtime | Cloud Run service |
| One source-based event handler | Cloud Run functions, second generation |
| Finite batch task with explicit completion | Cloud Run job |
| Long-running stateful or protocol-sensitive service | Compute Engine or GKE after architecture review |

Do not start new deployments on legacy first-generation Cloud Functions. Use Eventarc for supported event sources and Pub/Sub for message-driven work; see `infra-gcp-pubsub-manage` for delivery, acknowledgements, and DLQs.

Cloud Run functions runtime `python313` was confirmed supported in Google’s runtime support documentation on 2026-10-28. Pin the runtime label and application dependencies; review retirement dates before changing runtime generations.

## Identity and ingress

- Create distinct build, runtime, and invoker identities. The runtime identity receives only the data/API roles the code needs; the invoker gets `roles/run.invoker` on the service.
- Require authentication by default. Never use `allUsers` on event-processing services unless the endpoint is intentionally public and has a reviewed edge control.
- Keep credentials out of environment values, build logs, source archives, and command history. Use Secret Manager references or workload identity.
- Scope ingress to internal or load-balancer paths unless a public endpoint is explicitly required.

## Deploy and network

Deploy source functions through a reviewed build path; deploy container services from an immutable Artifact Registry digest. Make build service-account permissions explicit and separate validation-only builds from publishing identities.

```bash
gcloud run deploy "$SERVICE" --project="$PROJECT_ID" --region="$REGION" \
  --image="$IMAGE_URI@$IMAGE_DIGEST" \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" \
  --no-allow-unauthenticated --ingress=internal \
  --max-instances="$MAX_INSTANCES" --concurrency="$CONCURRENCY"
```

Use Direct VPC egress where supported; otherwise use a Serverless VPC Access connector with an allocated, non-overlapping range. Configure egress mode intentionally, and confirm route, DNS, firewall, and target service access. For Cloud SQL, follow the Cloud SQL reference.

## Reliability and operations

- Set explicit timeout, concurrency, max instances, minimum instances when latency requires it, and CPU/memory based on load tests.
- Event handlers must be idempotent because event delivery can repeat. Configure retries and failure routing at the trigger/subscription boundary.
- Use revision traffic controls for gradual deployment and retain a known-good revision for rollback.
- Inspect service description, revision readiness, logs, and metrics before moving traffic.

```bash
gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION"
gcloud run services update-traffic "$SERVICE" --project="$PROJECT_ID" \
  --region="$REGION" --to-revisions="$KNOWN_GOOD_REVISION=100"
```

Cloud Build integration follows the repository’s generic separation pattern: PR validation identities publish nothing, publisher identities have only artifact-write access, and release verifiers are read-only. Never grant a validation build production runtime or data-write permission merely for convenience.

**Destructive/high impact:** deleting a service, removing a revision, changing ingress, or moving all traffic affects live requests. Inspect exact targets and request approval.

## References

- [Cloud Run documentation](https://cloud.google.com/run/docs) — checked 2026-10-28.
- [Cloud Run functions documentation](https://cloud.google.com/functions/docs) — checked 2026-10-28.