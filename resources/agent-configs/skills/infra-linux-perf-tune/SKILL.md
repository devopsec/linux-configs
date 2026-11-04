---
name: infra-linux-perf-tune
description: "Measure and tune Linux kernel, CPU, memory, network, and block-I/O performance, including SIP/RTP workloads. Use when a task mentions sysctl, UDP drops, conntrack pressure, softirq, socket buffers, file-descriptor limits, iostat, fio, or throughput tuning."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/servers/performance-tuning]
  license: MIT
---

# Linux performance tuning

## Triggers

- Diagnose CPU, memory, network, or disk saturation on a Linux host.
- Tune sysctl, UDP socket queues, conntrack, file descriptors, I/O scheduling, or service limits.
- Measure SIP/RTP or application throughput and compare before/after counters.

## Load order (SAD KITTI)

```sadkitti
REQUIRE host runbook or platform operations documentation if present
REFERENCE "references/performance.md"
IF task involves RTP/media firewall rules or conntrack exemptions
  REFERENCE skill "sec-network-perimeter-manage" before changing packet policy
CACHE only the applicable measurement and tuning guidance
```

## Workflow

1. Confirm workload, OS/kernel, production status, and the approved test window; ask the user for RTP port ranges or site-specific interface values rather than guessing.
2. Capture a workload-representative baseline: CPU/softirq, memory, disk latency, network counters, socket drops, and conntrack use.
3. Locate the limiting resource before tuning; change one setting at a time in a managed configuration file.
4. Validate syntax and bounds, apply on a test host, then rerun the same workload and compare counters.
5. Retain only measured improvements; record rollback values and coordinate service reloads or firewall changes.

## Safety

- Do not copy generic sysctl numbers into production without RAM, kernel, NIC, and workload measurements.
- Treat `notrack`, queue/buffer changes, and `LimitNOFILE` as coordinated changes; validate with the application owner.
- Avoid active benchmarks against production traffic or raw data devices.

## Related skills

- systemd service limits and unit settings → `infra-linux-systemd-manage`
- Disk provisioning and filesystem growth → `infra-linux-blockStorage-manage`
- Firewall policy and RTP exposure → `sec-network-perimeter-manage`
- SIP application behavior and call measurements → `dev-kamailio-platform-manage`

## References

- [references/performance.md](references/performance.md) — measurement, kernel/network tuning, I/O, CPU, and symptom mapping.
