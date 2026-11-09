# Dynamic key-value state in nginx

Use when behavior must change without a reload or deploy: feature flags, blocklists, canary routes, redirect maps, maintenance switches. Pick the implementation by distribution first.

| Option | Distribution | State persistence | Update path |
|---|---|---|---|
| `ngx_http_keyval_module` (nginx.org) | **NGINX Plus only** (commercial subscription) | `state=` JSON file, optional `sync` across cluster | NGINX Plus REST API (`api write=on;`) |
| `kjdev/nginx-keyval` | Open-source dynamic module (MIT), nginx OSS | shared memory (lost on restart) or Redis | write by a variable/Lua/njs or direct Redis; no REST API |
| `lua_shared_dict` + Lua | OpenResty | shared memory (survives reload, not restart) | Lua handler/admin endpoint (see `dev-openresty-config-manage`) |
| plain `map` + `include` file | any nginx | file in repo | edit file + `nginx -s reload` (cheap, atomic, auditable) |

If none of the dynamic options is installed, use the `map` + `include` row; it is the safest default.

## NGINX Plus `ngx_http_keyval_module` (docs: nginx.org/en/docs/http/ngx_http_keyval_module.html)

```nginx
http {
    keyval_zone zone=one:32k state=/var/lib/nginx/state/one.keyval;   # http context only
    keyval $arg_text $text zone=one;                                  # key, variable, zone
    server {
        location /      { return 200 $text; }
        location /api   { api write=on; }                             # lock down with allow/deny or auth
    }
}
```

- `keyval_zone zone=name:size [state=file] [timeout=time] [type=string|ip|prefix] [sync];`
- `type=ip`: key is an address or CIDR, search key must fall in it (good for IP blocklists/allow-lists); `type=prefix` (1.17.5): record key must be a prefix of the search key (path routing). Both need extra zone memory.
- `sync` requires `timeout`; deletions only apply on the target node, peers expire by timeout.
- Do not edit the `state` file by hand.

## kjdev/nginx-keyval (open source)

- Contexts: `http`, `stream`. Directives: `keyval`, `keyval_zone`, `keyval_zone_redis`.
- Shared memory zone: `keyval_zone zone=name:size [ttl=...];` (minimum size 8 x page size; "zone is too small" otherwise). TTL is an extension and not in Plus.
- Redis zone needs the module built with `NGX_KEYVAL_ZONE_REDIS=1`. Defaults: `connect_timeout` and `command_timeout` 3s; `command_timeout=0` is rejected.
- Composite keys work: `keyval "$remote_addr:$http_user_agent" $v zone=one;`.
- Not implemented compared with Plus: `state=`, `type=prefix|ip`, `sync`, REST API.
- Security (module docs): shared memory data is plaintext and lost on restart; Redis AUTH and TLS are not supported, so keep Redis on a trusted loopback/private link; Redis calls are blocking, so keep timeouts low to avoid stalling workers.
- Common errors: `zone is too small`, `duplicate zone parameter`, `keyval: failed to connect redis`, `rejected due to not found variable zone`.

```nginx
http {
    keyval_zone zone=flags:1m ttl=1h;
    keyval $http_x_tenant $tenant_flag zone=flags;

    map $tenant_flag $backend_pool { default app_stable; "canary" app_canary; }

    server {
        location / { proxy_pass http://$backend_pool; }     # variable => needs upstream names, no URI replace
    }
}
```

Verify the module is loaded before relying on it: `nginx -V 2>&1 | tr ' ' '\n' | grep -i keyval` and a `load_module modules/ngx_http_keyval_module.so;` line at the top of `nginx.conf`.

## Static alternative (works everywhere)

```nginx
# conf.d/flags.conf (generated or edited in the repo, then `nginx -t && nginx -s reload`)
map $http_x_tenant $backend_pool {
    default   app_stable;
    acme      app_canary;
    include   /etc/nginx/tenants-canary.map;       # lines like: "globex" app_canary;
}
```

## Guidance

- Treat the key-value store as untrusted input: never put raw request data into `proxy_pass` hosts, `Location` headers, or `return` URLs without an allow-list `map`.
- Bound key cardinality (TTL, zone size); an unbounded zone from client-controlled keys is a memory DoS.
- Document the write path and who may write; never expose write APIs publicly.
