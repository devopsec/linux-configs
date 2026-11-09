---
name: infra-nginx-benchmark-run
description: "Load-test, benchmark, and validate tuning of nginx/OpenResty reverse proxies: baseline vs candidate comparisons, wrk/wrk2/hey/oha/k6/vegeta/h2load runs, capacity and keepalive/buffer/worker/TLS tuning verification, latency percentiles, saturation and error-rate analysis. Use when a task asks to benchmark, load test, stress test, measure throughput/latency, size worker_connections or upstream keepalive, or prove a tuning change helped. Not for writing the config (use dev-nginx-config-manage) and not for diagnosing a live incident (use infra-nginx-troubleshoot-run)."
metadata:
  author: Junie
  license: MIT
---

# nginx / OpenResty benchmarking and tuning validation

Goal: produce trustworthy before/after numbers for a proxy configuration. A benchmark without a baseline, fixed method, and error rate is not evidence.

## Triggers

- "Is this tuning change actually faster?" / "How many RPS can this proxy do?"
- Size `worker_processes`, `worker_connections`, `worker_rlimit_nofile`, upstream `keepalive`, buffers, caching, rate limits, TLS session reuse, HTTP/2.
- Regression check of a new config or OpenResty/Lua handler under load.
- Find the saturation point (what breaks first: CPU, file descriptors, ports, upstream, network).

## Load order (SAD KITTI)

```sadkitti
REQUIRE target (staging/local rig, never production without explicit approval), nginx/OpenResty version, hardware/container limits
REQUIRE goal: throughput ceiling, latency SLO (p99 at a rate), or A/B comparison of two configs
REFERENCE "references/methodology.md"
IF building a local rig (SUT + stub upstream + load generator)
  REFERENCE "references/rig-configs.md"
IF reporting results
  REFERENCE "references/report-template.md"
IF the SUT contains Lua hot paths
  REFERENCE skill "infra-openresty-profile-run"
IF the run shows errors, resets, or timeouts rather than just slow responses
  REFERENCE skill "infra-nginx-troubleshoot-run"
CACHE only the commands and thresholds relevant to the chosen tool
```

## Rules

1. Benchmark only systems you own, in staging or a local rig. Production load tests need explicit approval, a rate cap, and a stop condition. Never aim load at third-party hosts.
2. Always record a **baseline** with the exact same method before changing anything; change **one** parameter per run; repeat each run at least 3 times and report the median and spread.
3. Separate roles: load generator, nginx (SUT), and upstream on different CPUs/hosts (or pinned cores). If the generator is saturated, the numbers measure the generator.
4. Use a fixed-rate tool for latency (wrk2, `oha -q`, `vegeta attack -rate`, k6 `constant-arrival-rate`) to avoid coordinated omission; use closed-loop tools (wrk, ab, hey) only for peak-throughput estimates and say so.
5. Warm up (connections, caches, JIT, TLS sessions) for 10-30 s and discard it; measure steady state for at least 60 s.
6. Report p50/p90/p99/p99.9, max, RPS, error/non-2xx rate, socket errors/timeouts, and resource usage (CPU per nginx worker, load generator CPU, FDs, TIME_WAIT, upstream connections). RPS without percentiles and error rate is meaningless.
7. Check the stub upstream first: if it is slower than nginx, you are benchmarking the upstream. Use a fast static upstream (nginx `return 200`) to measure the proxy path itself.
8. Keep payload, headers, keepalive behavior, TLS version/cipher, HTTP version, and connection counts identical between runs; state them in the report.
9. Stop the run and report if error rate exceeds the agreed threshold (default: >1% non-2xx or any socket errors at the baseline rate), instead of pushing harder.
10. Do not tune sysctl/ulimit on a shared host without approval; record every system change and revert it.

## Workflow

1. Define the question and pass/fail criteria (e.g. p99 < 50 ms at 5k RPS, no errors).
2. Prepare the rig (`references/rig-configs.md`): SUT with `stub_status` and timing `log_format`, stub upstream, generator limits (`ulimit -n`), pinned CPUs.
3. Sanity check: single `curl -w` timing, then a 10 s smoke run at low rate.
4. Baseline: warm-up, 3 measured runs, collect generator output + nginx `stub_status` before/after + `ss -s` + CPU.
5. Apply one change (reload gracefully), repeat the identical runs.
6. Find the ceiling by stepping the rate (e.g. 1k, 2k, 4k, 8k RPS) until p99 or errors break the criteria; note the first bottleneck.
7. Report with the template; recommend keep/revert per change with numbers, and list what was not tested.

## Safety

- Confirm the target before every run; echo the URL and rate in the plan. Cap duration and rate.
- Scratch configs, results, and scripts go in `/tmp`, not the repo; results worth keeping go to a docs path chosen by the user.
- Do not store credentials/tokens in load scripts; use env vars.
- Containers: use fully qualified image names (podman) and bind-mount configs read-only; make files readable by the unprivileged worker user.

## Related skills

- Authoring the config being tested → `dev-nginx-config-manage`
- OpenResty/Lua code under test → `dev-openresty-config-manage`, `infra-openresty-profile-run`
- Errors/timeouts during the run → `infra-nginx-troubleshoot-run`
- Generic reverse proxy operations → `infra-nginx-reverseProxy-manage`

## References

- [references/methodology.md](references/methodology.md) — tools and exact commands, interpretation, bottleneck table.
- [references/rig-configs.md](references/rig-configs.md) — SUT/upstream configs, A/B variants (keepalive, buffers, TLS).
- [references/report-template.md](references/report-template.md) — results report skeleton.
