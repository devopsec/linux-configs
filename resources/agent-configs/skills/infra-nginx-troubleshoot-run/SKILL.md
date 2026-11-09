---
name: infra-nginx-troubleshoot-run
description: "Diagnose live nginx/OpenResty reverse proxy problems on a running host or container: 502/503/504/499/413/400 spikes, upstream timeouts, connection refused, 'worker_connections are not enough', 'too many open files', listen queue drops, TIME_WAIT/ephemeral port exhaustion, slow responses, TLS handshake failures, reload that does not take effect, SELinux denials, crashed workers. Use when a task says nginx is returning errors, is slow, drops connections, will not reload, or needs log/socket/kernel-counter analysis. Read-only first; not for authoring config (use dev-nginx-config-manage) and not for load testing (use infra-nginx-benchmark-run)."
metadata:
  author: Junie
  license: MIT
---

# nginx / OpenResty live troubleshooting

Goal: go from symptom to evidence-backed cause with read-only commands, then propose a minimal fix for approval.

## Triggers

- Elevated 5xx/4xx rates, latency spikes, connection resets, timeouts.
- nginx fails to start/reload, or a change "does not take effect".
- Resource exhaustion suspicion: file descriptors, ports, listen queue, memory, CPU.
- TLS errors, wrong certificate, SELinux/permission denials, crashed workers.

## Load order (SAD KITTI)

```sadkitti
REQUIRE symptom, time window, affected route/host, recent changes (config, deploy, certs, traffic)
REQUIRE access to nginx error log, access log, `nginx -T` output (redact secrets), and process/socket state
REFERENCE "references/runbook.md"
IF collecting evidence or checking system state
  REFERENCE "references/commands.md"
IF the cause is a config mistake
  REFERENCE skill "dev-nginx-config-manage"
IF the cause is Lua code, GC, shared dict, or timers
  REFERENCE skill "infra-openresty-profile-run"
IF capacity or tuning must be proven
  REFERENCE skill "infra-nginx-benchmark-run"
CACHE only the matching runbook entries
```

## Rules

1. Read-only first: logs, `nginx -T`, `ss`, `/proc`, counters. No reloads, restarts, config edits, sysctl changes, or packet captures of production traffic without approval.
2. Anchor on the **first** error in the window, not the loudest; correlate error-log lines with access-log status/timings (`$request_time`, `$upstream_response_time`, `$upstream_addr`, `$upstream_status`).
3. Split the path: client → (LB/CDN) → nginx → upstream. Show where the failure originates with evidence (e.g. status 502 with `connect() failed` = nginx could not reach the upstream; 499 = client left; 504 = upstream too slow).
4. State a hypothesis, the command that would falsify it, and the result; do not stack guesses.
5. Compare the running config with the repo (`nginx -T` vs committed files); the running process may predate the file (a reload may have failed silently).
6. Redact tokens, cookies, `Authorization` headers, private keys, and client IPs when quoting logs.
7. Propose the smallest fix, its verification command, and a rollback; apply only after approval.

## Workflow

1. Reproduce or bound the symptom: `curl -sS -D- -o /dev/null -w '%{time_connect} %{time_starttransfer} %{time_total}\n' URL` against nginx and, separately, against the upstream directly.
2. Pull `error.log` for the window and summarize by message pattern (`references/commands.md`); map each to the runbook.
3. Summarize `access.log`: status distribution, slowest routes, upstream timings.
4. Check resource state: worker FD usage vs limits, `ss -s`, listen queue, `nstat` drops, CPU/memory, `stub_status`.
5. Check recent change: config diff, cert expiry, deploy, upstream health, DNS.
6. Confirm the root cause with one discriminating test, then report evidence + fix + verification + rollback.

## Output format

- **Symptom** (what/when/how much) → **Evidence** (command + key lines) → **Root cause** → **Fix** (diff or command, needs approval) → **Verify** → **Prevention** (alert, limit, config).

## Safety

- Mark any command that changes state; ask before running it.
- Packet captures can contain secrets/PII: capture headers only, short, with approval, store in `/tmp`.
- Debug logging (`error_log ... debug`) is verbose and may log request data; scope with `debug_connection` and turn off afterwards.

## Related skills

- Config authoring/review → `dev-nginx-config-manage`
- Lua/OpenResty profiling and runtime issues → `infra-openresty-profile-run`, `dev-openresty-config-manage`
- Reproducing under load / sizing → `infra-nginx-benchmark-run`
- TLS audit and certificates → `sec-tls-config-audit`, `sec-tls-acme-manage`
- Generic reverse proxy operations → `infra-nginx-reverseProxy-manage`

## References

- [references/runbook.md](references/runbook.md) — symptom/log-message → cause → check → fix table (messages reproduced on OpenResty 1.31.8.1 are marked).
- [references/commands.md](references/commands.md) — evidence-gathering commands: logs, sockets, FDs, kernel counters, TLS, debug logging, SELinux.
