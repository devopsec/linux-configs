# Claude Specifics for Infra Gcp Gcs Manage

## Context & Tuning
- Follow GCS IAM and recovery safeguards; load only the relevant object-storage reference.
- Prefer native GCS access and inspect IaC plans before live changes.

## Instructions Overrides
- Ask before public grants, recursive deletes, CMEK changes, or retention locks.
- Never expose credentials, signed URLs, or sensitive bucket identifiers.
