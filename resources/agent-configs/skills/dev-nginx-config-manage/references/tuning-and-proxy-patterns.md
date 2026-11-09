# nginx tuning and reverse-proxy patterns

Verify each directive against <https://nginx.org/en/docs/> for the installed version. Contexts are noted per block.

## Workers and kernel I/O

```nginx
worker_processes auto;            # main
worker_cpu_affinity auto;         # main
worker_rlimit_nofile 20480;       # main; >= 2x worker_connections (client + upstream sockets)

events {
    worker_connections 8192;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;                # headers + file start in one packet; needs sendfile
    tcp_nodelay on;               # no Nagle delay on keepalive/interactive connections
    server_tokens off;
}
```

Raise the systemd `LimitNOFILE` too when `worker_rlimit_nofile` exceeds the unit limit. `use epoll;` is the Linux default; omit it.

## Upstream with keepalive

```nginx
upstream app {
    zone app 64k;
    server 127.0.0.1:8080 max_fails=3 fail_timeout=10s;
    server 127.0.0.1:8081 max_fails=3 fail_timeout=10s;
    keepalive 64;
}

server {
    location / {
        proxy_pass http://app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Re-declare all `proxy_set_header` lines in any location that adds one.

## Buffers

```nginx
proxy_buffering on;
proxy_buffer_size 8k;             # response headers
proxy_buffers 8 64k;
proxy_busy_buffers_size 128k;     # must be < proxy_buffers total minus one buffer
```

Size buffers from measured response sizes; payloads larger than the buffers spill to disk (`proxy_temp_path`). Disable buffering (`proxy_buffering off;`) only for streaming/SSE locations.

## Rate limiting

```nginx
http {
    limit_req_zone  $binary_remote_addr zone=api_limit:10m rate=30r/s;   # ~160k IP states per 10m
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
    limit_req_status 429;
    limit_conn_status 429;
}

location /api/v1/ {
    limit_req  zone=api_limit burst=20 nodelay;
    limit_conn conn_limit 10;
    proxy_pass http://app;
}
```

Behind a CDN/LB, key on the real client IP (`set_real_ip_from` + `real_ip_header`), otherwise all clients share one bucket.

## TLS

- Follow the Mozilla SSL configuration generator profile ("intermediate" by default): <https://ssl-config.mozilla.org/>.
- `listen 443 ssl;` plus `http2 on;` (nginx >= 1.25.1; older: `listen 443 ssl http2;`).
- Enable `ssl_session_cache shared:SSL:10m;`, `ssl_session_tickets off;`, and OCSP stapling when the CA supports it.
- Add HSTS only after confirming every subdomain serves HTTPS.

## Proxy caching

```nginx
proxy_cache_path /var/cache/nginx/app levels=1:2 keys_zone=app_cache:10m max_size=1g inactive=60m use_temp_path=off;   # http

location /static/ {
    proxy_cache app_cache;
    proxy_cache_valid 200 301 10m;
    proxy_cache_use_stale error timeout updating http_502 http_503 http_504;
    proxy_cache_lock on;
    add_header X-Cache-Status $upstream_cache_status always;
    proxy_pass http://app;
}
```

Never cache responses carrying `Set-Cookie` or per-user data without a vary-aware `proxy_cache_key`.

`proxy_cache_path` creates only the last path component: if the parent directory is missing, `nginx -t` fails with `mkdir() "/tmp/cache/app" failed (2: No such file or directory)` (verified). Create the parent (`mkdir -p /var/cache/nginx`) with ownership for the worker user in the image/unit file.

## WebSockets

```nginx
map $http_upgrade $connection_upgrade { default upgrade; '' close; }   # http

