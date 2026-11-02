---
name: infra-linux-nfs-manage
description: "Configure and troubleshoot Linux NFSv4 servers and clients, exports, automounts, identity mapping, and GCP Filestore mounts. Use when a task mentions /etc/exports, exportfs, mount.nfs, nfsstat, autofs, stale NFS handles, or shared filesystem access."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/storage/nfs-storage]
  license: MIT
---

# Linux NFS administration

## Triggers

- Configure an NFS export, NFSv4 client mount, systemd automount, or autofs map.
- Diagnose export denial, UID/GID mapping, stale handles, or NFS throughput.
- Connect a Linux workload to a managed NFS service such as GCP Filestore.

## Load order (SAD KITTI)

```sadkitti
REQUIRE host and data-sharing policy if present
REFERENCE "references/nfs.md"
IF managed NFS is involved
  REFERENCE the provider's current Filestore control-plane documentation
IF export or firewall policy changes
  REFERENCE skill "sec-network-perimeter-manage"
CACHE only server-side or client-side mount guidance
```

## Workflow

1. Confirm server/client OS, NFS version, trusted client identities/ranges, data sensitivity, and whether the workload requires shared locking or low-latency writes.
2. Inspect exports, active mounts, firewall policy, UID/GID mapping, and server/client statistics before changing configuration.
3. Prefer NFSv4 over TCP, narrow exports, `root_squash`, and an automount/`nofail` strategy where boot must not depend on the share.
4. Validate export syntax and reachability, then test access as the consuming service identity.
5. Monitor errors/latency and document the export, client scope, ownership model, and recovery process.

## Safety

- Never use a wildcard read/write export or `no_root_squash` on a shared network.
- Do not place SQLite databases or PostgreSQL data directories on NFS; use supported local or managed database storage.
- NFS soft mounts can turn transient outages into silent write corruption; preserve hard-mount semantics unless the application owner approves otherwise.

## Related skills

- Block devices and filesystems → `infra-linux-blockStorage-manage`
- Firewall rules and network reachability → `sec-network-perimeter-manage`
- GCP Filestore provisioning → `infra-gcp-any-manage`
- Kubernetes persistent volumes → `infra-kubernetes-any-manage`

## References

- [references/nfs.md](references/nfs.md) — exports, NFSv4 clients, managed Filestore boundary, security, and troubleshooting.
