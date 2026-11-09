---
name: dev-nginx-config-manage
description: "Author, review, refactor, and update nginx configuration files that live in a software project (nginx.conf, conf.d/*.conf, server/location/upstream blocks, snippets, Docker/Helm-mounted configs). Use when a task asks to add or change a route, reverse proxy an app, add redirects, headers, caching, gzip, rate limits, TLS settings, WebSocket/SSE support, auth, or CORS in nginx config, or to review an existing config for mistakes. Not for running benchmarks or live incident diagnosis (use infra-nginx-benchmark-run / infra-nginx-troubleshoot-run), not for Lua (use dev-openresty-config-manage), not for Apache, Caddy, HAProxy, or Traefik."
metadata:
  source: https://github.com/nejclovrencic/nginx-agent-skills
  author: Nejc Lovrencic (upstream), adapted
  license: MIT
---

# nginx configuration development (in-repo)

Scope: files committed to a project. The deliverable is a reviewable config diff plus the commands that prove it works. Live-host work is out of scope (see Related skills).

## Triggers

- Add/change `server`, `location`, `upstream`, `map`, `include` snippets for an app.
- Review a config for routing, inheritance, header, buffer, or security mistakes.
- Convert rewrite-heavy or `if`-heavy configs to idiomatic `map`/`return`/`try_files`.
- Add redirects, caching, gzip, CORS, rate limiting, basic auth, IP allow-lists, TLS, WebSocket/SSE proxying.
- Translate an nginx snippet found online into one valid for the project's nginx version.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project service topology (ports, upstream names, TLS termination point) and AGENTS.md if present
REQUIRE nginx version in use (Dockerfile tag, package pin, or `nginx -v`); default: assume the oldest supported in the project
REFERENCE "references/nginx-gotchas.md"
IF adding routes, redirects, auth, CORS, gzip, static caching, error pages, health endpoints
  REFERENCE "references/recipes.md"
IF tuning, rate limiting, TLS, buffers, upstream/keepalive, proxy caching, WebSockets
  REFERENCE "references/tuning-and-proxy-patterns.md"
IF dynamic key-value state is requested (feature flags, allow/deny lists, canary routing without reload)
  REFERENCE "references/keyval-and-dynamic-state.md"
IF validating or reloading
  REFERENCE "references/testing-patterns.md"
IF the config uses Lua (*_by_lua*, lua_*)
  REFERENCE skill "dev-openresty-config-manage"
IF unsure whether a directive/snippet is valid or current
  REFERENCE "references/sources.md"
CACHE only the directives and contexts relevant to the task
```

## Rules

1. Respect directive inheritance: a child block that redefines a directive discards all inherited values (one `proxy_set_header` in a `location` wipes the server-level set; same for `add_header`, `proxy_hide_header`, `proxy_set_header`).
2. Prefer `map`, `return`, and `try_files` over `if` and `rewrite`; in `location`, `if` is only safe with `return`/`rewrite ... last`.
3. Redirects: use a dedicated `server` block with `return 301 ...$request_uri;`, not a `rewrite` or `if ($host ...)` inside the main server.
4. State `proxy_pass` trailing-slash behavior explicitly (URI part replaces the matched prefix; variables disable replacement). Show a before/after request-path example in the PR description when changing it.
5. Every `upstream` gets `keepalive`, plus `proxy_http_version 1.1;` and `proxy_set_header Connection "";` in the proxying location (WebSocket locations use the `$connection_upgrade` map instead).
6. Verify every directive, its context, default, and the version it appeared in at <https://nginx.org/en/docs/> before using it; never invent directives. `keyval*` on nginx.org is NGINX Plus only (see keyval reference).
7. Never place a directive in an invalid context (`proxy_pass` in `http`, `worker_processes` in `server`, `limit_req_zone` in `server`).
8. Set `Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto` deliberately; trust client-supplied forwarded headers only from known proxy ranges (`set_real_ip_from` + `real_ip_header`).
9. Use `location` match order correctly: exact `=` > longest `^~` prefix > first matching regex > longest plain prefix; add a comment when order matters.
10. Copy snippets from old blogs/gists (including TLS cipher lists) only after checking them against current docs; use the Mozilla SSL generator for TLS (<https://ssl-config.mozilla.org/>).
11. Keep config DRY with `include snippets/*.conf` and `map`s at `http` level; one concern per snippet file.
12. Prefer comments that state *why* (e.g., "SSE: buffering off"), not what the directive does.

## Workflow

1. Map client → edge/LB → nginx → upstream, including TLS termination and trusted hops.
2. Inspect the current config (`nginx -T`), nginx version, listeners, and included files before editing.
3. Make the smallest reviewable change; keep project configs in the repo, not edited in place on a host.
4. Validate with `nginx -t` (or `docker run --rm -v ... nginx:<tag> nginx -t`); Lua errors only surface at runtime.
5. Prove behavior with `curl` cases for each changed route (status, `Location`, headers, body); see `references/testing-patterns.md` and the "Config test matrix" in `references/recipes.md`.
6. Reload gracefully (`nginx -s reload`/`systemctl reload nginx`); never restart to apply config.
7. For perf-impacting changes (buffers, keepalive, workers, caching), hand off to `infra-nginx-benchmark-run` instead of guessing numbers.

## Output checklist

- [ ] Directives valid in their context and for the target nginx version.
- [ ] Inheritance reset audited (headers re-declared where a child block adds one).
- [ ] `nginx -t` output included; curl expectations listed.
- [ ] No secrets, private keys, or internal-only hostnames added.
- [ ] Rollback note: previous config revision and reload command.

## Safety

- Ask before reloading production nginx or changing TLS/access policy.
- Keep `server_tokens off;`; never expose `stub_status`, debug, or admin locations without `allow`/`deny` or auth.
- Do not commit private keys or `ssl_certificate_key` material.
- Basic-auth password files hold secrets: reference them by path, never inline.

## Related skills

- Running load tests/benchmarks of a config → `infra-nginx-benchmark-run`
- Live diagnosis (502/504, FD exhaustion, logs, kernel counters) → `infra-nginx-troubleshoot-run`
- OpenResty/Lua handlers → `dev-openresty-config-manage`
- Generic nginx/Traefik proxy operations → `infra-nginx-reverseProxy-manage`
- Certificate lifecycle → `sec-tls-acme-manage`, `sec-tls-config-audit`

## References

- [references/nginx-gotchas.md](references/nginx-gotchas.md) — directive behavior, inheritance, location matching, buffers (upstream, MIT).
- [references/recipes.md](references/recipes.md) — copy-ready, version-checked snippets with a curl test per recipe.
- [references/tuning-and-proxy-patterns.md](references/tuning-and-proxy-patterns.md) — worker/kernel tuning, upstream keepalive, rate limiting, TLS, caching, SSE/WebSockets.
- [references/keyval-and-dynamic-state.md](references/keyval-and-dynamic-state.md) — `ngx_http_keyval_module` (Plus) vs kjdev/nginx-keyval (OSS), `lua_shared_dict` alternative.
- [references/testing-patterns.md](references/testing-patterns.md) — validation and reload behavior (upstream, MIT).
- [references/sources.md](references/sources.md) — vetted sources with trust notes.
