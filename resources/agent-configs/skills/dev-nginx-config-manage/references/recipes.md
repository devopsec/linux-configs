# nginx recipes (copy-ready, each with a test)

Derived from nginx.org docs, lebinh/nginx-conf, h5bp/server-configs-nginx, and the dev.to/cheatsheet material. Outdated advice from those sources is replaced and marked **(updated)**. Check each directive against the project's nginx version.

Test convention: `H=http://localhost:8080` (or the project's test port); `curl -sS -D- -o/dev/null "$H/path"` shows status + headers.

Verification status: the recipes below (and the TLS-free parts of `tuning-and-proxy-patterns.md`) were assembled into one config and passed `openresty -t` (nginx core of OpenResty 1.31.8.1); the non-proxy recipes were exercised with curl and the results are noted per section. Proxy-to-upstream behavior (mirror, canary, cache, WebSocket, SSE) was syntax-checked only.

## 1. Location matching (and how to prove which block won)

Order: `=` exact → longest `^~` prefix (stops regex search) → first matching regex (`~`, `~*`, in file order) → longest plain prefix.

```nginx
location = /health      { return 200 'ok\n'; }                  # exact
location ^~ /static/    { root /srv/app; }                      # beats any regex below
location ~* \.(?:png|jpe?g|svg|webp)$ { expires 30d; }         # regex, first match wins
location /api/          { proxy_pass http://app; }              # plain prefix
location /              { try_files $uri /index.html; }
```

Debug which location matched without guessing:

```nginx
location /api/ { add_header X-Loc api always; proxy_pass http://app; }
```

Test: `curl -sI $H/api/x | grep -i x-loc`. Remove debug headers before merging.

Capture + rewrite + named capture (from dev.to guide):

```nginx
location ~ ^/week/(\w+)$            { rewrite ^/week/(\w+)$ /weekend/$1 last; }   # internal re-dispatch
location ~ ^/weekend/(?<day>\w+)$   { return 200 "$day\n"; }                      # named capture
```

Test: `curl -s $H/week/sat` → `sat` (verified).

## 2. Redirects (separate `server` blocks, `return`)

```nginx
# HTTP -> HTTPS
server { listen 80; server_name example.org www.example.org; return 301 https://example.org$request_uri; }

# www -> apex (HTTPS site: both names need a cert)
server { listen 443 ssl; server_name www.example.org; ssl_certificate ...; ssl_certificate_key ...; return 301 https://example.org$request_uri; }

# single page / path prefix
location = /oldpage.html { return 301 /newpage.html; }
location /old-site/      { rewrite ^/old-site/(.*)$ /new-site/$1 permanent; }

# add trailing slash only for extensionless paths
rewrite ^([^.]*[^/])$ $1/ permanent;

# do not leak the internal listen port / host in relative redirects (set in http or server)
absolute_redirect off;       # nginx >= 1.11.8: emits `Location: /newpage.html`
```

Use 301/308 for permanent, 302/307 for temporary; 307/308 preserve the method. Tests (verified): `curl -sI $H/oldpage.html` → `301` + `Location: /newpage.html`.

**Pitfall (verified):** by default nginx turns a relative `return 301 /x;` into an absolute URL using the *listen port of the nginx process*. Behind a port mapping, container, or load balancer on a different port, the browser is sent to `http://host:8080/x` (the internal port). Fix with `absolute_redirect off;`, `port_in_redirect off;`, or an explicit absolute URL (`return 301 https://example.org$request_uri;`, preferred for canonical-host redirects).

## 3. Static files, caching headers, gzip

```nginx
location /static/ {
    root /srv/app;
    # Either `expires 30d;` (sets Expires + Cache-Control: max-age) OR an explicit header, not both:
    # `expires` plus `add_header Cache-Control` sends TWO Cache-Control headers (verified).
    add_header Cache-Control "public, max-age=2592000, immutable" always;   # re-declare with every other add_header in this block
    access_log off;
}
location ~* \.(?:png|jpe?g|svg|webp)$ { expires 30d; }   # simple form: Cache-Control: max-age=2592000 (verified)

gzip on;
gzip_comp_level 5;                        # 4-6 is the usual CPU/size sweet spot
gzip_min_length 256;
gzip_proxied any;
gzip_vary on;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss image/svg+xml;
# text/html is always compressed; do not list it.
```

**(updated)** lebinh's `gzip_disable "msie6"` and `gzip_http_version 1.1` are obsolete defaults. Hashed assets can use `immutable`; HTML must not.

Metadata cache for many small files:

```nginx
open_file_cache          max=1000 inactive=20s;
open_file_cache_valid    30s;
open_file_cache_min_uses 2;
open_file_cache_errors   on;
```

Test (verified): `curl -sI -H 'Accept-Encoding: gzip' $H/static/big.txt | grep -i -E 'content-encoding|vary'` → `Content-Encoding: gzip`, `Vary: Accept-Encoding`; `curl -sI $H/static/app.js | grep -i cache-control` → exactly one header.

## 4. SPA + API split

```nginx
location /api/ { proxy_pass http://app; ... }
location /     { root /srv/spa; try_files $uri $uri/ /index.html; }
```

`try_files` with a final `=404` for non-SPA sites; the last argument is an internal redirect, not a file test. Test deep link (verified): `curl -s $H/some/client/route | head -c 100` returns the SPA `index.html`.

## 5. Health and error pages

```nginx
location = /healthz { access_log off; default_type text/plain; return 200 'ok\n'; }
error_page 502 503 504 /50x.html;
location = /50x.html { root /usr/share/nginx/html; internal; }   # path differs per install (see below)
```

The 50x page directory differs: `/usr/share/nginx/html` (Debian/Ubuntu packages, official `nginx` image), `/usr/local/openresty/nginx/html` (OpenResty). A wrong path turns a 502 into a 404 plus `open() "...50x.html" failed (2: No such file or directory)` (verified). Ship the error page inside the project and point `root` at it.

Test: `curl -sI $H/healthz`; stop the upstream and check `/` returns the 50x page.

## 6. Access control

```nginx
# IP allow-list (first match wins; end with deny all)
location /admin/ {
    allow 10.0.0.0/8; allow 127.0.0.1; allow ::1; deny all;   # ::1: `localhost` may resolve to IPv6
    proxy_pass http://app;
}

# basic auth - hashed file, never {PLAIN}
auth_basic "restricted";
auth_basic_user_file /etc/nginx/htpasswd;     # created with: openssl passwd -apr1  (or htpasswd -m)
```

Password schemes: nginx itself verifies only `$apr1$` (MD5-apr1), `{SHA}` and `{SSHA}`; everything else goes to the system `crypt()`. bcrypt (`htpasswd -B`, `$2y$`) works only if the libc/libxcrypt supports it (musl/Alpine and glibc builds without libxcrypt often do not); otherwise every login gets 401 and the error log shows `crypt_r() failed`. Before using bcrypt or `$5$`/`$6$` (SHA-crypt), test one login against the exact nginx image; default to apr1 when unsure.

**(updated)** lebinh shows a `{PLAIN}` password file; use apr1 hashes (bcrypt only where `crypt()` supports it, see above). Combine with `satisfy any;` only when OR-semantics are intended. Tests: `curl -s -o/dev/null -w '%{http_code}\n' $H/admin/` → `401`/`403` from a non-allowed address (from an allowed one the proxy is reached: verified 502 with a dead upstream); with `-u user:pass` → `200`. Container/port-mapped tests may arrive from a bridge address (`10.x`) rather than `127.0.0.1`: check `$remote_addr`.

## 7. CORS (explicit origins via `map`)

```nginx
map $http_origin $cors_origin {
    default "";
    "https://app.example.org" $http_origin;
    "https://staging.example.org" $http_origin;
}

location /api/ {
    add_header Access-Control-Allow-Origin $cors_origin always;
    add_header Vary Origin always;
    if ($request_method = OPTIONS) {              # return-only `if` is safe
        add_header Access-Control-Allow-Origin  $cors_origin always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type" always;
        add_header Access-Control-Max-Age 86400 always;
        return 204;
    }
    proxy_pass http://app;
}
```

**(updated)** `Access-Control-Allow-Origin *` (lebinh) is only for fully public assets; credentials need exact origins. The preflight `add_header`s repeat because `add_header` inside `if` replaces the outer set. Test (verified): `curl -si -X OPTIONS -H 'Origin: https://app.example.org' -H 'Access-Control-Request-Method: POST' $H/api/x` → `204` with `Access-Control-Allow-Origin: https://app.example.org`, methods, headers, max-age; with `Origin: https://evil.example` → `204` and **no** `Access-Control-Allow-Origin` header.

## 8. TLS server block (modern baseline)

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;                                  # nginx >= 1.25.1; older: `listen 443 ssl http2;`
    server_name example.org;

    ssl_certificate     /etc/ssl/example.org/fullchain.pem;
    ssl_certificate_key /etc/ssl/example.org/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    # ssl_ciphers: paste from https://ssl-config.mozilla.org/ (intermediate)
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on; ssl_stapling_verify on;    # needs `resolver` and a CA that supports OCSP
    add_header Strict-Transport-Security "max-age=31536000" always;
}
```

**(updated)** lebinh's `TLSv1 TLSv1.1` list, huge cipher string, and `ssl_prefer_server_ciphers on` are obsolete. Test: `openssl s_client -connect host:443 -tls1_2 </dev/null | head`, and `curl -sI https://host/ | grep -i strict`. For audits use `sec-tls-config-audit`.

