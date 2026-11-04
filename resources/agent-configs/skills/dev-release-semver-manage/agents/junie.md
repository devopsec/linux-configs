# Junie specifics — dev-release-semver-manage

## Context & Tuning
- Read the release config when present; otherwise apply SemVer 2.0.0 and Conventional Commit defaults.
- Review commit range and generated notes before recommending a bump or tag.
- Treat protected tags as immutable and require explicit approval to create or publish them.
- Keep customer identifiers, internal hostnames, and secrets out of release notes.
