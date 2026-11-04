# Junie specifics — dev-github-actions-manage

## Context & Tuning
- Read the GitHub Actions tool config when present; otherwise use the stated lint/security defaults.
- Treat fork event payloads and `pull_request_target` contexts as untrusted boundaries.
- Verify minimal permissions and full-SHA action pins; never print tokens or OIDC credentials.
- Do not dispatch production workflows or alter permissions without explicit approval.