## 9. Observability in config

```nginx
log_format main_ext '$remote_addr "$request" $status $body_bytes_sent '
                    'rt=$request_time urt=$upstream_response_time uct=$upstream_connect_time '
                    'uaddr=$upstream_addr cache=$upstream_cache_status rid=$request_id';
access_log /var/log/nginx/access.log main_ext buffer=64k flush=5s;

proxy_set_header X-Request-ID $request_id;      # correlate nginx and app logs

# only trusted networks may read it; needs --with-http_stub_status_module
location = /nginx_status { stub_status; allow 127.0.0.1; allow ::1; deny all; access_log off; }
```

Skip noisy logs with a map: `map $uri $loggable { /healthz 0; default 1; }` + `access_log ... if=$loggable;`. Test: `curl -s http://localhost/nginx_status` shows `Active connections`, `accepts handled requests`, `Reading/Writing/Waiting`. The ACL allows `::1` because `localhost` may resolve to IPv6 first and, with a `listen [::]` socket, connect from `::1` (403 otherwise); if the ACL cannot change, test with `curl -4`.

## 10. Request mirroring and canary (replace `post_action`)

```nginx
location /api/ {
    mirror /_mirror;                 # nginx >= 1.13.4
    mirror_request_body on;
    proxy_pass http://app;
}
location = /_mirror { internal; proxy_pass http://shadow$request_uri; proxy_set_header X-Mirror 1; }

split_clients "${remote_addr}${http_user_agent}" $canary { 5% canary; * stable; }   # sticky ~5% bucket
# proxy_pass http://app_$canary;   (define upstream app_canary / app_stable)
```

