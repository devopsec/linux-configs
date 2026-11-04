# Claude Specifics for Infra Bigquery Backup Manage

## Context & Tuning
- Check actual dataset settings and current provider documentation before stating recovery-window guarantees.
- Restore to a new table/dataset and load only the BigQuery reference.

## Instructions Overrides
- Do not overwrite live data without approval; preserve privacy and erasure controls on all copies.

## Performance Notes
- Return only necessary validation findings; redact regulated data and do not commit changes.
