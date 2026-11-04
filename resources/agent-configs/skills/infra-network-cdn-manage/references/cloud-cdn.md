# Google Cloud CDN

## Choose an origin

Use a backend bucket for static content served from GCS; use a backend service for dynamic HTTP(S) origins that explicitly support caching. Cloud CDN is not for SIP/RTP. Keep the origin private when supported by the selected topology and organization policy; bucket access controls remain owned by the storage skill.

Inspect the backend, cache enablement, logging, cache mode, cache key, signed-access configuration, and origin response headers before changing behavior. Use the project's GCP/IaC conventions rather than creating duplicate frontend resources.

## Cache policy

| Content type | Recommended origin behavior |
|---|---|
| Content-hashed static assets | Long-lived public caching; change the asset name when content changes |
| HTML/manifests | Revalidate or short-lived caching to pick up releases |
| User-specific/authenticated response | `private` or `no-store`; exclude from shared caching |
| API response | Cache only with an explicit authorization and cache-key design |

For backend services, prefer origin-controlled caching unless the content is proven public and static. Never force-cache a private or authenticated response. Include only query parameters/headers that actually change the representation in the cache key; avoid cookie/user identity leakage.

## Configure and verify

```bash
gcloud compute backend-buckets describe <backend-bucket>
gcloud compute backend-services describe <backend-service> --global
gcloud compute backend-buckets update <backend-bucket> --enable-cdn
```

Use supported cache modes and resource scope for the selected GCP backend. Review Cloud Armor interaction, origin authentication, URL map, and TLS frontend before applying. Confirm IaC ownership and review its plan before live changes.

Verify response metadata and cache behavior:

```bash
curl -sI https://<approved-host>/<asset>
```

Check `Cache-Control`, `Age`, cache status headers where exposed, request logs, cache lookup/hit metrics, and origin logs. Test both expected cacheable content and a private/non-cacheable response.

## Signed access and invalidation

Use signed URLs/cookies only for content that must remain private. Generate/sign with the approved identity/key process, keep key material in the designated secret store, set a bounded validity window, and never include signed URL values in tickets or logs.

Prefer content-hashed asset names; invalidate only HTML/manifests or a narrow approved path when needed. Broad invalidation is rate-limited and can create an origin load spike. Preview the exact paths and confirm the release order before invalidating.

## Troubleshooting

| Symptom | Check |
|---|---|
| Always a cache miss | origin headers, cache mode, `Set-Cookie`, cache-key cardinality |
| Stale release content | content-hashed names, HTML policy, invalidation scope |
| Private data appears cached | cache mode, authorization, `private`/`no-store`, cache key; disable and purge urgently |
| Backend bucket returns 403 | object IAM, signed-access expiry/key, origin policy |
| CORS responses are wrong | `Vary: Origin`, preflight behavior, allowed cache-key headers |

CloudFront, Cloudflare, and other CDN products are outside this GCP-specific reference; use their dedicated provider guidance.