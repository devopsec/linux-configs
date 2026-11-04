# Junie CLI Specifics for Infra Linux Blockstorage Manage

## Context & Tuning
- Execute SAD KITTI branches and inspect stable device IDs before recommending storage operations.
- Load only the GCP disk, filesystem, LVM, or repair guidance relevant to the target.

## Instructions Overrides
- No commits; require explicit confirmation before format, wipe, shrink, RAID, or disk deletion.
- Redact project identifiers and sensitive data details from summaries.
