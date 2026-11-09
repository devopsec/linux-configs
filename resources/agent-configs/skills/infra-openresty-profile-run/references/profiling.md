# OpenResty profiling techniques

Check tool flags with `--help` for the installed versions. Items marked **(verified)** were run in the OpenResty container used for these skills (`docker.io/openresty/openresty:alpine-fat`, 1.31.8.1); the others are standard documented techniques that need the host tools installed.

## Symptom → technique

| Symptom | Technique | Notes |
|---|---|---|
| Workers ~100% CPU, RPS low | CPU flame graph (C stacks with `perf`; Lua stacks with SystemTap toolkit or OpenResty XRay) | start with `top -H -p <worker>` and `perf top -p <worker>` |
| All requests slow together, CPU low | blocked event loop: `strace -c -f -p <worker>` for blocking syscalls; code review for `io.open`, `os.execute`, `io.popen`, LuaSocket, big `get_keys` | cosockets never block; plain Lua I/O does |
| Latency spikes at intervals | GC pauses, cache lock, timers, log flush | correlate with `lua_gc_kb` sawtooth, timer counts, `access_log buffer=` flush interval |
| Memory growth | Lua heap (`collectgarbage("count")`), shared dict usage, nginx pools (RSS vs Lua KB) | RSS growing but Lua KB flat = C-level (FFI/modules/buffers) |
| "no memory" from shdict | `free_space()`/`capacity()` trend, TTL review | see runtime-metrics.md |
| Suspect JIT trace aborts | LuaJIT verbose/profiler on a test script | **(verified)** `resty -j v script.lua` prints `[TRACE ...]` lines; `jit.p` profiler module loads |
| One handler slow | per-phase timing with `ngx.update_time()` + `ngx.now()` | runtime-metrics.md |

## Cheap checks first

```bash
top -H -p $(pgrep -f 'nginx: worker' | head -1)           # per-thread CPU
cat /proc/<worker>/status | grep -E 'VmRSS|VmData|Threads'
strace -c -f -p <worker> -- sleep 10                       # syscall time summary; blocking calls stand out
curl -s http://localhost:8080/_lua_stats                   # runtime-metrics.md endpoint (ACL allows 127.0.0.1 and ::1)
```

## CPU flame graphs

### A. perf (C-level stacks; any Linux, needs perf + FlameGraph scripts)

```bash
perf record -F 99 -g -p <worker-pid> -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > /tmp/worker.svg
```

Shows nginx/LuaJIT interpreter/PCRE/OpenSSL/zlib hot spots. Lua function names are not resolved by default; use the Lua-aware methods below for that. Use `-F 99` (not higher) on production.

### B. OpenResty SystemTap toolkit + stapxx (Lua-level stacks)

From the `openresty-systemtap-toolkit` project (needs SystemTap, kernel debuginfo, and usually root):

```bash
./ngx-sample-lua-bt -p <worker-pid> --luajit20 -t 5 > /tmp/a.bt     # flavor flag: check --help (luajit20 / lua51)
./fix-lua-bt /tmp/a.bt > /tmp/b.bt
stackcollapse-stap.pl /tmp/b.bt > /tmp/c.cbt
flamegraph.pl /tmp/c.cbt > /tmp/lua.svg
```

Heavy tooling: prefer a rig. Alternative: **OpenResty XRay** (commercial, agent-based, continuous Lua-level flame graphs, GC object analysis, memory leak analysis). The OpenResty site mentions XRay and AI-assisted flame-graph analysis; treat vendor claims as leads to verify with your own before/after benchmark.

### C. LuaJIT built-in profiler (rig/dev, script-level)

```bash
resty -e 'local p = require "jit.p"; p.start("f", "/tmp/prof.txt"); -- run the code under test; p.stop()'
# "f" = function-level, add "l" for line-level; output is a sorted percentage list
```

**(verified)** `jit.p` loads in `resty` and writes a profile. For code inside nginx phases, drive it from a rig location behind a debug flag and remove it afterwards.

## Blocking detection

1. `strace -c -f -p <worker>` over 10 s: large time in `read`/`pread64`/`openat`/`fsync`/`flock` from a worker = blocking I/O in Lua or modules (static file reads from slow disks included).
2. Search the code for `io.open`, `io.popen`, `os.execute`, `require "socket"`, `ngx.shared.DICT:get_keys`, big `string.rep`/regex on request bodies.
3. Log warnings when a section exceeds a threshold (runtime-metrics.md per-phase timing).
4. `lua_socket_log_errors on;` and error-log lines like `lua tcp socket read timed out` indicate cosocket waits, not blocking.

## GC and memory

```lua
-- per worker, via the stats endpoint: collectgarbage("count") in KB (Lua heap)
-- ad-hoc only (stop-the-world): collectgarbage("collect")  -- debug, never on a schedule in production
```

- Leak pattern: heap rises monotonically across steady load. Typical causes: module-level tables keyed by request data, closures capturing request objects in timers, unbounded in-process caches (use `resty.lrucache` with a size limit), global variables.
- Large per-request allocations (`table.concat` of big bodies, JSON of large payloads) raise GC pressure: stream where possible, reuse tables (`table.clear`), avoid copies from `dict:get` for big values.
- Per-worker caches multiply memory by worker count; compare with a shared dict (cost: serialization and lock contention).

## Contention

- Shared dict calls take a zone-level lock: many `get/set` per request on one dict under high concurrency show up as CPU in the slab/lock code in `perf`. Split hot counters into several dicts, or aggregate per worker and flush with a timer.
- `resty.lock` and cache-miss stampedes: use `resty.lock` or stale-while-revalidate to protect backends.

## Reporting

- Table: symptom, technique, evidence (top 5 frames with %, GC trend, shdict trend), root cause, fix, before/after benchmark (same load), residual risk.
- Attach flame graph SVGs or paths (in `/tmp` or a user-chosen docs location), not inline.
