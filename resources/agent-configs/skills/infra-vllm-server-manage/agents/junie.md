# Junie CLI Specifics for Infra Vllm Server Manage

## Context & Tuning
- Load only `references/vllm.md`; inspect pinned runtime help before proposing release-sensitive flags and confirm GPU type/count, model revision, context, concurrency, and SLO.

## Instructions Overrides
- Do not start GPU workloads or expose a raw inference port without explicit approval and cost review.

## Performance Notes
- Keep API/model-hub tokens out of command output, manifests, and summaries; do not commit changes.
