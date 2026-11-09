# Benchmark methodology for nginx / OpenResty

Verify tool flags with `<tool> --help` for the installed version; flags below are the commonly documented ones.

## Choose the tool

| Goal | Tool | Notes |
|---|---|---|
| Peak throughput (closed loop) | `wrk -t<threads> -c<conns> -d60s --latency URL` | threads <= generator cores; latency numbers under saturation are distorted (coordinated omission) |
| Latency at a fixed rate | `wrk2 -t2 -c100 -d60s -R5000 --latency URL` | constant throughput, correct percentiles |
| Simple, scriptable | `oha -z 60s -q 2000 -c 100 URL` / `hey -z 60s -q 20 -c 100 URL` | `oha -q` is per-connection rate in some versions: check help; `hey -q` is per-worker |
| Scenarios, thresholds, CI | `k6 run` with `constant-arrival-rate` executor and `thresholds` | JS scripts, good for checks and pass/fail exit codes |
| Open-model, JSON results | `echo "GET URL" \| vegeta attack -rate=2000 -duration=60s \| vegeta report` | also `vegeta report -type=hist[0,10ms,50ms,100ms]` |
| HTTP/2 / TLS handshake focus | `h2load -n100000 -c100 -m10 https://host/` | `-m` = concurrent streams per connection |
| Quick sanity only | `ab -n 10000 -c 100 -k URL` | HTTP/1.0 default without `-k`, single thread: not for tuning decisions |
| Single request timing | `curl -sS -o /dev/null -w 'dns=%{time_namelookup} connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' URL` | use before any load run |

## Run template

```bash
# 0. environment (record in the report)
nginx -v; nproc; uname -r; ulimit -n
# 1. generator limits
ulimit -n 65535
# 2. warm-up (discard)
wrk -t2 -c100 -d20s http://SUT:8080/ >/dev/null
# 3. snapshot counters before
curl -s http://SUT:8080/nginx_status > /tmp/bench/status.before
# 4. measured run (repeat 3x)
wrk2 -t2 -c200 -d60s -R5000 --latency http://SUT:8080/ | tee /tmp/bench/run1.txt
# 5. snapshot after + system state
curl -s http://SUT:8080/nginx_status > /tmp/bench/status.after
ss -s
```

`stub_status` fields: `Active connections`, `accepts handled requests` (`accepts != handled` means dropped connections, usually `worker_connections` exhausted), `Reading/Writing/Waiting`.

Server-side latency from the log (see rig-configs `log_format`):

```bash
# p50/p90/p99 of request_time from the access log (rt=... field)
awk '{for(i=1;i<=NF;i++) if($i ~ /^rt=/){sub("rt=","",$i); print $i}}' /tmp/bench/access.log | sort -n \
 | awk '{a[NR]=$1} END{print "p50",a[int(NR*.5)],"p90",a[int(NR*.9)],"p99",a[int(NR*.99)]}'
```

## Interpreting results

| Observation | Likely bottleneck | Next check |
|---|---|---|
| nginx worker CPU ~100% each, RPS flat | CPU bound on proxy (TLS, gzip, Lua) | `perf top -p <worker>`; offload gzip/TLS; for Lua see `infra-openresty-profile-run` |
| Generator CPU ~100% | generator bound | more threads/hosts, or lower rate |
| Latency climbs while nginx CPU low | upstream slow/queueing, or too few upstream keepalive connections | `$upstream_response_time` vs `$request_time`; `keepalive`; upstream CPU |
| Non-2xx 502/504 grow with rate | upstream failures/timeouts | error.log `upstream timed out`, `connect() failed` |
| Socket errors `connect`/`read` on generator | `worker_connections`, `somaxconn`, backlog, FDs | `stub_status accepts-handled`, `nstat -az TcpExtListenDrops`, `/proc/<pid>/limits` |
| `Cannot assign requested address` on generator or nginx | ephemeral port exhaustion (no keepalive) | upstream `keepalive`, HTTP/1.1, empty `Connection`; `ss -s` TIME_WAIT |
| p99 spikes every N seconds | GC (Lua), cache lock, upstream health checks, log flush | time-correlate with logs, `lua` GC stats |
| Throughput scales with `-c` but p99 explodes | queueing past saturation | compare at fixed rate below the knee |

## A/B discipline

- Same binary, same host, same time window; alternate A and B runs (A B A B) to cancel drift.
- Changes worth testing one at a time: `keepalive` on upstream, `proxy_buffering`/buffer sizes, `worker_processes`/`worker_connections`, `gzip` level, `ssl_session_cache`/TLS version, HTTP/2, `proxy_cache`, `sendfile`/`tcp_nopush` for static, `open_file_cache`, `reuseport`.
- Accept a change only if the improvement exceeds run-to-run variation (e.g. >5% median improvement and no worse tail/errors).
- Different payload sizes behave differently: test small (1 KB), medium (64 KB), and large (>= 1 MB, exercises buffering/sendfile) responses.

## Method sources

- Codeship "Tuning NGINX": change one parameter (`worker_processes`, then `worker_connections`, with `worker_rlimit_nofile`) and re-measure after each step.
- F5/NGINX tuning posts and Netdata worker-connection guide: file-descriptor chain (`worker_rlimit_nofile` >= 2 x `worker_connections`), listen-queue drops via `nstat`, container CPU quotas (`worker_processes auto` reads host CPUs).
- Always confirm directive details in <https://nginx.org/en/docs/>.
