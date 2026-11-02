# Requirements checklist template

Use in `/tmp` or in the reply; optionally land a project matrix if the repo already keeps one.

```markdown
# Spec: <filename> <version>
# Scope: <feature>

| ID | Requirement (short) | Code touchpoint | Test | Status |
|----|---------------------|-----------------|------|--------|
| REQ-01 | ... | src/... | test_... | done |
| REQ-02 | ... | — | — | deferred: <why> |
| REQ-03 | ... | — | — | blocked: <why> |
```

## Status vocabulary

- `done` — implemented and verified
- `partial` — shipped subset; note missing pieces
- `deferred` — out of agreed scope
- `blocked` — needs user/spec clarification
- `n/a` — not applicable after clarification

## Writing good REQ ids

- Prefer stable ids from the spec (`R-4.2`, `ERR_42`).
- If none, assign `REQ-01…` in document order and keep them for the session.