location /ws/ {
    proxy_pass http://app;
    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_read_timeout 1h;
}
```

(With an upstream `keepalive`, the generic location keeps `Connection ""`; WebSocket locations use the map above.)

## Diagnosis quick table

| Symptom | Check |
|---|---|
| 502 | upstream down/refused, wrong `proxy_pass` scheme, SELinux `httpd_can_network_connect` |
| 504 | `proxy_read_timeout`/`proxy_connect_timeout`, slow upstream |
| 413 | `client_max_body_size` |
| Headers missing in upstream | `proxy_set_header` inheritance reset |
| `upstream sent too big header` | raise `proxy_buffer_size` |
| Ephemeral port exhaustion | missing upstream `keepalive` / HTTP/1.1 / empty `Connection` |

## Listen options and kernel limits

```nginx
server {
    listen 443 ssl reuseport backlog=4096;   # reuseport: per-worker listen socket (nginx >= 1.9.1, Linux 3.9+); set once per address:port across all servers
    listen 80  reuseport backlog=4096;
}
```

- `backlog` is capped by `net.core.somaxconn`; also check `net.ipv4.tcp_max_syn_backlog`. Dropped SYNs/accept-queue overflows show up in `nstat -az TcpExtListenDrops TcpExtListenOverflows`.
- `net.ipv4.ip_local_port_range` and `net.ipv4.tcp_tw_reuse` matter for many short upstream connections; the real fix is upstream keepalive.
- `fs.file-max` and the service's `LimitNOFILE` must exceed `worker_rlimit_nofile` x workers. Container CPU quotas: `worker_processes auto` reads host CPUs, so pin an explicit number under cgroup limits.
- `accept_mutex` is off by default since 1.11.3; leave it, unless benchmarks on an old build say otherwise.
- `listen ... deferred` (Linux `TCP_DEFER_ACCEPT`) and `fastopen=N` are niche; enable only with a measured win and a client population that supports them.
- Apply sysctl changes via `/etc/sysctl.d/*.conf` in the host/IaC repo, not from the nginx config; hand verification to `infra-nginx-troubleshoot-run`.

## Timeouts and client limits

```nginx
client_max_body_size      10m;        # 413 otherwise; raise per upload location only
client_body_buffer_size   128k;       # larger bodies spill to client_body_temp_path
client_header_timeout     15s;
client_body_timeout       15s;        # slow-client (slowloris) mitigation
send_timeout              30s;
keepalive_timeout         30s;
keepalive_requests        1000;       # default is 1000 since 1.19.10
proxy_connect_timeout     5s;
proxy_send_timeout        60s;
proxy_read_timeout        60s;
reset_timedout_connection on;
```

Timeouts are per-read/write gap, not total request time. Tutorial values (e.g. 10-12 s) suit small sites; size them from p99 upstream latency.

## SSE / streaming (no buffering)

```nginx
location /events/ {
    proxy_pass http://app;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_buffering off;                 # or: add_header X-Accel-Buffering no; from the app
    proxy_cache off;
    proxy_read_timeout 1h;
    gzip off;
}
```

Test: `curl -N -sS $H/events/` prints events as they arrive (not at the end).

## Client certificates (mTLS)

```nginx
ssl_client_certificate /etc/nginx/ca/clients-ca.pem;
ssl_verify_client      on;                     # `optional` + check $ssl_client_verify for mixed auth
ssl_verify_depth       2;
proxy_set_header X-Client-DN   $ssl_client_s_dn;      # set (not append) so clients cannot spoof it
proxy_set_header X-Client-Verify $ssl_client_verify;
```

Test: `curl --cert c.pem --key c.key --cacert ca.pem https://host/` → 200; without cert → 400.

## Tuning method (from the Codeship/F5/Netdata guidance)

1. Record a baseline with `infra-nginx-benchmark-run` (same host, same payload, same tool flags).
2. Change **one** parameter, reload, re-measure; keep the change only if RPS/latency/error rate improves.
3. Raise `worker_connections` together with `worker_rlimit_nofile` and the OS/systemd limit; verify with `/proc/<worker-pid>/limits`.
4. `worker_processes` above the CPU count rarely helps; `auto` is the default recommendation.
5. Record before/after numbers and hardware in the PR; never ship a tuned value without them.
