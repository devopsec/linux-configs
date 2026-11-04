# Linux block devices, GCP disks, and LVM

## Inventory and device identity

```bash
lsblk -f
blkid
findmnt --verify
df -hT; df -i
```

Match the intended cloud disk name to a stable device path (`/dev/disk/by-id/`), serial, filesystem UUID, and mount point. Never act on `/dev/sdX` alone; enumeration can change after reboot or attach operations.

## GCP Persistent Disk and Hyperdisk

Choose a disk family using workload latency, capacity, IOPS/throughput requirements, region/zone, machine-family support, and budget. Confirm current limits in the provider control plane before provisioning or tuning.

```bash
gcloud compute disks describe <disk> --zone=<zone>
gcloud compute disks create <disk> --zone=<zone> --size=<approved-size> --type=<approved-disk-type>
gcloud compute instances attach-disk <vm> --zone=<zone> --disk=<disk> --device-name=<device-name>
```

Set data-disk auto-delete behavior deliberately. Detach only after stopping writers, unmounting cleanly, and removing or disabling the corresponding fstab entry. Snapshot before replacement or risky maintenance; database snapshots require the database's consistency procedure.

## First-use filesystem and mount

**Destructive:** formatting destroys existing filesystem metadata. Proceed only after the owner confirms the exact device is new/empty and the operation is approved.

```bash
DEVICE=/dev/disk/by-id/<verified-device-id>
lsblk -f "$DEVICE"          # stop if a filesystem or partition is present
mkfs.ext4 "$DEVICE"         # choose filesystem only after confirming the workload
UUID=$(blkid -s UUID -o value "$DEVICE")
install -d -m 0755 <mount-point>
```

Add a reviewed UUID-based fstab entry with an appropriate filesystem, mount options, and `nofail` only when boot must continue without the data disk. Validate with `findmnt --verify`, mount, then check `findmnt` and `df -hT`.

## Grow capacity

Increase cloud capacity first, then inspect the guest's new device size. If the filesystem is partitioned, grow the correct partition; if it is LVM, resize the PV and LV; finally grow the filesystem using the correct online/offline procedure.

```bash
lsblk
growpart <device> <partition-number>  # only when a partition table is in use
pvresize <verified-pv>
lvextend -r -L +<approved-increment> <logical-volume>
```

For direct ext4, use the matching `resize2fs` device; for mounted XFS, use `xfs_growfs <mount-point>`. Recheck filesystem and application health. Cloud disks are generally grown, not shrunk.

## LVM and RAID

Before `pvcreate`, verify the selected device has no needed data. Review `pvs`, `vgs`, `lvs -a -o +devices` and the intended allocation before changing metadata. `lvreduce`, `pvremove`, and filesystem shrinking can destroy data; require a verified backup and explicit confirmation.

Software RAID is seldom needed on replicated cloud disks. Use it only for a justified local/bare-metal design; inspect all member serials, existing metadata, redundancy, rebuild plan, and monitoring before creating or replacing an array.

## Snapshots and repair

Use application-consistent snapshots: flush/stop writers or use the database's backup tooling. Never freeze the root filesystem as a generic snapshot step. Confirm restore tests and retention policy before relying on a snapshot.

Run filesystem repair only on the correct unmounted filesystem and after preserving data. For XFS, start with the tool's no-modify/check mode. If a filesystem remounts read-only, stop writers and investigate kernel errors before repair.

## Destructive-action gate

Require explicit user confirmation before `mkfs`, `wipefs`, `parted mklabel`, `lvremove`, `lvreduce`, `mdadm --create` on any existing device, or deleting a cloud disk. First list the target identifiers and explain data loss, backup, and rollback implications.