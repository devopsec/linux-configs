# Vetted sources for nginx configuration

Ordered by authority. Always prefer the first group when sources disagree.

## Authoritative

| Source | Use for | Notes |
|---|---|---|
| <https://nginx.org/en/docs/dirindex.html> | directive index: syntax, default, context, version | the only ground truth for "does this directive exist here" |
| <https://nginx.org/en/docs/http/ngx_http_core_module.html#variables> | built-in variables | `$host` vs `$http_host`, `$uri` vs `$request_uri` |
| <https://nginx.org/en/docs/http/ngx_http_upstream_module.html> | upstream, keepalive, load-balancing, `$upstream_*` | |
| <https://nginx.org/en/docs/http/ngx_http_proxy_module.html> | proxy_* directives | buffers, caching, `proxy_pass` URI rules |
| <https://nginx.org/en/docs/http/converting_rewrite_rules.html> | replacing rewrite with server blocks/`return`/`try_files` | |
| <https://nginx.org/en/docs/http/ngx_http_keyval_module.html> | keyval (Plus only) | marked "commercial subscription" |
| <https://nginx.org/en/docs/http/ngx_http_stub_status_module.html> | `stub_status` | needs build flag |
| <https://ssl-config.mozilla.org/> | TLS profile generator | pick "nginx", match nginx + OpenSSL versions |
| <https://docs.nginx.com/nginx/admin-guide/> | F5 admin guide (OSS + Plus) | |

## Community collections (check before copying)

| Source | Strength | Caveat |
|---|---|---|
| [h5bp/server-configs-nginx](https://github.com/h5bp/server-configs-nginx) | maintained boilerplate: security headers, caching, compression, `conf.d`/`h5bp` include layout | opinionated for static sites; trim for API proxies |
| [lebinh/nginx-conf](https://github.com/lebinh/nginx-conf) | concise redirects/cache/gzip/CORS/auth snippets | old: TLS list, `post_action`, `{PLAIN}` auth are outdated (see recipes.md) |
| [agile6v/awesome-nginx](https://github.com/agile6v/awesome-nginx) | index of distributions, third-party modules, tools | discover modules; verify maintenance status before adopting |
| [kjdev/nginx-keyval](https://github.com/kjdev/nginx-keyval) | open-source keyval dynamic module | see `keyval-and-dynamic-state.md` |
| [Codeship: Tuning NGINX](https://blog.codeship.com/tuning-nginx/) | method: change one parameter, re-measure (`worker_processes`, `worker_connections`, `worker_rlimit_nofile`) | 2016 era; page may be retired; numbers are not portable |
| [DEV: Optimizing Nginx Configuration](https://dev.to/tanvirrahman/comprehensive-guide-to-optimizing-nginx-configuration-3hb9) | worked walk-through of location types, rewrite, named captures, logging | tutorial values (e.g. 10K buffers, 12s timeouts) are examples, not recommendations |
| Cheat sheets: [toolkitpub](https://www.toolkitpub.com/tools/nginx-cheatsheet), [skillademia](https://www.skillademia.com/cheat-sheets/nginx/) | quick lookup of directive names/examples | verify context/version in nginx.org docs |
| DigitalOcean config generator <https://www.digitalocean.com/community/tools/nginx> | baseline server/security/caching blocks | review generated TLS/headers against Mozilla profile |

## Verification routine for a copied snippet

1. Look up each directive in the directive index (context, default, introduced-in version).
2. Compare against `nginx -V` modules (`--with-http_stub_status_module`, `--with-http_realip_module`, `--with-http_v2_module`).
3. Run `nginx -t` in a container of the project's exact nginx tag.
4. Write a curl test (recipes.md "Config test matrix").
5. Strip tutorial placeholders: IPs, docroots, tiny timeouts.
