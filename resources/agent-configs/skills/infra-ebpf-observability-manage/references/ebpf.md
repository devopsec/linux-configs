# eBPF observability on VMs (bpftrace, BCC, Tetragon)

Use when app metrics/traces can't explain latency, drops or unexpected process/file/network activity. Everything here needs root or `CAP_BPF`+`CAP_PERFMON`; **time-box runs (`timeout 60 …`), one host at a time, user approval on production**.

## Prerequisites

```bash
uname -r                                   # ≥ 5.10 recommended (RHEL 9 = 5.14, Debian 12 = 6.1)
test -e /sys/kernel/btf/vmlinux && echo BTF-ok
sudo dnf install -y bpftrace bcc-tools     # RHEL-family (tools in /usr/share/bcc/tools)
sudo apt install -y bpftrace bpfcc-tools   # Debian (tools suffixed -bpfcc)
```

- No BTF → upgrade kernel (don't fetch random BTF archives from the internet).
- SELinux enforcing usually fine for root; lockdown=confidentiality (Secure Boot) blocks some probes — check `cat /sys/kernel/security/lockdown`.
- GCE: standard images ship BTF; no special VM config needed.

## BCC tools (fastest wins)

| Question | Tool (RHEL path / Debian name) |
|---|---|
| new processes / short-lived execs | `execsnoop` / `execsnoop-bpfcc` |
| who opens which files | `opensnoop -p <pid>` |
| TCP connects / accepts / lifetimes | `tcpconnect`, `tcpaccept`, `tcplife` |
| TCP retransmits (network loss) | `tcpretrans` |
| block I/O latency histogram | `biolatency -D 10 1` |
| slow filesystem ops | `ext4slower 10` / `xfsslower 10` |
| run-queue latency (CPU saturation) | `runqlat 10 1` |
| off-CPU time | `offcputime -p <pid> 10` |
| CPU profile | `profile -F 99 -p <pid> 30` |

## bpftrace one-liners

```bash
# syscall latency histogram for one process (µs)
sudo timeout 30 bpftrace -e 'tracepoint:raw_syscalls:sys_enter /pid == $1/ { @s[tid] = nsecs; }
  tracepoint:raw_syscalls:sys_exit /@s[tid]/ { @us = hist((nsecs - @s[tid]) / 1000); delete(@s[tid]); }' <pid>

# UDP sends per process to a selected service port — counts only, no payload
sudo timeout 30 bpftrace -e 'kprobe:udp_sendmsg {
  $sk = (struct sock *)arg0; $dport = bswap($sk->__sk_common.skc_dport);
  if ($dport == $1) { @udp_tx[comm] = count(); } }' <service-port>

# TCP retransmits with endpoints
sudo timeout 60 bpftrace -e 'tracepoint:tcp:tcp_retransmit_skb {
  @[ntop(args->saddr), ntop(args->daddr), args->dport] = count(); }'

# block I/O latency by device
sudo timeout 30 bpftrace -e 'tracepoint:block:block_rq_issue { @s[args->dev, args->sector] = nsecs; }
  tracepoint:block:block_rq_complete /@s[args->dev, args->sector]/ {
    @us[args->dev] = hist((nsecs - @s[args->dev, args->sector]) / 1000); delete(@s[args->dev, args->sector]); }'

# CPU flame graph input (99 Hz, 30 s)
sudo timeout 30 bpftrace -e 'profile:hz:99 /pid == $1/ { @[ustack, kstack, comm] = count(); }' <pid> > "$TMPDIR/stacks.bt"
```

Prefer stable **tracepoints** over kprobes (kernel-internal struct offsets change between versions). `bswap()` replaces upstream's manual byte-swap of `skc_dport`. Python stacks need `PYTHONPERFSUPPORT=1` (3.12+) for readable frames.

## Continuous / always-on options

| Tool | Purpose | Notes |
|---|---|---|
| **Tetragon** (standalone systemd, no k8s needed) | process exec, file access, network policy events; enforcement | rpm/deb or tarball with checksum from GitHub releases; export JSON events → Alloy/Filebeat → Loki/ELK or Cloud Logging |
| **Parca Agent** / **Grafana Pyroscope (Alloy `pyroscope.ebpf`)** | continuous CPU profiling | low overhead (~1%); review data retention |
| **ebpf_exporter** (Cloudflare) | custom kernel metrics → Prometheus | YAML + CO-RE programs; good for retransmits/run-queue SLIs |
| **Cilium/Hubble** | k8s CNI flow visibility | only relevant if a GKE cluster is in scope |

Tetragon example policy — alert on shells spawned by service users:

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata: { name: shell-from-services }
spec:
  kprobes:
    - call: "sys_execve"
      syscall: true
      args: [ { index: 0, type: "string" } ]
      selectors:
        - matchArgs: [ { index: 0, operator: "Postfix", values: ["/bash", "/sh"] } ]
          matchActions: [ { action: Post } ]
```

`tetra getevents -o compact` on the host to inspect; route events to the SIEM / `sec-ops-incident-respond` workflows.

Dropped from upstream: Helm-based Cilium/Hubble install and CLI install via `curl … stable.txt` (unverified downloads), btfhub `wget`, piping Tetragon logs to an external SIEM with `curl`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ERROR: Could not resolve symbol` | probe renamed in this kernel → use tracepoint or `bpftrace -l 'kprobe:*udp*'` |
| `Operation not permitted` | root/caps, lockdown mode, `kernel.unprivileged_bpf_disabled` irrelevant for root |
| lost events | raise `BPFTRACE_PERF_RB_PAGES`, filter by pid earlier |
| overhead concerns | sample (`profile:hz:49`), filter in-kernel, shorter runs |
