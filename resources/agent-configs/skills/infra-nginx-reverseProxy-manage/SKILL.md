---
name: infra-nginx-reverseProxy-manage
description: "Configure and operate nginx or Traefik HTTP reverse proxies, TLS termination, upstreams, WebSockets, headers, and rate limits. Use when a task mentions proxy_pass, nginx, Traefik, 502/504, upstream health, WebSocket proxying, or reverse-proxy TLS."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/networking/reverse-proxy]
  license: MIT
---

# nginx and Traefik reverse proxies

## Triggers

- Create or troubleshoot nginx/Traefik HTTP(S) proxy routes, upstreams, headers, or WebSockets.
- Configure proxy TLS certificates, health checks, client IP handling, or rate limits.
- Diagnose a proxy-generated 4xx/5xx response or reload failure.

## Defaults

Prefer the supported distro nginx package. If Traefik is selected, pin `v3.7.16` (checked `2026-10-28`) and an immutable image digest; never use a floating tag.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project service topology and AGENTS.md if present
IF file exists "~/.junie/custom/configs/infra/reverse-proxy.toml"
  REFERENCE that file for the preferred proxy and defaults
ELSE
  use defaults listed here
REFERENCE "references/reverse-proxy.md"
IF the proxy terminates or renews certificates
  REFERENCE skill "sec-network-tls-manage"
CACHE only the relevant proxy and runtime configuration
```

## Workflow

1. Map client → edge/load balancer → proxy → upstream, including trusted proxy hops and protocol requirements.
2. Inspect active configuration, package/container version, listeners, logs, and upstream health before editing.
3. Use the configured default proxy unless the user selects another supported option; write minimal, reviewable configuration.
4. Validate with `nginx -t` or the installed Traefik configuration checks, then perform a graceful reload and health test.
5. Verify client IP, TLS chain, cache/header behavior, WebSocket timeouts, and application logs.

## Safety

- Never place SIP signaling or RTP behind an HTTP reverse proxy; use the dedicated SIP/L4 path.
- Do not trust `X-Forwarded-For` from arbitrary clients; allow only configured proxy/LB ranges.
- Protect ACME private keys and proxy dashboards; expose administrative endpoints only through authenticated private paths.
- Pin container images to an exact tag or digest; do not use `latest`.

## Related skills

- GCP load balancers → `infra-network-loadBalancer-manage`
- DNS records and ACME challenge delegation → `infra-gcp-cloudDns-manage`
- Certificate lifecycle and TLS policy → `sec-network-tls-manage`
- Container runtime/socket isolation → `infra-container-any-manage`
- SIP services → `dev-kamailio-platform-manage`

## References

- [references/reverse-proxy.md](references/reverse-proxy.md) — nginx and Traefik configuration, security, TLS, and operations.
