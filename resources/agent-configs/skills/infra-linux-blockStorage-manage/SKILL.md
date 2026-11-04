---
name: infra-linux-blockStorage-manage
description: "Provision and operate Linux block devices, GCP Persistent Disk/Hyperdisk, partitions, filesystems, LVM, and software RAID. Use when a task mentions lsblk, mkfs, fstab, growpart, resize2fs, xfs_growfs, LVM, mdadm, disk snapshots, or filesystem repair."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/storage/block-storage]
  license: MIT
---

# Linux block storage management

## Triggers

- Attach, format, mount, grow, snapshot, or troubleshoot a Linux block device.
- Extend an LVM volume or filesystem, inspect RAID health, or assess disk latency.
- Operate GCP Persistent Disk or Hyperdisk attached to a Linux VM.

## Load order (SAD KITTI)

```sadkitti
REQUIRE data-retention policy and host runbook if present
REFERENCE "references/block-storage.md"
IF disk lifecycle is declared in OpenTofu/Terraform
  REFERENCE the relevant IaC skill and inspect its plan before live operations
IF storage contains a database
  REFERENCE its database-specific backup/consistency procedure before snapshotting
CACHE only the target device and filesystem workflow
```

## Workflow

1. Identify the exact VM, device ID, filesystem, mount point, data owner, and production impact; compare `lsblk`, `blkid`, and `findmnt`.
2. Confirm backups or an application-consistent snapshot before resizing, repairing, or replacing a device.
3. For first-use formatting, stop and obtain explicit confirmation that the verified device is empty and disposable.
4. Grow capacity in order: cloud device, partition (if any), physical volume/LV, then filesystem; never shrink online by assumption.
5. Validate mounts and application reads/writes; record stable UUID/by-id paths and rollback constraints.

## Safety

- `mkfs`, `wipefs`, partition-table creation, `lvremove`, `lvreduce`, RAID creation on existing devices, and disk deletion are destructive and require explicit confirmation.
- Do not use a guessed device name or benchmark a raw device containing data.
- Local SSD is ephemeral; verify its lifecycle before placing any persistent state there.

## Related skills

- NFS and Filestore mounts → `infra-linux-nfs-manage`
- Storage backup and recovery → `infra-any-backupRecovery-manage`
- Linux I/O performance → `infra-linux-perf-tune`
- GCP VM and disk provisioning → `infra-gcp-compute-manage`

## References

- [references/block-storage.md](references/block-storage.md) — GCP disk lifecycle, filesystem growth, LVM, RAID, and repair.
