# Linux NFS server and client operations

## Workload fit

NFS fits shared files, read-mostly assets, and workloads explicitly designed for network filesystems. Do not use it for SQLite databases or PostgreSQL data directories; filesystem locking, latency, and failure semantics can cause corruption or unacceptable behavior. For object data and backups, prefer object storage.

## Server setup

Use the distro's signed NFS server package and service. Prefer NFSv4-only operation when all clients support it; this reduces ancillary RPC exposure. Keep export definitions in the host's supported exports file and validate with `exportfs -ra` / `exportfs -v` before relying on them.

```text
/srv/share  <approved-client-cidr>(rw,sync,no_subtree_check,root_squash)
/srv/public <approved-client-cidr>(ro,sync,no_subtree_check,root_squash)
```

Use the narrowest approved client identity/range and read-only access where possible. Map user/group ownership consistently across hosts. Select NFS version, export root, server threads, and filesystem using actual distro and workload requirements.

## Client mounts

Prefer a stable server DNS name and systemd automount where boot must not wait on a remote share. Use NFSv4 over TCP and a hard mount for ordinary data workloads. Avoid `soft` mounts for writable files; interrupted operations can silently corrupt data.

```text
<nfs-server>:/<export> <mount-point> nfs4 vers=<supported-version>,hard,proto=tcp,_netdev,nofail,x-systemd.automount 0 0
```

Validate fstab and mount behavior with `findmnt --verify`, `findmnt <mount-point>`, and `nfsstat -m`. Use `RequiresMountsFor=` for systemd services that must have the share mounted before startup.

## Security and identity

- Do not use `*(rw,...)` or `no_root_squash` on shared networks.
- Restrict network access to approved client ranges and the required NFS service; coordinate with firewall policy rather than opening broad RPC ranges.
- For Kerberos or encrypted transport, confirm both server and client support and the organization's identity/keytab process.
- Align UID/GID mapping or directory-service identity; a mismatch commonly appears as anonymous ownership.
- On SELinux systems, set the appropriate file contexts/booleans; do not disable SELinux to make an export work.

## Managed Filestore boundary

GCP Filestore provides a managed NFS endpoint. Provisioning, tier/capacity, network attachment, backups, and firewall reachability are provider-control-plane concerns; this skill covers Linux mount behavior and identity. Ask for the approved share name, mount target, client scope, and service tier; do not invent IPs or capacity. Use the provider's current documentation for supported tiers and NFS versions.

## Performance and diagnosis

Use `nfsstat -c`, `nfsstat -s`, `mountstats <mount-point>`, server logs, and application timing before changing mount options or thread counts. Check network loss/latency, disk backing, client concurrency, and UID mapping. Consider `nconnect` only when supported by the running kernel and server and justified by measurement.

| Symptom | Check |
|---|---|
| Access denied | effective exports, client identity/source, SELinux labels |
| Mount stalls | server availability, route/firewall, DNS, service logs |
| Stale file handle | export path/filesystem identity and remount procedure |
| Files appear as anonymous user | UID/GID mapping and idmap configuration |
| Slow I/O | `mountstats`, network, server threads, backing storage |

Do not use lazy unmount or force recovery as a first response while writers may still be active; identify and safely stop consuming processes first.