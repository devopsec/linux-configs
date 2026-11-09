# Benchmark rig configs

Run all three roles on separate CPUs (containers with `--cpuset-cpus`, or separate hosts). Configs are templates: validate each with `nginx -t` / `openresty -t` before use.

## 1. Stub upstream (fast, static)

```nginx
# upstream.conf (listens :9000)
worker_processes 2;
events { worker_connections 4096; }
http {
    access_log off;
    keepalive_requests 100000;
    server {
        listen 9000 reuseport;
        location = /small  { default_type text/plain; return 200 "ok\n"; }
        location = /delay  { default_type text/plain; echo_sleep 0.05; echo ok; }   # needs echo-nginx-module (OpenResty bundles it)
        location = /big    { alias /srv/payload/1m.bin; }                              # dd if=/dev/urandom of=1m.bin bs=1M count=1
    }
}
```

`echo_sleep` is available in OpenResty (bundled `ngx_echo`); with plain nginx use `/small` and `/big` only.

## 2. SUT (system under test) baseline

```nginx
worker_processes auto;
worker_rlimit_nofile 65535;
events { worker_connections 16384; }

http {
    log_format bench 'rt=$request_time urt=$upstream_response_time uct=$upstream_connect_time st=$status';
    access_log /tmp/bench/access.log bench buffer=256k flush=5s;     # or `off` to measure without logging

    upstream app {
        server 127.0.0.1:9000;
        keepalive 64;
    }

    server {
        listen 8080 reuseport;

        location / {
            proxy_pass http://app;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }

        location = /nginx_status { stub_status; allow 127.0.0.1; allow ::1; deny all; access_log off; }
    }
}
```

Verified on `docker.io/openresty/openresty:alpine` (1.31.8.1): both configs pass `-t`; through-proxy `/small`, `/delay` (~50 ms), and `/big` (1048576 bytes) work; 2000 parallel requests all returned 200; the `rt=`/`urt=`/`uct=` log lines feed the awk percentile snippet in `methodology.md`. `/nginx_status` answers only to `127.0.0.1` as configured, so query it from the SUT host/container (`podman exec sut wget -qO- http://localhost:8080/nginx_status`) or add the generator's IP to `allow`. When the SUT and upstream share one container, start the first instance with `-g 'pid /tmp/up.pid;'` and the second with a different `pid` file.

## 3. A/B variants (change one at a time)

| Variant | Delta against the baseline | Expected effect |
|---|---|---|
| No upstream keepalive | remove `keepalive 64;` and `proxy_http_version`/`Connection ""` | more connect time, TIME_WAIT/ephemeral port pressure |
| Keepalive size | `keepalive 16` vs `64` vs `256` | reuse rate; too small leaks new connections under bursts |
| Buffers | `proxy_buffers 8 64k; proxy_buffer_size 8k;` vs defaults; `proxy_buffering off` | disk spill for large bodies, memory per connection, streaming latency |
| Logging | `access_log off` vs buffered vs unbuffered | CPU/syscall overhead |
| Gzip | `gzip on; gzip_comp_level 1/5/9` | CPU vs bytes; test with a compressible `/json` payload |
| TLS | `ssl_session_cache shared:SSL:10m`, TLS 1.2 vs 1.3, `http2 on` | handshake CPU, resumption rate (`h2load`, `openssl s_time`) |
| Workers | `worker_processes 1/2/auto` and `worker_connections` | scaling with cores |
| Cache | `proxy_cache` with a hot key | latency collapse, hit ratio via `$upstream_cache_status` |

Container sketch (podman, rootless; fully qualified names; limits via cpuset):

```bash
mkdir -p /tmp/bench && chmod a+rwx /tmp/bench
podman run -d --rm --name up  --cpuset-cpus 0   -p 9000:9000 -v /tmp/bench/upstream.conf:/etc/nginx/nginx.conf:ro,Z docker.io/library/nginx:stable
podman run -d --rm --name sut --cpuset-cpus 1-2 -p 8080:8080 --network host -v /tmp/bench/sut.conf:/etc/nginx/nginx.conf:ro,Z -v /tmp/bench:/tmp/bench:Z docker.io/library/nginx:stable
# generator on cores 3+ (taskset -c 3-4 wrk ...)
```

(With `--network host` skip `-p`; use `127.0.0.1` for the upstream address. Keep only one network mode per container.)

## 4. TLS handshake test

```bash
openssl s_time -connect SUT:8443 -new  -time 15   # full handshakes/s
openssl s_time -connect SUT:8443 -reuse -time 15  # resumed sessions/s (needs ssl_session_cache)
h2load -n50000 -c50 -m10 https://SUT:8443/        # HTTP/2 multiplexed
```

## 5. Fast sanity check without extra tools

```bash
# poor-man's rate probe: 2000 requests, 50 parallel (xargs)
seq 2000 | xargs -P50 -I{} curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://SUT:8080/ | sort | uniq -c | sort -rn | head
```
