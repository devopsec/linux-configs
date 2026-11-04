---
name: infra-docker-image-build
description: "Build and validate Docker/BuildKit OCI images with reproducible multi-stage Dockerfiles, digest-pinned bases, secret-safe builds, and buildx multi-platform publishing. Use when a request mentions Dockerfile, docker build, BuildKit, buildx, image layers, build cache, image labels, or image build failures."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/containers/docker-management
  license: MIT
---

# Docker image build

Use this skill for image construction only. Running services, Compose, Podman, registry operations, and runtime hardening belong to the related skills.

## Triggers

- `Dockerfile`, `.dockerignore`, `docker build`, BuildKit, buildx, multi-stage or multi-platform image builds
- Build cache misses, build failures, image labels, build secrets, or reproducible image output

## Load order (SAD KITTI)

```sadkitti
IF task involves Dockerfile design, image layers, or build commands
  REFERENCE "references/docker-build.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Inspect the existing Dockerfile, lockfiles, and `.dockerignore`; retain the repository’s established runtime and entrypoint.
2. Order layers from stable dependencies to frequently changing source; use multi-stage builds and copy lockfiles before application files.
3. Pin release base images by digest, use exec-form entrypoints, run as a non-root numeric user, and keep credentials out of `ARG`, `ENV`, layers, and build logs.
4. Build locally with the narrowest target/platform needed, lint the Dockerfile, inspect the image metadata, and report its digest and any deployment assumptions.

## Related skills

- Local runtime → `infra-docker-compose-manage` or `infra-podman-container-manage`
- Registry authentication and image publication → `infra-gcp-artifactRegistry-manage`
- Runtime isolation and scan policy → `sec-container-runtime-harden`
- CI build/publish pipeline → `dev-github-actions-manage`, `dev-jenkins-pipeline-manage`, or in-house `dev-gcp-cloudBuild-manage`
- Kubernetes workloads → `infra-kubernetes-workload-manage`
