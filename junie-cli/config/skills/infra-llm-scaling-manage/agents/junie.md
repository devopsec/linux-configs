# Junie CLI Specifics for Infra Llm Scaling Manage

## Context & Tuning
- Load only `references/llm-scaling.md` and use measured metrics from the deployed serving version; confirm online/batch mode, replica bounds, queue durability, quota, and spend ceiling.

## Instructions Overrides
- Obtain approval before changing KEDA, node-pool capacity, or production replica bounds.

## Performance Notes
- Test cooldown, metric outage, interruption recovery, and scale-to-zero behavior; redact secrets and make no commits.
