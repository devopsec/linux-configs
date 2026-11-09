# nginx / OpenResty troubleshooting runbook

Messages marked **[repro]** were reproduced in a container (OpenResty 1.31.8.1) and the text is exact (variable parts elided). Others are the standard nginx messages; confirm the exact wording in your logs.

## Status code map

| Status | Meaning in nginx context | First checks |
|---|---|---|
| 400 | malformed request, plain HTTP sent to a TLS port, header too large (`client sent too long header line`, `large_client_header_buffers`) | error.log message, client, `listen ... ssl` |
| 401/403 | auth/ACL/permissions: `auth_basic`, `allow/deny`, file permissions | error.log `access forbidden by rule`, `(13: Permission denied)` |
| 404 | no matching file/route; wrong `root`/`alias`/`proxy_pass` URI | `nginx -T` location order, `error.log` `open() ... failed (2: ...)` |
| 413 | body over `client_max_body_size` | **[repro]** `client intended to send too large body: 3000 bytes` |
| 429 | `limit_req`/`limit_conn` (or app) | `limiting requests, excess: ... by zone "<name>"` |
| 499 | client closed the connection before the response (nginx-specific) | client timeouts, slow upstream, LB idle timeout shorter than the backend |
| 502 | nginx could not get a valid response from the upstream | upstream down/refused, protocol mismatch, header too big, reset |
| 503 | `limit_req_status`, maintenance, or no live upstreams | error.log |
| 504 | upstream too slow (`proxy_read_timeout`/`proxy_connect_timeout`) | upstream latency, timeouts |

## Error-log messages

| Message (pattern) | Cause | Check | Fix |
|---|---|---|---|
| **[repro]** `connect() failed (111: Connection refused) while connecting to upstream` | upstream not listening / wrong port or host / container not up | `ss -ltnp \| grep :<port>`; `curl` the upstream directly; `$upstream_addr` in access log | start/fix upstream; correct `proxy_pass`/upstream; add `proxy_next_upstream` + more servers |
| `connect() failed (113: No route to host)` / `(110: Connection timed out) while connecting` | network/firewall/SG, wrong IP | `traceroute`, `nc -vz host port`, firewall rules | fix routing/firewall; lower `proxy_connect_timeout` to fail fast |
| **[repro]** `upstream timed out (110: Operation timed out) while reading response header from upstream` -> 504 | upstream slower than `proxy_read_timeout` (default 60s) | `$upstream_response_time` distribution, upstream logs/CPU | fix slow endpoint; raise timeout only for known long routes; avoid retries of non-idempotent requests |
| **[repro]** `no live upstreams while connecting to upstream` -> 502 | all servers in the upstream marked `down` or failed (`max_fails`/`fail_timeout`) | `nginx -T` upstream block; recent connect errors | restore servers; tune `max_fails`/`fail_timeout`; health checks (Plus) or passive checks |
| **[repro]** `upstream sent too big header while reading response header from upstream` -> 502 | response headers exceed `proxy_buffer_size` | which route; header sizes via `curl -D-` to the upstream | raise `proxy_buffer_size` (and `proxy_buffers`/`proxy_busy_buffers_size` accordingly); reduce cookies/headers |
| `recv() failed (104: Connection reset by peer) while reading response header from upstream` | upstream crashed/closed, keepalive race, idle timeout shorter than nginx's | upstream logs; compare upstream keepalive idle timeout with nginx reuse | align timeouts (upstream idle > nginx `keepalive_timeout` for upstream), `proxy_next_upstream` |
| `upstream prematurely closed connection while reading response header from upstream` | upstream died mid-request (crash/OOM/timeout) | upstream crash logs, OOM killer | fix upstream; limit request size; retries for idempotent requests only |
| `[alert] N worker_connections are not enough` | connection limit hit per worker | `stub_status` (accepts vs handled), connections per worker | raise `worker_connections` and `worker_rlimit_nofile`; add keepalive; scale out |
| `[crit] ... (24: Too many open files)` (`accept4()`, `socket()`, `open()`) | FD limit | `/proc/<worker>/limits`, `ls /proc/<worker>/fd \| wc -l`, `systemctl show nginx -p LimitNOFILE` | `worker_rlimit_nofile`, systemd `LimitNOFILE`, container ulimit |
| `bind() to 0.0.0.0:80 failed (98: Address already in use)` | another process or old instance | `ss -ltnp \| grep :80` | stop the other listener; fix duplicate `listen` |
| `host not found in upstream "app"` (startup, `[emerg]`) | name resolved at start, not resolvable (container order, DNS) | `getent hosts app`, start order | start dependency first; use `resolver` + variable `proxy_pass` for dynamic names (see caveats in `dev-nginx-config-manage`) |
| `no resolver defined to resolve <host>` | variable in `proxy_pass` without `resolver` | `nginx -T` | add `resolver` with valid DNS and sane `valid=` |
| `open() "..." failed (13: Permission denied)` | file permissions/SELinux/AppArmor | `namei -l <path>`, run-as user, `ausearch -m avc` | fix permissions/context |
| `connect() to ... failed (13: Permission denied) while connecting to upstream` | SELinux blocks nginx outbound | `getsebool httpd_can_network_connect`, `ausearch -m avc -ts recent` | `setsebool -P httpd_can_network_connect 1` (approved) |
| `SSL_do_handshake() failed (SSL: error:... ) while SSL handshaking` | client protocol/cipher mismatch, bad cert chain, SNI | `openssl s_client -connect host:443 -servername name`, error text | align `ssl_protocols`/ciphers; fix chain; see `sec-tls-config-audit` |
| `SSL_CTX_use_PrivateKey ... key values mismatch` (start/reload) | cert/key do not match | `openssl x509 -noout -modulus -in crt \| md5sum` vs key | use the matching pair |
| `an upstream response is buffered to a temporary file` / `a client request body is buffered to a temporary file` | buffers too small for payload | payload sizes | tune `proxy_buffers`/`client_body_buffer_size`; `proxy_buffering off` for streaming |
| `limiting requests, excess: N by zone "name"` | `limit_req` rejecting | traffic pattern, key (CDN IP?) | tune rate/burst; key on real client IP; allow-list health checks |
| `worker process N exited on signal 11` | crash (module, Lua, FFI) | core dump, last request in access log, module versions | disable suspect module/Lua code; upgrade; collect backtrace |
| `[emerg] unknown directive` / `directive is not allowed here` | typo, module missing, wrong context | `nginx -t`, `nginx -V` | fix per docs |
| `[emerg] ... "worker_processes" directive is duplicate` etc. | duplicate/included twice | `nginx -T \| grep -n` | remove duplicate include |
| `[info] client ... closed keepalive connection` | client closed an idle keepalive (normal) | ignore | none; filter out at `info` |

