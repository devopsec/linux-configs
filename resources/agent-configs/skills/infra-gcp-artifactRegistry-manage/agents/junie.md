# Junie specifics — infra-gcp-artifactRegistry-manage

## Context & Tuning
- Execute the SAD KITTI branch for Artifact Registry only; read project identity from approved config or ask.
- Separate publishing identity permissions from reader/deployment access.
- Prefer digest-based deployment and preview destructive retention policies.
- Never reveal service-account keys, access tokens, or private project values.
