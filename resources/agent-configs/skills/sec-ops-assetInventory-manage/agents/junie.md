# Junie CLI Specifics for Sec Ops Assetinventory Manage

## Context & Tuning
- Confirm boundary, discovery sources, required fields, ownership, and coverage limits before building the inventory.
- Treat addresses, CIDRs, buckets, RTP ranges, and targets as user/configuration inputs.

## Instructions Overrides
- Never inventory credential contents or use labels as proof of security control.

## Performance Notes
- Report gaps and source coverage concisely; do not commit restricted inventories or expose personal data.
