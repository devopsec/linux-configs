# OpenResty worked examples

Checked against the lua-nginx-module README (shared dict, `init_by_lua_block`, log constants, `ngx.log`, `ssl_certificate_by_lua_block`), lua-resty-core `ngx.ssl`, and lua-cjson docs. Adjust to the OpenResty version in use.

Sections 1, 2, 3, 4, 5, 6 and 8 were executed on `openresty/openresty:alpine` (OpenResty 1.31.8.1) and produced the documented results; sections 7, 9, 10, 11 are unexecuted patterns. Run each through `openresty -t` and the listed curl test.

## 1. Project layout and `init_by_lua_block`

```
conf/nginx.conf
lua/app/router.lua
lua/app/ratelimit.lua
lua/app/certs.lua
t/                       # Test::Nginx files
```

```nginx
http {
    lua_package_path "$prefix/lua/?.lua;;";       # `;;` keeps the default path
    lua_shared_dict ratelimit 10m;
    lua_shared_dict flags     1m;

    init_by_lua_block {
        -- runs in the master on every config load/reload; COW-shared with workers.
        require "cjson"                    -- preload C modules (see lua-nginx-module docs)
        require "app.router"
        local flags = ngx.shared.flags
        if not flags:get("seeded") then    -- shm survives reload: seed once
            flags:set("maintenance", false)
            flags:set("seeded", true)
        end
    }
}
```

Test: `openresty -t && openresty -s reload`; with `lua_code_cache off` `init_by_lua` reruns per request (dev only).

## 2. Shared dict operations

```lua
local dict = ngx.shared.ratelimit

-- atomic counter with initial value and TTL (init_ttl needs lua-resty-core, on by default in current OpenResty)
local n, err = dict:incr("ip:" .. ip, 1, 0, 60)
if not n then
    ngx.log(ngx.ERR, "ratelimit incr failed: ", err)      -- "no memory" or other error
    return                                                -- fail open (or closed) deliberately
end

-- set: LRU-evicts valid entries when full; check forcible
local ok, err, forcible = dict:set("k", "v", 300)
if not ok then ngx.log(ngx.ERR, "set failed: ", err) end
if forcible then ngx.log(ngx.WARN, "ratelimit dict evicting live keys: enlarge it") end

-- safe_set: never evicts valid entries, returns nil, "no memory" instead
local ok, err = dict:safe_set("k", "v", 300)

-- add: only if absent (poor-man's lock/once)
local added = dict:add("job:lock", 1, 30)
```

- `incr` returns `nil, "not found"` when the key is missing and no `init` is given, `nil, "not a number"` for non-numeric values.
- Values may be booleans, numbers, strings, or nil; `exptime=0` never expires; `flush_expired` frees expired slots; `get_keys` is O(n) and locks the zone: avoid it on hot paths.
- Every key is shared by all workers, so each op is atomic per call but multi-step logic is not; use `add`/`incr` for check-and-set.

## 3. Fixed-window rate limiter (`access_by_lua_block`)

```lua
-- lua/app/ratelimit.lua
local _M = {}
local dict = ngx.shared.ratelimit

function _M.check(key, limit, window)
    local count, err = dict:incr(key, 1, 0, window)
    if not count then
        ngx.log(ngx.ERR, "ratelimit: ", err)
        return true                          -- fail open on dict errors
    end
    return count <= limit, count
end

return _M
```

```nginx
location /api/ {
    access_by_lua_block {
        local rl = require "app.ratelimit"
        local ok = rl.check("ip:" .. ngx.var.binary_remote_addr, 100, 60)
        if not ok then
            ngx.header["Retry-After"] = "60"
            return ngx.exit(429)
        end
    }
    proxy_pass http://app;
}
```

Test: `for i in $(seq 1 120); do curl -s -o/dev/null -w '%{http_code}\n' $H/api/; done | sort | uniq -c` → 100 x 200, 20 x 429 (verified, with `Retry-After: 60` on the 429). For production-grade limiting prefer built-in `limit_req` (`dev-nginx-config-manage`) or `lua-resty-limit-traffic`; use Lua only for custom keys/logic. `binary_remote_addr` is raw bytes: fine as a dict key, not for logging.

**Pitfall (hit while testing):** nginx's `return` directive runs in the *rewrite* phase, before `access_by_lua*`. A location of `access_by_lua_block {...}` plus `return 200 "ok";` never runs the Lua at all (120 x 200, no limiting). Use a real content handler (`proxy_pass`, `content_by_lua_block`, static files) or move the logic to `rewrite_by_lua*`.

## 4. Logging (`ngx.log` and levels)

