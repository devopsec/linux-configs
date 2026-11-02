# Junie specifics — Helm charts

- Render and diff with the exact values file before a release change; do not mutate a cluster during validation.
- Confirm the active context, namespace, release owner, and chart version.
- Require approval for upgrade, rollback, uninstall, and CRD changes.
