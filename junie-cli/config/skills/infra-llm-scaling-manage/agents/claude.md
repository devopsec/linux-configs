# Claude Specifics for Infra Llm Scaling Manage

## Context & Tuning
- Use `references/llm-scaling.md` as the KEDA source; avoid copying tenant policy from gateway configuration. Check queue, KV cache, and SLO metrics.

## Instructions Overrides
- Require cost/quota confirmation and an on-demand baseline for online workloads.

## Performance Notes
- Report tested scale-up/down and interruption behavior without exposing tenant identifiers.
