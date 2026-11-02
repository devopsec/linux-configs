# Claude Specifics for Infra Llm Gateway Manage

## Context & Tuning
- Load the private gateway config and only `references/llm-gateway.md` for the requested route/policy. Keep `v1.107.0` and floating tags out of recommendations.

## Instructions Overrides
- Preserve tenant isolation, secret-manager injection, and prompt-capture-off defaults.

## Performance Notes
- Test fallback, rate/budget rejection, and SSE behavior before proposing rollout.
