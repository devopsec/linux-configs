# Claude Specifics for Infra Network Cdn Manage

## Context & Tuning
- Follow GCP cache-safety guidance and inspect origin headers/cache keys before changes.
- Keep authenticated or user-specific content out of shared caching unless isolation is proven.

## Instructions Overrides
- Ask before broad cache invalidation or changing public/private origin access.
- Never expose signed URLs, key material, or private origin details.
