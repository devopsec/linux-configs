# Claude specifics — infra-docker-image-build

## Context & Tuning
- Load only the Docker build reference relevant to the requested target or build failure.
- Preserve the repository's base image, build stages, and runtime contract unless asked to change them.
- Keep credentials out of Docker build arguments, layers, and diagnostic output.
- Ask before publishing an image or changing an immutable release tag.