```lua
ngx.log(ngx.ERR,    "upstream selection failed for ", host, ": ", err)
ngx.log(ngx.WARN,   "slow auth backend: ", elapsed, "s")
ngx.log(ngx.NOTICE, "feature flag changed: ", name)
ngx.log(ngx.INFO,   "route=", route)              -- visible when error_log level is info
ngx.log(ngx.DEBUG,  "ctx=", require("cjson.safe").encode(ngx.ctx))   -- guard expensive formatting
```

Levels: `ngx.STDERR, EMERG, ALERT, CRIT, ERR, WARN, NOTICE, INFO, DEBUG`. Valid in every phase (including timers, SSL, init). `nil` prints `nil`, booleans print `true/false`, `ngx.null` prints `null`. Messages over 2048 bytes are truncated. Wrap expensive debug formatting in a level check (e.g. `if ngx.config.debug`-style local flag) so it is skipped in production. Set `error_log logs/error.log notice;` in prod, `debug` only temporarily (requires a debug build).

## 5. A small JSON API router (refactor of forkbombe/openresty-api-example)

What the original `api.lua` does well: path templates with typed placeholders, one entrypoint, JSON in/out. What to fix:

| Issue in original | Why it matters | Fix below |
|---|---|---|
| Global functions/tables (`strSplit`, `Api`) | shared by concurrent requests in a worker; leak across requests | module with `local` |
| `cjson.decode` on raw body | raises on bad JSON -> 500 | `cjson.safe` -> 400 |
| `ngx.var.uri:gsub(...)` result used as 1 value | `gsub` returns 2 values | wrap in parentheses / use `ngx.re` |
| Wrong method returns `error=500` in body, HTTP 200 | wrong status | 405 + `Allow` |
| No 404, no body-size check | silent empty reply | explicit 404, `get_body_file()` check |
| Linear `string.match` patterns per request | slow | precompiled `ngx.re` with `"jo"` |

```lua
-- lua/app/router.lua
local cjson = require "cjson.safe"
local _M = {}
local routes = {}

function _M.add(method, pattern, handler)
    routes[#routes + 1] = { method = method, pattern = "^" .. pattern .. "$", handler = handler }
end

local function reply(status, tbl, headers)
    ngx.status = status
    ngx.header.content_type = "application/json"
    if headers then for k, v in pairs(headers) do ngx.header[k] = v end end
    ngx.say(cjson.encode(tbl))
    return ngx.exit(ngx.OK)                -- finish the content phase cleanly
end

function _M.dispatch()
    local path   = ngx.var.uri
    local method = ngx.req.get_method()
    local allowed = {}

    for _, r in ipairs(routes) do
        local m = ngx.re.match(path, r.pattern, "jo")       -- named captures: (?<id>\d+)
        if m then
            if r.method == method then
                local body
                if method == "POST" or method == "PUT" or method == "PATCH" then
                    ngx.req.read_body()
                    local raw = ngx.req.get_body_data()
                    if not raw then
                        if ngx.req.get_body_file() then return reply(413, { error = "body too large" }) end
                        raw = "{}"
                    end
                    local decoded, err = cjson.decode(raw)
                    if decoded == nil then return reply(400, { error = "invalid JSON", detail = err }) end
                    body = decoded
                end
                return r.handler(m, body, reply)
            end
            allowed[#allowed + 1] = r.method
        end
    end

    if #allowed > 0 then
        return reply(405, { error = "method not allowed" }, { Allow = table.concat(allowed, ", ") })
    end
    return reply(404, { error = "not found" })
end

return _M
```

```lua
-- lua/app/routes.lua: loaded once per Lua VM (init_by_lua `require` or first request), routes registered at load time
local router = require "app.router"

router.add("GET",  [[/api/test/(?<id>\d+)/(?<name>\w+)]], function(m, _, reply)
    return reply(200, { id = tonumber(m.id), name = m.name })
end)
router.add("POST", [[/api/test]], function(_, body, reply)
    return reply(201, { received = body })
end)

return router
```

```nginx
location /api/ {
    client_max_body_size 1m;
    client_body_buffer_size 1m;            # keep bodies in memory so get_body_data() works
    content_by_lua_block { require("app.routes").dispatch() }
}
```

`require` caches the module, so routes are registered once per worker, not per request.

Tests:

```bash
curl -s  $H/api/test/42/bob                       # {"id":42,"name":"bob"}
curl -si -X DELETE $H/api/test | grep -E '^(HTTP|Allow)'    # 405 + Allow: POST
curl -s  -X POST -d '{bad' $H/api/test            # 400 invalid JSON
curl -si $H/api/nope | head -1                    # 404
```

