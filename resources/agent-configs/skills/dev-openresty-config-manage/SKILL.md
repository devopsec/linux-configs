---
name: dev-openresty-config-manage
description: "Author, review, and update OpenResty / lua-nginx-module code and config that live in a software project: *_by_lua_block handlers, Lua modules loaded via lua_package_path, lua_shared_dict, init_by_lua/init_worker_by_lua, ssl_certificate_by_lua, API gateway logic, JSON handling (lua-cjson), lua-resty-* libraries, ngx.log. Use when a task mentions OpenResty, ngx.* Lua API, ngx.shared, ngx.ctx, access_by_lua, content_by_lua, resty CLI, or Lua inside nginx. Not for plain nginx config without Lua (use dev-nginx-config-manage), not for load tests or live profiling (use infra-openresty-profile-run / infra-nginx-benchmark-run)."
metadata:
  source: https://github.com/nejclovrencic/nginx-agent-skills
  author: Nejc Lovrencic (upstream), adapted
  license: MIT
---

# OpenResty / Lua development (in-repo)

Scope: Lua modules and nginx config committed to a project. Operations (benchmark, flame graphs, live debugging) live in the infra skills.

## Triggers

- Write or fix Lua running inside nginx/OpenResty (any `*_by_lua*` directive or `lua_*` setting).
- Add auth, rate limiting, routing, header logic, or a small API at the proxy layer in Lua.
- Add dynamic TLS (`ssl_certificate_by_lua*`), shared-memory state, timers, or JSON endpoints.
- Review Lua handlers for blocking calls, globals, phase misuse, or JIT-hostile code.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project proxy topology and AGENTS.md if present
REQUIRE OpenResty version (`openresty -v` / Dockerfile tag) and LuaJIT flavor; default: assume the oldest supported in the project
REFERENCE "references/openresty-api.md"
REFERENCE skill "dev-nginx-config-manage" for server/location/upstream parts
IF writing handlers, shared dicts, JSON, TLS, gateway patterns, logging
  REFERENCE "references/examples.md"
IF installing OpenResty, adding libraries (opm/luarocks), setting lua_package_path, or running scripts with `resty`
  REFERENCE "references/install-and-modules.md"
IF performance or hot-path work
  REFERENCE "references/luajit-performance.md"
IF unsure whether an API/library exists or is maintained
  REFERENCE "references/sources.md"
CACHE only the phase and API sections relevant to the task
```

## Rules

1. Check **phase restrictions** before using cosocket, subrequest, or `ngx.say`/`ngx.print` APIs; each API's doc lists its allowed contexts (consult the availability table in `references/openresty-api.md`).
2. Never block the event loop: no `os.execute`, `io.popen`, blocking file I/O, or LuaSocket; use `lua-resty-*` cosocket libraries and `ngx.timer.at` for background work. Cosockets need a `resolver` for hostnames.
3. Pass data between phases with `ngx.ctx`; read `ngx.var.*` once into a local rather than repeatedly.
4. Declare modules and functions `local`; globals persist across requests in a worker (leaks and races). Put code in modules under `lua_package_path`, keep `*_by_lua_block` bodies as thin calls.
5. `init_by_lua*` runs once in the master on every config load/reload (COW-shared; good for `require` preloading and config parsing); per-worker state and timers belong in `init_worker_by_lua*`. `lua_shared_dict` contents survive a reload, so guard one-time seeding with a flag key.
6. Size shared dicts deliberately (`lua_shared_dict name 10m;`, minimum 8 KB). `set` evicts by LRU when full and returns `forcible=true`; use `safe_set` (returns `nil, "no memory"`) when eviction is wrong; always check return values. Use `incr(key, 1, 0, ttl)` for atomic counters.
7. Log with explicit levels (`ngx.ERR`, `ngx.WARN`, `ngx.NOTICE`, `ngx.INFO`, `ngx.DEBUG`); lines are truncated at 2048 bytes; never log secrets, tokens, or full auth headers. `ngx.log(ngx.ERR, ...)` is the only structured sink available in every phase.
8. Wrap fallible work (`cjson.decode`, cosocket calls) in `pcall`/error checks and return the right HTTP status (400 bad body, 405 wrong method with `Allow`, 500 only for server faults).
9. JSON: use the bundled `cjson` (OpenResty ships it; do not install a second copy). `cjson.null` for JSON null, `cjson.empty_array` for `[]`; mind sparse-array and number-precision limits.
10. Lua has no `switch`; use a table of handlers keyed by value (see examples) instead of long `if/elseif` chains.
11. Reuse connections: call `set_keepalive` on every cosocket client after use; configure `lua_socket_pool_size`/`keepalive` deliberately.
12. Phase order matters for plain directives too: `return`/`rewrite` run in the rewrite phase, before `access_by_lua*`, so an access-phase check next to a `return` never executes (verified); and `init_worker_by_lua*` runs as the unprivileged worker user, so files it reads must be readable by that user.
13. Auto-issued certificates: `lua-resty-auto-ssl` is marked abandoned upstream; prefer an actively maintained ACME client plus `ssl_certificate_by_lua` only when per-SNI cert selection is truly required.

## Workflow

1. Identify the phase the logic must run in and check API availability for it.
2. Implement in a Lua module under the project (loaded via `lua_package_path`); keep `*_by_lua_block` thin.
3. `nginx -t` / `openresty -t` (does not catch Lua runtime errors), then exercise the Lua path with real requests (`curl`) while watching the error log at `info`/`debug`.
4. Add tests: `Test::Nginx` (`.t` files) or `busted` + `resty` CLI when the project uses them; otherwise scripted `curl` cases for success and each failure path (bad JSON, wrong method, missing header, dict full).
5. For hot-path changes, hand off to `infra-openresty-profile-run` and `infra-nginx-benchmark-run`.
6. Reload gracefully; confirm `lua_code_cache on;` in production (off is dev-only and reruns `init_by_lua` per request).

## Output checklist

- [ ] Every ngx API used is valid in its phase.
- [ ] No blocking calls, no new globals; `local` everywhere.
- [ ] Shared dict names/sizes declared; return values checked.
- [ ] Error paths return correct HTTP status and log at the right level without secrets.
- [ ] `nginx -t` + curl evidence for success and failure cases.

## Safety

- Validate and bound all request-derived input before using it in `ngx.redirect`, `ngx.exec`, shared dict keys, upstream selection, or file paths.
- Never log secrets, tokens, or full auth headers; bound key cardinality in shared dicts (client-controlled keys can exhaust memory).
- Admin/status endpoints implemented in Lua need explicit access control.
- Ask before production reloads.

## Related skills

- nginx server/location/upstream configuration and tuning → `dev-nginx-config-manage`
- Profiling/flame graphs/live debugging of OpenResty → `infra-openresty-profile-run`
- Load testing and benchmarking → `infra-nginx-benchmark-run`
- Generic reverse proxy operations → `infra-nginx-reverseProxy-manage`

## References

- [references/openresty-api.md](references/openresty-api.md) — phases, API availability by phase, shared dicts, body handling, subrequests, ngx.ctx vs ngx.var (upstream, MIT).
- [references/examples.md](references/examples.md) — worked, doc-checked examples: init/preload, shared dict counters, rate limit, API router, JSON, dynamic TLS, timers, logging.
- [references/install-and-modules.md](references/install-and-modules.md) — install (Deb packages), project layout, `resty` CLI, opm/luarocks, `lua_package_path`.
- [references/luajit-performance.md](references/luajit-performance.md) — LuaJIT-friendly coding rules for hot paths (NYI-list-checked).
- [references/sources.md](references/sources.md) — vetted sources with trust notes.
