# Junie specifics — infra-docker-compose-manage

## Context & Tuning
- Execute the SAD KITTI Compose branch and inspect active override/profile inputs.
- Render merged YAML before recommending a change to a running stack.
- Treat volume deletion and destructive cleanup as explicit approval gates.
- Never expose secret values from `.env` or Compose secret sources.