## Playbooks

### Intermittent 502 right after deploys/restarts
1. Check the access log `$upstream_addr`/`$upstream_status` for the failing instance.
2. If errors are `connect() failed (111)` during rollout: add readiness gating before traffic; use `proxy_next_upstream error timeout http_502` with `proxy_next_upstream_tries 2` for idempotent methods only.
3. If `recv() failed (104)` on reused connections: upstream closes idle keepalive earlier than nginx expects; raise upstream idle timeout or lower nginx upstream `keepalive_timeout` (nginx >= 1.15.3 supports `keepalive_timeout` in `upstream`).

### 504s under load
1. Compare `urt` (`$upstream_response_time`) with `rt`: if `urt` ~ `rt`, the upstream is slow; if `rt` >> `urt`, nginx or the client side is the bottleneck (buffering to slow clients, CPU).
2. Check upstream saturation and queueing; check worker CPU.
3. Only then consider raising timeouts; reproduce with `infra-nginx-benchmark-run`.

### New connections refused/dropped at the edge
1. `nstat -az TcpExtListenOverflows TcpExtListenDrops` increasing -> accept queue overflow: raise `backlog=` on `listen` and `net.core.somaxconn`, ensure workers accept fast.
2. `stub_status`: `accepts` greater than `handled` -> `worker_connections` exhausted.
3. `ss -ltn` for the listening port: `Recv-Q` near `Send-Q` means the accept queue is full.

### Ephemeral port exhaustion to upstream
Signs: `connect() failed (99: Cannot assign requested address)`, large TIME_WAIT counts (`ss -s`). Fix: upstream `keepalive`, `proxy_http_version 1.1`, `proxy_set_header Connection ""`; widen `net.ipv4.ip_local_port_range`; add upstream IPs/ports.

### Config change has no effect
1. `nginx -t` passes but reload failed? Check `error.log` right after the reload and `journalctl -u nginx`.
2. Old workers lingering: `ps -ef \| grep 'nginx: worker process is shutting down'` -> long-lived connections keep old config; set `worker_shutdown_timeout` or restart in a window (approval).
3. Configuration came from a different file/prefix: `nginx -T \| head`, `ps -o args= -p <master>`.
4. Another layer caches: browser, CDN, `proxy_cache`, `expires`.

### Wrong or stale TLS certificate
`openssl s_client -connect host:443 -servername name </dev/null 2>/dev/null \| openssl x509 -noout -subject -enddate -issuer`; compare with the files on disk; reload picks up renewed files (certificates are read at reload); with `ssl_certificate_by_lua*` check the SNI allow-list and cached cdata (per-worker, refreshed only on reload).

### Reproduce a failure in a lab (copy)

```nginx
upstream dead { server 127.0.0.1:9999; }          # -> 502 connect() failed (111)
location /slow { proxy_read_timeout 1s; proxy_pass http://slow; }   # slow upstream sleeping 3s -> 504
location /up   { client_max_body_size 1k; proxy_pass http://slow; } # POST 3000 bytes -> 413
location /big  { proxy_buffer_size 1k; proxy_pass http://bighdr; } # header 5000 bytes -> 502 too big header
```

Run with `openresty -c <file> -g 'daemon off;'` in a container and `curl` each path; compare messages with the table above.
