---
name: infra-openresty-profile-run
description: "Profile and measure OpenResty / Lua behavior on a running instance or test rig: CPU hot spots and flame graphs, blocked event loop, Lua GC and memory growth, shared dict exhaustion, timer backlog, per-phase latency, LuaJIT trace aborts. Use when OpenResty workers use high CPU, p99 latency is caused by Lua code, memory grows, lua_shared_dict fills up, or a Lua change needs performance evidence. Operational and measurement focused; not for writing Lua (use dev-openresty-config-manage) and not for generic nginx load tests (use infra-nginx-benchmark-run)."
metadata:
  author: Junie
  license: MIT
---

# OpenResty / Lua profiling and runtime measurement

Goal: locate the cost (CPU, blocking, memory, contention) with evidence before anyone rewrites Lua code.

## Triggers

- Worker CPU high while RPS is modest; latency that tracks Lua handlers.
- Event loop stalls (all requests slow together, other routes affected).
- Lua memory growth, GC pauses, `lua_shared_dict` "no memory" or forced evictions.
- Timer backlog (`lua_max_pending_timers` / `lua_max_running_timers` warnings).
- Evidence needed that a Lua optimization helped (pairs with `infra-nginx-benchmark-run`).

## Load order (SAD KITTI)

```sadkitti
REQUIRE OpenResty version, LuaJIT flavor, where it runs (host/container), whether it is production, load profile
REFERENCE "references/profiling.md"
IF adding in-process counters, histograms, or health endpoints
  REFERENCE "references/runtime-metrics.md"
IF coding rules for fixes are needed
  REFERENCE skill "dev-openresty-config-manage"
IF a load generator is needed to reproduce
  REFERENCE skill "infra-nginx-benchmark-run"
IF errors/timeouts rather than slowness
  REFERENCE skill "infra-nginx-troubleshoot-run"
CACHE only the technique chosen for the symptom
```

## Rules

1. Start with cheap, safe measurements (in-process counters, `stub_status`, `top`, per-request timing) before sampling profilers or tracing; keep production overhead low and ask before attaching anything to a production worker.
2. Classify the symptom first: CPU-bound (workers at ~100%), blocked (syscalls like `read`/`open`/`fsync` in `strace -c`), memory (Lua heap vs shared dicts vs nginx pools), or waiting (upstream, cosocket timeouts).
3. Profile **under realistic load** on a rig first; replay the production pattern with `infra-nginx-benchmark-run`.
4. Report hot paths as percentages of samples with the Lua stack/function names, not guesses; compare before and after with the same load.
5. Time with `ngx.update_time()` then `ngx.now()` (nginx caches time per event-loop iteration; `ngx.hrtime` is not available in all builds). Never use blocking timers or `os.clock()` for wall time.
6. Do not change `lua_code_cache`, GC parameters, or shared dict sizes on production without approval; verify any change on the rig first.
7. Remove temporary debug endpoints and logging after the investigation; restrict permanent stats endpoints with `allow`/`deny`.
8. LuaJIT claims must be checked against the NYI table (see `dev-openresty-config-manage/references/luajit-performance.md`); `pcall`, `pairs`, and `ipairs` do not abort traces.

## Workflow

1. Baseline: RPS, p50/p99 per route, worker CPU, `stub_status`, error log level `warn` or above clean.
2. Add or read in-process stats (`references/runtime-metrics.md`): Lua GC KB per worker, shdict free space vs capacity, timer counts, per-route latency buckets.
3. Pick the technique from the symptom table in `references/profiling.md`.
4. Capture evidence (flame graph / `strace -c` / GC trend / shdict trend) under steady load for 30-60 s.
5. Form one hypothesis; change one thing on the rig; re-measure.
6. Report: symptom, evidence, root cause, fix, before/after numbers, remaining risk.

## Safety

- Sampling with `perf`/SystemTap/eBPF can slow production workers and needs privileges: ask first, keep captures short (30 s), and run against one worker PID.
- Stats endpoints expose internals: loopback or admin network only.
- Keep captures in `/tmp`; they contain function names and may contain data fragments.

## Related skills

- Writing/refactoring Lua → `dev-openresty-config-manage`
- Load testing → `infra-nginx-benchmark-run`
- Live incident diagnosis → `infra-nginx-troubleshoot-run`

## References

- [references/profiling.md](references/profiling.md) — symptom-to-technique table, flame graph pipelines, GC/memory, blocking detection, LuaJIT profiler.
- [references/runtime-metrics.md](references/runtime-metrics.md) — verified in-process stats module (GC, shdict, timers, latency histogram).
