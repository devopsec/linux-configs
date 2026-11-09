# LuaJIT-friendly rules for OpenResty hot paths

Measure first (flame graph or `infra-openresty-profile-run`); apply these only to code that profiling shows is hot. Statements below were checked against the LuaJIT NYI table (Tarantool wiki "LuaJIT Not Yet Implemented", which tracks upstream LuaJIT 2.1 and notes where OpenResty's `luajit2` fork differs).

## Corrections to common advice

| Claim (seen in AI/blog advice) | Reality per NYI table |
|---|---|
| "`pcall`/`xpcall` abort traces" | Compiled (`pcall`, `xpcall` = yes). Use them for error handling; do not contort code to avoid them |
| "`pairs()` is NYI" | `pairs` and `ipairs` are compiled; `next()` is compiled in LuaJIT 2.1 upstream (check the OpenResty luajit2 version in use) |
| "string concat in loops is only slow" | `..` compiles (CAT), but allocates; build large strings with `table.concat` (compiled) |
| "`string.format` is always NYI" | Partially compiled: not for `%p` or non-string args to `%s` |
| "`string.gsub`/`unpack` are NYI" | "stitch" support in 2.1: compiled via a trace stitch, slower than a native trace |
| "`string.find` with patterns is fast" | Only *plain* searches (`string.find(s, p, 1, true)`) are compiled |

## Rules

- Use `local` for functions and modules (`local ngx_var = ngx.var`); global lookups are slower and unsafe across requests.
- Cache hot `ngx.*` function references at module load, not inside request code.
- Avoid string concatenation in loops; collect into a table and `table.concat`. Reuse tables with `table.new`/`table.clear` (`require "table.new"`, `require "table.clear"`).
- Prefer `string.find(s, pat, 1, true)` (plain) when no pattern is needed; use `ngx.re.match(..., "jo")` (JIT PCRE + compile-once cache) for regexes. Avoid Lua patterns (`string.match`, `gmatch`) on hot paths.
- Do not create closures per request in hot paths; hoist them to module level.
- Keep `ffi.cdef` declarations at module load, never per request; use `ffi` only via well-tested bindings (`lua-resty-core` pattern).
- Reuse connections: `set_keepalive` on every cosocket client, or use a pooled library.
- `lua_code_cache on;` in production; `off` reloads Lua per request and reruns `init_by_lua` (dev only).
- Keep shared dict calls few per request: `dict:get` copies the value into a Lua string; store compact values; avoid `get_keys` (locks the zone, O(n)).
- Avoid very large Lua tables in per-worker memory: LuaJIT 2.1 GC limit is 2 GB total on x86-64 without GC64; check the build flavor.

## How to find trace aborts

```bash
# resty CLI with the JIT verbose/profiler modules (dev only)
resty -j v -e 'for i=1,1e6 do local x = tostring(i) end' 2>&1 | grep -i -E 'abort|NYI' | head
# or load the module inside a content handler, run load, then read stderr
# LuaJIT: jit.v / jit.dump / jit.p (see luajit.org/running.html); OpenResty: -j flags require a LuaJIT built with them
```

For production-grade evidence use OpenResty XRay/flame graphs or `perf` + stapxx/openresty-systemtap-toolkit (see `infra-openresty-profile-run`), not guesses.
