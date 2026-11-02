# nginx and Traefik reverse-proxy operations

## Supported versions and defaults

Versions checked **2026-10-28** against official release pages:

| Software | Exact upstream version at check | Source |
|---|---|---|
| nginx stable | `1.30.6` | [nginx downloads](https://nginx.org/en/download.html) |
| Traefik | `v3.7.16` | [Traefik v3.7.16 release](https://github.com/traefik/traefik/releases/tag/v3.7.16) |

Prefer supported distro packages for nginx because distributions may backport security fixes. If deploying Traefik as a container, pin an exact tag and immutable digest; do not use a floating tag. The example config defaults to nginx unless the user selects Traefik or a team TOML policy overrides it. `preferred_proxy` selects `nginx` or `traefik`; keep `traefik_image_tag` aligned with the approved exact pin and set `nginx_release_track` only when using an upstream nginx repository.

## nginx HTTPS proxy pattern

Keep upstreams on private addresses or a local socket. Use the site's approved host, certificate, and service values; do not copy sample names or trusted-proxy CIDRs into production.

```nginx
upstream app_backend {
    server <private-upstream>:<port>;
    keepalive <approved-connection-count>;
}

server {
    listen 443 ssl;
    http2 on;
    server_name <approved-hostname>;
    ssl_certificate     <certificate-chain-path>;
    ssl_certificate_key <private-key-path>;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout <approved-timeout>;
        proxy_read_timeout <approved-timeout>;
    }
}
```

Use a separate port-80 ACME challenge location only when required by the approved certificate workflow; otherwise redirect to HTTPS. Trust forwarded client IP headers only from configured, verified load-balancer/CDN sources. Use `map` for conditional header/routing behavior rather than complex `if` directives inside `location` blocks.

## Rate limits and headers

Set per-client request/connection limits based on real-client identity and expected traffic. If all traffic appears to come from one proxy address, configure the real-IP module with only the actual upstream proxy ranges; trusting arbitrary `X-Forwarded-For` enables spoofing.

Apply security headers consistently and check nginx inheritance behavior when setting headers at `location` scope. Enable HSTS preload only after all applicable subdomains are HTTPS and the change is approved. Do not cache or log sensitive authorization headers.

## Traefik v3

Pin the deployment to `traefik:v3.7.16` plus its verified image digest. Prefer the file provider for static service definitions when feasible. If a container provider is necessary, do not mount the raw Docker socket; use a constrained socket proxy and disable automatic exposure.

Keep the dashboard private and authenticated. Store ACME state with strict filesystem permissions and a backup/recovery plan because it contains private key material. Use separate static and dynamic configuration and validate behavior before rollout.

## TLS and operations

Prefer the organization's certificate manager or distro-supported ACME client. Keep private key files out of repository content and logs. Use idempotent deploy hooks and a graceful reload only after certificate/config validation.

```bash
nginx -t
nginx -T
systemctl reload nginx
journalctl -u nginx --since '<approved-window>' -p warning
curl -sv -o /dev/null https://<approved-hostname>/<health-path>
```

For Traefik, validate configuration with the deployed image's supported CLI/options and inspect startup/configuration logs; do not assume nginx validation applies.

## Safety and troubleshooting

- HTTP reverse proxies do not terminate or route SIP signaling/RTP; use the appropriate SIP/L4 ingress design.
- Rate limiting, client-IP extraction, proxy timeouts, request-size limits, and WebSocket timeouts are application-specific runtime values.
- Keep admin APIs, stats, dashboards, ACME storage, and private keys inaccessible to public users.

| Symptom | Check |
|---|---|
| 502 | upstream address/port, DNS, service state, SELinux network-connect policy |
| 504 | upstream latency, timeout scope, backend logs |
| Wrong client IP | verified LB/CDN hops and real-IP trust configuration |
| WebSocket closes | upgrade headers, idle/read timeout, app ping behavior |
| Certificate renewal fails | challenge reachability, DNS CAA, deploy-hook logs |
| Traefik returns 404 | router match, provider load, service/entrypoint wiring |