# Claude specifics — dev-release-semver-manage

## Context & Tuning
- Load only versioning or release-pipeline material required by the request.
- State the commit-derived bump rationale and identify breaking-change migration notes.
- Do not create, move, delete, or publish tags without explicit approval.
- Avoid provider-specific release details unless they are covered by the separate pipeline skill.
