# Benchmark report template

```markdown
## nginx benchmark: <title>

**Question / pass criteria:** <e.g. p99 < 50 ms at 5k RPS, 0 errors>

### Environment
- nginx/OpenResty: <version>, build flags relevant: <ssl, http_v2, lua>
- SUT: <cores/RAM, container limits, kernel>; upstream: <stub|real app>; generator: <host, tool+version>
- Network path: <loopback|LAN>, TLS: <none|1.2|1.3>, HTTP: <1.1|2>, keepalive: <client/upstream>
- Payload: <size, headers>; connections: <n>; rate: <fixed R|closed loop>; warm-up: <s>; measure: <s>; repeats: <n>

### Results (median of N runs; spread in parentheses)
| Variant | RPS | p50 | p90 | p99 | p99.9 | max | non-2xx | socket errors | worker CPU | gen CPU |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline | | | | | | | | | | |
| change 1: <what> | | | | | | | | | | |

### Saturation
- Knee at <rate>; first bottleneck: <CPU|FDs|ports|upstream|network>; evidence: <stub_status, ss -s, perf, logs>

### Decision
- Keep / revert per change, with the number that justifies it and the variation threshold used.

### Not tested / caveats
- <payload sizes, TLS, long soak, multi-host, cold cache ...>

### Reproduce
- Config revisions (commit/hash), exact commands, files in /tmp/bench (or user-chosen path).
```

Raw outputs (tool stdout, `stub_status` before/after, `ss -s`, log excerpts) belong next to the report, not pasted into it.
