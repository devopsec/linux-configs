---
name: infra-ebpf-observability-manage
description: "Use eBPF observability tools on Linux to investigate kernel, process, filesystem, block-I/O, and network behavior with bpftrace, BCC, or Tetragon. Use when tasks mention eBPF, BTF, bpftrace, BCC tools, Tetragon, TCP retransmits, run-queue latency, or kernel-level profiling."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/observability/ebpf-observability
  license: MIT
---

# eBPF observability manage

Use short, filtered eBPF investigations when application metrics and traces cannot explain kernel or host behavior. Prefer stable tracepoints and time-box every collection.

## Triggers

- Kernel-level latency, TCP retransmits, process/file activity, or block I/O
- bpftrace/BCC tool selection, BTF prerequisites, or Tetragon events
- CPU profiling or eBPF permission/overhead troubleshooting

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or host runbook if present
IF task involves selecting an eBPF tool, probe duration, or collection scope
  IF file "~/.junie/custom/configs/infrastructure/ebpf.toml" exists
    REFERENCE "~/.junie/custom/configs/infrastructure/ebpf.toml"
  ELSE
    use the defaults in Tool defaults
IF task involves eBPF, bpftrace, BCC, Tetragon, or kernel tracing
  REFERENCE "references/ebpf.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Clarify the incident question, host/kernel version, process or interface scope, and required privilege.
2. Check BTF and tool availability; choose the least invasive tracepoint/tool that can answer the question.
3. Get explicit approval before production tracing, run on one host with a strict timeout, and filter early to limit overhead and data collection.
4. Stop on schedule, summarize only relevant aggregate findings, and remove temporary output after preserving approved evidence.

## Safety

- eBPF tools require root or delegated capabilities and may expose process/network details; production use requires user approval.
- Never capture payloads or broad host data when counts/latency aggregates suffice. Protect output files and redact identifiers.
- Do not fetch unsigned kernel artifacts or pipe remote installers into a shell.

## Tool defaults

- Use `bpftrace` for a short, focused tracepoint probe; prefer the matching BCC utility for standard host questions. Use Tetragon only when continuous process/file/network events are required.
- Limit one-off probes to 30 seconds by default; production use always requires approval.
- `assets/config.example.toml` shows optional preferences and contains no host values.

## Related skills

- Host administration and performance: `infra-linux-perf-tune`
- Metrics and dashboards: `infra-prometheus-metrics-manage`
- Log investigation: `infra-loki-logging-manage` / `infra-elk-logging-manage`
- Incident handling: `sec-ops-incident-respond`

## References

- [eBPF observability on Linux hosts](references/ebpf.md)
