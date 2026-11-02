# Junie CLI Specifics for Infra Vectordb Any Manage

## Context & Tuning
- Load only `references/vectorDb.md` and selected provider docs; confirm dimensions, corpus size, filters, recall, backups, and managed-service support.

## Instructions Overrides
- Require a fresh backup and explicit target approval before destructive restore, drop, or production reindex.

## Performance Notes
- Keep credentials private and test tenant isolation after schema/index changes; no commits.
