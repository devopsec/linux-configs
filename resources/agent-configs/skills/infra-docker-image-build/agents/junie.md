# Junie specifics — infra-docker-image-build

## Context & Tuning
- Execute SAD KITTI branches and load only the build reference needed for the request.
- Inspect existing Dockerfile and lockfile conventions before proposing image changes.
- Keep secrets and private registry credentials out of logs and summaries.
- Do not publish images or modify production tags without explicit approval.
