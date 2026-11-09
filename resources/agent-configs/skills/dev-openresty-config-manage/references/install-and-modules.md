# Installing OpenResty and managing Lua modules

Sources: <https://openresty.org/en/getting-started.html>, <https://openresty.org/en/deb-packages.html>, lua-resty-core README (prerequisites).

## Packages (Debian/Ubuntu official APT repo)

| Package | Provides |
|---|---|
| `openresty` | production server at `/usr/local/openresty/nginx/sbin/nginx`; use the `openresty` command, not `nginx`; `systemctl start|stop|restart|reload openresty` |
| `openresty-resty` | the `resty` CLI (`resty -e 'ngx.say("hello")'`) |
| `openresty-opm` | `opm` package manager for community libraries |
| `openresty-doc` | offline docs + `restydoc` |
| `openresty-debug` | debug build (`--with-debug`): enables `debug` error log level and extra checks; slower |
| `openresty-valgrind` | build for Valgrind runs only |

Default prefix is `/usr/local/openresty/`. For your own app, keep config in the project and run with `-p` so the installation tree stays untouched:

```bash
mkdir -p myapp/{conf,logs,lua}
openresty -p "$PWD/myapp" -c conf/nginx.conf -t     # syntax check
openresty -p "$PWD/myapp" -c conf/nginx.conf        # start
openresty -p "$PWD/myapp" -s reload                 # graceful reload
curl -s http://localhost:8080/                      # smoke test
```

Container alternative (verified in this skill's tests, OpenResty 1.31.8.1, LuaJIT 2.1):

| Image (`docker.io/openresty/openresty:`) | Has `resty` | Has `opm`/`luarocks` | Use for |
|---|---|---|---|
| `alpine` | no (`resty` is a Perl script and the image has no `perl`) | `opm` only | running the server |
| `alpine-fat` | yes | both | CLI tests (`resty`), installing libraries, builds |

Mount the project read-only and run `openresty -c /srv/app/conf/nginx.conf -g 'daemon off;'`. With rootless podman use fully qualified image names (short names do not resolve without a configured registry) and `:Z` on bind mounts under SELinux. Remember workers run as an unprivileged user: mounted Lua and key files must be world-readable (or owned appropriately). Build flags present in the image: `http_ssl`, `http_v2`, `http_realip`, `http_stub_status`, `stream`, `stream_ssl`, `stream_ssl_preread`.

## Minimal `nginx.conf` for a new app

```nginx
worker_processes auto;
error_log logs/error.log info;
events { worker_connections 1024; }
http {
    lua_package_path "$prefix/lua/?.lua;;";
    server {
        listen 8080;
        location / { default_type text/plain; content_by_lua_block { ngx.say("hello, ", ngx.var.remote_addr) } }
    }
}
```

## Library management

- `opm get <author>/<lib>` installs into `/usr/local/openresty/site/`; `opm list`; pin versions in a lock/notes file because opm has no lockfile.
- `luarocks` (with `--lua-version=5.1`, OpenResty's LuaJIT) for libraries not on opm; set `LUAROCKS_CONFIG`/`--tree` to a project directory and add it to `lua_package_path`/`lua_package_cpath`.
- Vendor critical libs under the project `lua/` directory when reproducibility matters.
- Bundled and available: `cjson` (lua-cjson), `ngx.*`, `resty.core`, `resty.lrucache`, `resty.lock`, `resty.limit.*`, `resty.string`, `resty.redis`, `resty.mysql`, `resty.dns.resolver`, `resty.upload`, `resty.websocket.*`. Not bundled: `resty.http` (lua-resty-http), JWT libs, `resty.auto-ssl`.
- `lua-resty-core` is loaded by default in current OpenResty; some API features (e.g. `incr` `init_ttl`) require it. Its README states it must match the bundled `lua-nginx-module`/LuaJIT versions: use the bundled copy, do not mix versions.
- Kong's `cjson` fork (`Kong/kong-cjson`) is for Kong runtimes; in plain OpenResty use the bundled one.

## `resty` CLI for scripts and unit tests

```bash
resty -e 'local c = require "cjson.safe"; print(c.encode({a=1}))'
resty --shdict 'ratelimit 1m' -e 'local d = ngx.shared.ratelimit; print(d:incr("k", 1, 0))'
resty -I lua script.lua           # add lua/ to the module path
resty -j v script.lua             # JIT verbose (diagnose trace aborts)
```

`resty` runs code in a timer-like context: request-phase APIs (`ngx.var`, `ngx.req`) are unavailable, so unit-test pure modules and use `Test::Nginx` for phase-bound code.

## Version checks

```bash
openresty -v                  # nginx/OpenResty version
openresty -V 2>&1 | tr ' ' '\n' | grep -E 'with-|add-'    # compiled modules (stream, http_v2, lua, luajit)
resty -e 'print(jit.version, ngx.config.ngx_lua_version, ngx.config.nginx_version)'
```

Record these in the PR when behavior depends on a version (e.g. `ssl_certificate_by_lua` needs OpenSSL 1.0.2e+; HTTP/2 `http2 on;` needs nginx >= 1.25.1).
