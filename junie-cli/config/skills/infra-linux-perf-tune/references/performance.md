# Linux performance measurement and tuning

## Method

1. Record host OS/kernel, workload shape, normal operating envelope, and the test window.
2. Capture representative counters before tuning; identify a measured bottleneck rather than guessing from utilization alone.
3. Change one variable in a managed file, apply on a test host, and repeat the same test.
4. Keep the change only if the target metric improves without unacceptable regressions; record a rollback value.

## Baseline commands

```bash
uptime; nproc; free -h
vmstat <interval> <samples>
mpstat -P ALL <interval> <samples>
iostat -xz <interval> <samples>
pidstat -u -r <interval> <samples>
ss -s; nstat -az
cat /proc/sys/fs/file-nr
```

Install `sysstat` from the host's signed distro repository for `mpstat`, `iostat`, and `pidstat`. Check CPU saturation, softirq time, swap activity, I/O wait/latency, socket errors, and file-descriptor use together.

## Network and SIP/RTP workloads

Inspect UDP errors and socket queues before changing sysctls:

```bash
nstat -az
ss -uamn
cat /proc/net/softnet_stat
conntrack -C
conntrack -S
sysctl net.netfilter.nf_conntrack_max
```

For SIP/RTP, use the actual listener and media ranges supplied by the service owner. Ask for RTP ranges and interface/VM type when absent; never infer site values from generic examples. Map rising `UdpRcvbufErrors` to socket/app receive buffers, softnet drops to backlog/CPU queues, and conntrack drops to table pressure or policy.

When tuning, persist approved numeric settings in a clearly named `/etc/sysctl.d/` file, then validate the file and effective values. Check whether a boot-time generator owns the setting. Ensure any `notrack` rules preserve explicit allow policy for the intended traffic and are coordinated with the firewall owner.

On cloud VMs, queue/ring controls depend on the virtual NIC and machine type. Inspect `ethtool -l <interface>` and provider limits; measure before changing queue counts or RPS. Keep application file-descriptor ceilings aligned with system limits and systemd `LimitNOFILE`.

## CPU, memory, and I/O

- Use `vmstat`, `mpstat`, and `pidstat` to separate CPU saturation, softirq pressure, and memory reclaim/swapping.
- Use `iostat -xz` and application timings to identify device latency or saturation before changing schedulers or read-ahead.
- For cloud disks, check the disk class, size, machine family, and provider throughput/IOPS constraints; coordinate capacity changes with the block-storage owner.
- Guest CPU governors may not control cloud VM frequency; confirm platform support before changing them.

## Benchmark guardrails

Use `iperf3` only between approved test endpoints and keep offered load within the test scope. Run `fio` only against a disposable test file on a test filesystem; never target a raw device or live data path. Use application-level load tests against a non-production SIP endpoint and capture packet-loss/call-quality metrics as well as host counters.

## Symptom mapping

| Observation | Likely area to investigate |
|---|---|
| Rising UDP receive-buffer errors | Application socket requests and kernel receive buffers |
| Softnet drops/time squeeze | CPU/softirq load, queue distribution, backlog/budget |
| Conntrack insertion/drop errors | Table capacity, timeout policy, tracked flows |
| High I/O wait or latency | Disk class/limits, filesystem workload, queue depth |
| `Too many open files` | Process limits, systemd unit limits, global file table |
| High softirq on one CPU | NIC queues, affinity/RPS, workload distribution |

Do not apply a generic tuning profile wholesale. Every kernel value depends on the running kernel, memory, NIC, application behavior, and measured load.