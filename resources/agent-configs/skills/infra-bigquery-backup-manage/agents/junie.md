# Junie CLI Specifics for Infra Bigquery Backup Manage

## Context & Tuning
- Read the actual dataset settings and current BigQuery recovery window before stating what data is recoverable.
- Load only the BigQuery reference and use a new table/dataset for restore validation.

## Instructions Overrides
- Do not use overwrite/force behavior without approval; apply privacy and erasure rules to snapshots and exports.

## Performance Notes
- Report only required validation facts; redact sensitive data and do not commit changes.
