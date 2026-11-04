# Claude Specifics for Infra Linux Packages Manage

## Context & Tuning
- Use distro-native package tooling and keep package/repository scope narrow.
- Verify the configured repository and rollback path before proposing a change.

## Instructions Overrides
- Require approval before production upgrades/removals or new vendor repositories.
- Do not include credentials or unverified signing material in the response.
