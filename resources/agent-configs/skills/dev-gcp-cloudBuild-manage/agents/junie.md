# Junie specifics — dev-gcp-cloudBuild-manage

- Execute only the active SAD KITTI branch; keep project companion details out of generic references.
- Inspect trigger definitions, build YAML, and IAM read-only before proposing changes.
- Do not run builds, alter triggers/IAM, or publish artifacts without explicit approval; sandbox validation only.
- Treat scans as required gates by default; identify documented local exceptions and report their scope.
- Redact project IDs, full service-account emails, and secret values in summaries; no commits.
