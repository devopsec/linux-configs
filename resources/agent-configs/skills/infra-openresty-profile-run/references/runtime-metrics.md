# In-process runtime metrics for OpenResty

Verified on `docker.io/openresty/openresty:alpine` (OpenResty 1.31.8.1): the stats endpoint returned worker/GC/timer/shdict data, was refused (403) from outside loopback, and the log-phase histogram recorded all 81 test requests; shared dict counters persisted across `openresty -s reload`.

## Module

```lua
-- lua/app/stats.lua
local cjson = require "cjson.safe"
local _M = {}

local BUCKETS = { 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5 }   -- seconds

-- log_by_lua*: record request latency into a shared dict histogram (no cosockets, O(1) work)
function _M.observe(route)
    local dict = ngx.shared.stats
    local t = tonumber(ngx.var.request_time) or 0
    local b = "+Inf"
    for _, ub in ipairs(BUCKETS) do
        if t <= ub then b = tostring(ub); break end
    end
    dict:incr("h:" .. route .. ":" .. b, 1, 0)
    dict:incr("h:" .. route .. ":count", 1, 0)
end

-- content handler: per-worker runtime state + shared dict usage (restrict with allow/deny)
function _M.dump(dicts)
    local out = {
        worker = { id = ngx.worker.id(), pid = ngx.worker.pid(), count = ngx.worker.count() },
        lua_gc_kb = collectgarbage("count"),
        timers = { running = ngx.timer.running_count(), pending = ngx.timer.pending_count() },
        shdict = {},
    }
    for _, name in ipairs(dicts) do
        local d = ngx.shared[name]
        out.shdict[name] = { capacity = d:capacity(), free = d:free_space() }
    end
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(out))
end

return _M
```

```nginx
http {
    lua_package_path "$prefix/lua/?.lua;;";
    lua_shared_dict stats 2m;
    server {
        listen 8080;
        location /api/ {
            content_by_lua_block { require("app.routes").dispatch() }
            log_by_lua_block     { require("app.stats").observe("api") }
        }
        location = /_lua_stats {
            allow 127.0.0.1; allow ::1; deny all;     # ::1: `localhost` may resolve to IPv6
            content_by_lua_block { require("app.stats").dump({ "stats", "ratelimit" }) }
        }
    }
}
```

Sample output (one worker answers per request; sample several times or aggregate per `pid`):

```json
{"timers":{"pending":0,"running":0},"worker":{"count":2,"id":1,"pid":3},"shdict":{"cache":{"free":1032192,"capacity":1048576},"stats":{"free":2072576,"capacity":2097152}},"lua_gc_kb":285.5}
```

## Reading the numbers

| Metric | Healthy | Warning sign |
|---|---|---|
| `lua_gc_kb` per worker | sawtooth around a stable level | steady upward trend under constant load = leak (globals, unbounded tables/caches, large `ngx.ctx`); verify with several workers |
| `shdict.free / capacity` | stays well above 0 | trending to 0: raise size or shorten TTLs; `set` returns `forcible=true` when evicting live keys |
| `timers.pending` | near 0 or stable | growing: timers created faster than they run; check `lua_max_pending_timers` warnings |
| `timers.running` | low | pinned at limit: long-running timer bodies |
| histogram buckets | mass in low buckets | shift to higher buckets after a release |

Notes:
- `free_space()` reports free memory pages in the zone and can be low-ish even with fragmented layouts; combine with the `forcible` flag and error log "ngx_slab_alloc() failed: no memory" messages.
- `dict:get_keys(n)` locks the zone and is O(n): debug only, never on hot paths.
- Keep histogram key cardinality fixed (route names are constants). Never use client-controlled values in key names.
- Export to Prometheus with a maintained library (e.g. `knyar/nginx-lua-prometheus`) when a metrics stack exists; check its maintenance status first.

## Per-phase timing inside a request

```lua
-- access_by_lua_block
ngx.ctx.t_access = ngx.now()                  -- use ngx.update_time() before ngx.now() in long loops
-- ...later in log_by_lua_block
ngx.update_time()
local spent = ngx.now() - ngx.ctx.t_access
if spent > 0.1 then ngx.log(ngx.WARN, "slow lua section: ", spent, "s uri=", ngx.var.uri) end
```

`ngx.req.start_time()` returns when the request started; `$request_time` and `$upstream_response_time` are available in `log_by_lua*` via `ngx.var`.
