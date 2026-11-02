# Junie CLI Specifics for Infra Gcp Gcs Manage

## Context & Tuning
- Execute SAD KITTI branches and load only the bucket, IAM, lifecycle, or transfer guidance needed.
- Use ADC/impersonation and request unknown bucket, retention, location, or access values.

## Instructions Overrides
- No commits; require explicit approval for public access, deletes, or retention locks.
- Redact service-account/HMAC secrets and signed URLs from outputs.
