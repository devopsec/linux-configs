# LiteLLM gateway, routing, and cost policy

Version checked 2026-10-28: LiteLLM `v1.106.4`, published October 25 after the October 21 incident and shown as the latest stable release in the official release list. Upstream reported `v1.107.0` and floating tags pointing to compromised artifacts; do not use `v1.107.0`, `latest`, `main-stable`, or `main-latest`. Treat any newer package/image as unapproved until trusted publisher advisories and signature provenance are reviewed.

## Minimal private proxy configuration

```yaml
model_list:
  - model_name: <stable-alias>
    litellm_params:
      model: hosted_vllm/<served-model>
      api_base: os.environ/VLLM_API_BASE
      api_key: os.environ/VLLM_API_KEY
  - model_name: <vertex-alias>
    litellm_params:
      model: vertex_ai/<approved-model-id>
      vertex_project: os.environ/GCP_PROJECT
      vertex_location: os.environ/GCP_REGION

router_settings:
  routing_strategy: least-busy
  num_retries: 2
  allowed_fails: 2
  cooldown_time: 60
  fallbacks: [{<primary-alias>: [<fallback-alias>]}]

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
```

Keep gateway, database, and cache endpoints private. Load provider and master keys from Secret Manager or an approved secret injector; never place literal keys in YAML. For Vertex AI, use the workload identity/ADC path and runtime project/region rather than a service-account key. Use Cloud SQL PostgreSQL over Auth Proxy/private IP for the gateway database, a non-root image variant where available, and mirror the verified image into an approved registry.

## Version and supply-chain gate

Before deployment, verify the selected image signature with a trusted public key from the release notes and inspect the publisher's incident/advisory page. Pin the full version and digest. If `v1.107.0` ran in an environment, isolate it, remove the artifact, rotate credentials accessible to that environment, and investigate outbound activity before restoring service.

```bash
cosign verify --key '<trusted-release-public-key>' ghcr.io/berriai/litellm:v1.106.4
```

## Keys, budgets, routes

- Issue one virtual key per application/team; limit its allowed models, RPM/TPM, and budget. Deliver it through a managed secret store.
- Keep the master key operator-only. Test key revocation, fallback behavior, backend timeouts, and budget enforcement.
- Use explicit distinct model aliases for fallback targets; duplicate aliases can load-balance rather than fail over.
- Prefer provider/gateway cost metadata or an approved negotiated-rate file over hardcoded price constants. Unknown model costs must be surfaced, not recorded as zero.

## Tenant isolation and spend attribution

| Tier | Boundary |
|---|---|
| Shared | Authenticated gateway virtual key, per-team model allowlist/RPM/TPM/budget, tenant-prefixed cache keys. |
| Dedicated namespace | Separate Kubernetes namespace, `NetworkPolicy`, GPU `ResourceQuota`, and priority controls. |
| Dedicated pool/project | Separate node pool or GCP project, CMEK, and separate logs/billing boundary for contractual isolation. |

Always derive tenant identity from the verified key, never a free-form request header; partition logs/retention and audit admin actions. Prefer LiteLLM's teams/virtual keys over a custom router. Do not use an unreviewed custom router that accepts but fails to verify a key, races concurrency check/increment, omits TPM enforcement, or breaks stream/error handling.

Tag approved usage events by team/service/model and export to BigQuery for spend attribution; join with GCP billing export for GPU/VM cost. Use gateway budgets as hard limits and Cloud Monitoring/Prometheus as warnings. Do not put tenant-specific IDs, rates, or thresholds into this generic default config.

## Cache and streaming policy

Enable exact caching only for approved deterministic calls; semantic caching only for suitable FAQ/support tasks after labelled quality tests. Include tenant, model, prompt version, and relevant generation parameters in the cache key/filter. Never cache PII, tool results, or data whose retention policy disallows storage. Invalidate by source/prompt version, not TTL alone. Keep streaming intact (`proxy_buffering off` on proxies) and do not enable verbose prompt/header debug logs in production.

Use exact request caching for identical deterministic requests, semantic caching only for non-user-specific FAQ/support flows, and provider prompt caching for repeated static prefixes. Start semantic similarity thresholds around `0.90` only as a labelled-test baseline; tune against false hits. Keep cache-only Redis isolated from rate-limit/billing Redis, with bounded memory and no persistence if policy permits.

Cost levers: route simple classification/extraction to a smaller model, trim history/context, batch eligible offline work, and measure exact/provider cache savings. Self-hosting break-even must include 24×7 GPU cost, high availability, operations, and idle capacity; compare against current negotiated rates.

## Validate

Test health, each backend route, fallback during a controlled failure, virtual-key isolation, budget/rate-limit rejection, cache hit/miss boundaries, and SSE streaming. Use spend alerts for early warning and gateway budgets for hard limits. Nginx-only balancing is not a replacement for gateway authentication/budget enforcement; use the generic reverse-proxy skill for that configuration.