## 6. JSON handling (lua-cjson / bundled `cjson`)

```lua
local cjson = require "cjson.safe"        -- returns nil, err instead of throwing
cjson.encode({})                           -- "{}"   (empty table encodes as object by default)
cjson.encode(cjson.empty_array)            -- "[]"
cjson.encode({ a = cjson.null })           -- {"a":null}
cjson.encode_empty_table_as_object(false)  -- OpenResty fork: encode {} as [] globally (per-worker setting; set in init_worker)
cjson.encode_sparse_array(true)            -- allow sparse arrays instead of erroring
```

- OpenResty bundles its own `cjson` (openresty/lua-cjson); Kong ships a fork (Kong/kong-cjson) with the same API for Kong-based stacks. Do not install a second copy; use the one in the install tree.
- Decode numbers > 2^53 lose precision; pass IDs as strings.
- Arrays with holes or non-integer keys raise on encode unless `encode_sparse_array` is set.
- Set limits for untrusted input: `cjson.decode_max_depth(n)`, and bound body size with `client_max_body_size`.

## 7. Replacing `switch` (Lua has none)

```lua
local handlers = {
    GET    = function(ctx) return ctx.read()   end,
    POST   = function(ctx) return ctx.create() end,
    DELETE = function(ctx) return ctx.delete() end,
}
local h = handlers[ngx.req.get_method()]
if not h then
    ngx.header["Allow"] = "GET, POST, DELETE"
    return ngx.exit(405)
end
return h(ctx)
```

Build the table once at module load (not per request). Table dispatch is also JIT-friendly compared with long `if/elseif` string chains.

## 8. Dynamic TLS with `ssl_certificate_by_lua_block`

Requirements: OpenSSL 1.0.2e+, lua-nginx-module with `ssl_certificate_by_lua` support, a **static fallback** `ssl_certificate`/`ssl_certificate_key` in the `server` (nginx refuses to start without it: `no ssl configured for the server`). The handler runs right before the TLS handshake and may yield (cosockets allowed).

```nginx
http {
    lua_package_path "$prefix/lua/?.lua;;";
    # allow-list of SNI names served from /etc/ssl/dynamic/<host>.crt|.key
    init_worker_by_lua_block {
        require("app.certs").load("/etc/ssl/dynamic/", { "a.example.org", "b.example.org" })
    }

    server {
        listen 443 ssl;
        ssl_certificate     /etc/ssl/fallback.crt;  # required fallback
        ssl_certificate_key /etc/ssl/fallback.key;
        ssl_certificate_by_lua_block { require("app.certs").select() }
    }
}
```

```lua
-- lua/app/certs.lua
local ssl = require "ngx.ssl"
local _M = {}
local by_host = {}          -- per-worker: host -> { cert = <chain>, key = <privkey> }

local function slurp(path)
    local f, err = io.open(path, "rb")           -- allowed here: init_worker runs at startup, not per request
    if not f then return nil, err end
    local d = f:read("*a"); f:close(); return d
end

function _M.load(dir, hosts)
    for _, host in ipairs(hosts or {}) do
        local pem_cert = slurp(dir .. host .. ".crt")
        local pem_key  = slurp(dir .. host .. ".key")
        if pem_cert and pem_key then
            local cert, e1 = ssl.parse_pem_cert(pem_cert)
            local key,  e2 = ssl.parse_pem_priv_key(pem_key)
            if cert and key then by_host[host] = { cert = cert, key = key }
            else ngx.log(ngx.ERR, "cert load failed for ", host, ": ", e1 or e2) end
        end
    end
end

function _M.select()
    local name = ssl.server_name()                 -- SNI; nil without SNI
    local entry = name and by_host[name:lower()]
    if not entry then return end                   -- keep the static fallback
    local ok, err = ssl.clear_certs()
    if not ok then ngx.log(ngx.ERR, "clear_certs: ", err); return ngx.exit(ngx.ERROR) end
    ok, err = ssl.set_cert(entry.cert)
    if not ok then ngx.log(ngx.ERR, "set_cert: ", err); return ngx.exit(ngx.ERROR) end
    ok, err = ssl.set_priv_key(entry.key)
    if not ok then ngx.log(ngx.ERR, "set_priv_key: ", err); return ngx.exit(ngx.ERROR) end
end

return _M
```

