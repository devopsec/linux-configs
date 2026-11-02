# Junie CLI Specifics for Infra Ops Drplan Create

## Context & Tuning
- Obtain owner-approved recovery targets, service dependencies, incident authority, and failover destination; do not invent site values.
- Load only the DR procedure and any recovery-specific reference required by the active task.

## Instructions Overrides
- Treat promotion, routing changes, and failback as disruptive; require approved authority and a tested rollback path.

## Performance Notes
- Summarize actual measured RPO/RTO and open actions; do not commit runbooks or evidence.
