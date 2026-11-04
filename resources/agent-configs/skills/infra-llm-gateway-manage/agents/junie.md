# Junie CLI Specifics for Infra Llm Gateway Manage

## Context & Tuning
- Load only `references/llm-gateway.md`; pin the approved release and verify its signature/provenance. Treat the October 2026 `v1.107.0` incident as a release gate.

## Instructions Overrides
- Never print master/provider keys or prompt content; require tenant-scoped keys, limits, and cache rules.

## Performance Notes
- Ask before changing production routes or hard budgets; no commits.