Notes:
- **Permissions:** `init_worker_by_lua*` runs as the unprivileged worker user (`nobody`/`www-data`), not in the master. Files read there (Lua modules first loaded in workers, `*.key`) must be readable by that user, while `ssl_certificate_key` is read by the master as root. Symptom of a mismatch: `module 'app.certs' not found` with the file present, or `cert load failed`. Verified on OpenResty 1.31.8.1: SNI `a.example.org`/`b.example.org` return their own certs, an unknown name returns the fallback.
- `parse_pem_cert` / `parse_pem_priv_key` return cdata objects: cache them (per worker) rather than parsing per handshake; `cert_pem_to_der` + `set_der_cert` is the older path.
- Only accept SNI names from an allow-list; never fetch certificates for arbitrary client-chosen names (DoS and key-exposure risk).
- Certificate renewal: reload workers or refresh the cache from a timer; coordinate with the ACME client's hooks.
- `lua-resty-auto-ssl` (on-the-fly Let's Encrypt via this phase, internal `127.0.0.1:8999` hook server, `lua_shared_dict auto_ssl 1m` + `auto_ssl_settings 64k`, `/.well-known/acme-challenge/` handler, needs `resolver`, a fallback cert, writable `/etc/resty-auto-ssl`) is marked **abandoned** in its README; treat as legacy and prefer acme.sh, dehydrated, or the cluster's ACME stack.
- Test: `openssl s_client -connect 127.0.0.1:443 -servername a.example.org </dev/null 2>/dev/null | openssl x509 -noout -subject` versus an unknown SNI (must show the fallback).
- Reference docs: lua-resty-core `lib/ngx/ssl.md` (`parse_pem_cert`, `set_cert`, `server_name`, `verify_client`, `get_tls1_version_str`) and its `t/ssl.t` for runnable examples.

## 9. Timers and background jobs

```nginx
init_worker_by_lua_block {
    if ngx.worker.id() == 0 then                         -- run once per server, not once per worker
        local ok, err = ngx.timer.every(30, function(premature)
            if premature then return end                 -- worker is shutting down
            local flags = ngx.shared.flags
            -- cosocket calls (lua-resty-http/redis) are allowed in timers
            ngx.log(ngx.INFO, "refresh tick")
        end)
        if not ok then ngx.log(ngx.ERR, "timer failed: ", err) end
    end
}
```

Always handle `premature`. Timers have no request: no `ngx.var`, no `ngx.req`. `lua_max_running_timers`/`lua_max_pending_timers` bound them.

## 10. Gateway pattern: API-key check with local cache

```lua
-- access_by_lua_block
local key = ngx.var.http_x_api_key
if not key or #key > 128 then return ngx.exit(401) end

local cache = ngx.shared.keys
-- separate prefixes: a client key can never collide with another entry type
if cache:get("neg:" .. key) then return ngx.exit(403) end   -- known-bad key: no backend call
local tenant = cache:get("pos:" .. key)
if not tenant then
    local res = require("app.auth").lookup(key)          -- cosocket call to auth service/redis (non-blocking)
    if not res then
        cache:set("neg:" .. key, true, 10)                -- negative cache, short TTL
        return ngx.exit(403)
    end
    tenant = res.tenant
    cache:set("pos:" .. key, tenant, 300)
end
ngx.ctx.tenant = tenant                                   -- visible to later phases (log_by_lua, header_filter)
ngx.req.set_header("X-Tenant", tenant)                    -- set, not append: strip spoofed values
ngx.req.clear_header("X-Api-Key")                         -- do not forward the credential
```

The negative cache only absorbs repeated bad keys; random keys still reach the backend, so put a per-IP `limit_req` (or the section 3 limiter) in front of this check. `set` evicts by LRU when the dict is full, so a flood of negative entries can push out positive ones; use a separate dict for negatives if that matters.

Use `ngx.ctx` (per-request Lua table) for phase-to-phase state; `ngx.var` is nginx's variable store (strings only; declare custom ones with `set $tenant "";` first). Hash or truncate API keys before logging.

## 11. `Test::Nginx` skeleton

```perl
use Test::Nginx::Socket 'no_plan';
run_tests();

__DATA__
=== TEST 1: rate limit returns 429 after limit
--- http_config
    lua_shared_dict ratelimit 1m;
    lua_package_path "$prefix/../lua/?.lua;;";
--- config
    location /t {
        access_by_lua_block { local ok = require("app.ratelimit").check("k", 1, 60); if not ok then return ngx.exit(429) end }
        echo ok;
    }
--- pipelined_requests eval
["GET /t", "GET /t"]
--- error_code eval
[200, 429]
```

`resty` CLI one-liners for unit-level checks: `resty -e 'local c=require"cjson.safe"; print(c.encode({}))'`; add `--shdict 'ratelimit 1m'` to test shared dict code outside nginx.
