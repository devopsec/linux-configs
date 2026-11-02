# Junie CLI Specifics for Infra Network Cdn Manage

## Context & Tuning
- Execute SAD KITTI branches and load only the Cloud CDN origin/cache reference needed.
- Ask for content classification, origin, cache key, and invalidation scope at runtime.

## Instructions Overrides
- No commits; require approval before public origin access or broad invalidation.
- Redact signed URLs, signing keys, and sensitive origin identifiers.