**(updated)** lebinh's `post_action` is undocumented and unsupported; use `mirror`. With a variable in `proxy_pass`, nginx needs a `resolver` for hostnames and no longer replaces the matched URI.

## 11. Useful core variables

| Need | Variable | Note |
|---|---|---|
| Host the client asked for | `$host` | normalized, no port; `$http_host` keeps the port and can be empty |
| Original URI incl. query | `$request_uri` | `$uri` is normalized and changes after rewrite/try_files |
| Query string with `?` | `$is_args$args` | |
| Client IP | `$remote_addr` | after `real_ip` module: the replaced address; original in `$realip_remote_addr` |
| Scheme seen by nginx | `$scheme` | behind a TLS-terminating LB use a `map` on `X-Forwarded-Proto` from trusted hops |
| Upstream timing | `$upstream_connect_time`, `$upstream_header_time`, `$upstream_response_time` | comma-separated on retries |
| Request correlation | `$request_id` | 32 hex chars, nginx >= 1.11.0 |

Source: <https://nginx.org/en/docs/http/ngx_http_core_module.html#variables>.

## 12. Config test matrix (use as the PR test plan)

| Change | Test |
|---|---|
| New route | `curl -sI $H/route` → expected status, `Server` has no version, headers present |
| `proxy_pass` URI handling | upstream echo endpoint returns the received path; compare `/api/x` vs `/api/x?y=1` |
| Header inheritance | `curl -sI` on a location that adds a header: previously inherited headers still present |
| Redirect | `curl -sI` status + `Location`; loop check `curl -sIL --max-redirs 5` |
| Rate limit | `for i in $(seq 1 50); do curl -s -o/dev/null -w '%{http_code}\n' $H/api/; done \| sort \| uniq -c` shows 429s |
| WebSocket | `curl -si -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==' $H/ws/` → `101` |
| Gzip | `Accept-Encoding: gzip` + `Content-Encoding: gzip` |
| Reload safety | `nginx -t && nginx -s reload`, then error.log has no `[emerg]`/`[alert]` |
