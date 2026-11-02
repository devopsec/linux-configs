# Claude specifics — sec-claudeCode-guardrails-manage

- Check `/status` and `/permissions` before interpreting effective policy.
- Treat hooks and settings changes as privileged code; show a diff and await approval.
- Do not use bypass modes on a host with real credentials.
