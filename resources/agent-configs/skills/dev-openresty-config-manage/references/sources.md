# Vetted sources for OpenResty / Lua in nginx

## Authoritative

| Source | Use for |
|---|---|
| [lua-nginx-module README](https://github.com/openresty/lua-nginx-module#nginx-api-for-lua) | every directive and `ngx.*` API with allowed contexts. Key anchors: `#lua_shared_dict`, `#init_by_lua_block`, `#ssl_certificate_by_lua_block`, `#nginx-log-level-constants`, `#ngxlog`, `ngx.shared.DICT` methods, `ngx.timer.*` |
| [lua-resty-core](https://github.com/openresty/lua-resty-core) | FFI implementations of the API; `lib/ngx/ssl.md` (cert/key parsing, `set_cert`, `server_name`, `verify_client`), `t/ssl.t` runnable examples; README prerequisites (version coupling with bundled lua-nginx-module/LuaJIT) |
| [openresty.org getting started](https://openresty.org/en/getting-started.html) / [deb packages](https://openresty.org/en/deb-packages.html) | install, `-p` prefix layout, `resty`, `opm` |
| [openresty/lua-cjson](https://github.com/openresty/lua-cjson/) | JSON API (`encode_empty_table_as_object`, `empty_array`, `decode_max_depth`) used by OpenResty |
| [nginx.org docs](https://nginx.org/en/docs/dirindex.html), [core variables](https://nginx.org/en/docs/http/ngx_http_core_module.html#variables) | plain nginx directives and variables used by Lua via `ngx.var` |
| [LuaJIT docs](https://luajit.org/luajit.html) and NYI table | JIT behavior; see `luajit-performance.md` for the checked list. (`luajit.org/status.html` is a project status page, not the NYI list) |

## Libraries and implementations

| Source | Notes |
|---|---|
| [Kong/kong-cjson](https://github.com/Kong/kong-cjson) | Kong's lua-cjson fork; relevant only inside Kong |
| [kjdev/nginx-keyval](https://github.com/kjdev/nginx-keyval) | OSS keyval C module (shm/Redis); for pure-Lua use `lua_shared_dict`. Plus-only module differs (see nginx skill) |
| [auto-ssl/lua-resty-auto-ssl](https://github.com/auto-ssl/lua-resty-auto-ssl) | on-the-fly Let's Encrypt; README marks it **abandoned**; reference for the `ssl_certificate_by_lua` pattern only |
| [Kong](https://github.com/Kong/kong), [Apache APISIX](https://github.com/apache/apisix) | large production OpenResty gateways; read for patterns (DNS, pooling, route matching, plugins) |
| [forkbombe/openresty-api-example](https://github.com/forkbombe/openresty-api-example/blob/master/api.lua) | small API router; useful as a teaching sample, but contains globals, unchecked decode and wrong status codes (see examples.md section 5) |
| Medium: [Building an API Gateway with Nginx + Lua](https://medium.com/@tumulr/building-an-api-gateway-with-nginx-lua-e3dff45e6e63) | blocked for automated fetch (Cloudflare); read manually, apply the examples.md safety rules (phase checks, non-blocking I/O, status codes) |
| [Stack Overflow: switch alternative in Lua](https://stackoverflow.com/questions/37447704/what-is-the-alternative-for-switch-statement-in-lua-language) | table-of-functions dispatch (see examples.md section 7) |

## Trust notes

- Blog posts and gists often use pre-2018 APIs (`ngx.req.get_uri_args` default limits, `lua-resty-core` off) or `lua_code_cache off` in production snippets; verify against the README for the installed version.
- LLM-written summaries (including the supplied Gemini notes) mixed up some LuaJIT claims; the NYI table is the check. They also pointed to a non-existent `nyt_intro.html`; the OpenResty/LuaJIT NYI reference is the table above.
- A directive/API not in the lua-nginx-module README or lua-resty-core docs should be treated as nonexistent until found there.
