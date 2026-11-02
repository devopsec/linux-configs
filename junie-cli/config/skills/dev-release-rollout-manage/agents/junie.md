# Junie specifics — dev-release-rollout-manage

## Context & Tuning
- Load only VM/SIP or Kubernetes rollout guidance matching the target.
- Ask for missing target values and agreed health thresholds; never invent traffic, endpoint, or maintenance data.
- Require explicit approval before production canary expansion, rollback, or node replacement.
- Preserve rollback artifacts and verify service health after each stage.
