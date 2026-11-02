# Claude specifics — dev-release-rollout-manage

## Context & Tuning
- Select VM/SIP or Kubernetes references based on the actual deployment target.
- Establish an approved artifact digest, canary size, bake time, and rollback target before rollout.
- For stateful traffic, confirm drain completion before restarting or replacing a node.
- Keep site-specific addresses, thresholds, and customer data out of global instructions.
