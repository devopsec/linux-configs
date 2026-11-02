---
name: infra-network-cdn-manage
description: "Configure Google Cloud CDN for public or private HTTP content, backend buckets/services, cache keys, cache headers, signed access, and invalidation. Use when a task mentions Cloud CDN, cache hits, cache-control, backend buckets, CDN signed URLs, or invalidation."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/networking/cdn-setup]
  license: MIT
---

# Google Cloud CDN management

## Triggers

- Enable or troubleshoot Cloud CDN on a backend bucket or backend service.
- Design cache keys, origin `Cache-Control`, signed access, or cache invalidation.
- Investigate stale, private, uncached, or unexpectedly expensive cached responses.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project content-classification and release policy if present
REFERENCE "references/cloud-cdn.md"
IF the origin is a GCS bucket
  REFERENCE skill "infra-gcp-gcs-manage"
IF edge resources are declared in OpenTofu/Terraform
  REFERENCE the matching IaC skill and inspect its plan before live changes
CACHE only the origin, cache-key, signed-access, or invalidation guidance needed
```

## Workflow

1. Identify origin type, public/private data, request methods, cookies/query parameters, cacheability, and regional requirements.
2. Inspect backend, cache mode, cache key, origin response headers, signed-access policy, and logs before changing behavior.
3. Cache only explicitly safe content; isolate user-specific responses and avoid force-caching dynamic/private data.
4. Prefer versioned asset names and narrow invalidations; stage configuration through IaC when present.
5. Verify response headers, cache status, origin reachability, and private-data isolation after rollout.

## Safety

- Never cache personalized or credential-bearing responses in a shared cache without a proven cache-key and authorization design.
- Keep storage origins private where possible; public access and invalidation of broad paths require explicit review.
- Do not route SIP or RTP through an HTTP CDN.

## Related skills

- GCS bucket security and object access → `infra-gcp-gcs-manage`
- GCP load balancer and backend services → `infra-network-loadBalancer-manage`
- nginx/Traefik origin configuration → `infra-nginx-reverseProxy-manage`
- Other CDN providers → their provider-specific skill or official documentation (outside this skill's scope)
- Infrastructure as code → `infra-opentofu-any-manage`, `infra-terraform-any-manage`

## References

- [references/cloud-cdn.md](references/cloud-cdn.md) — Cloud CDN origins, cache modes, headers, signed access, and invalidation.
