---
name: infra-docker-compose-manage
description: "Design, validate, operate, and troubleshoot Docker Compose multi-container applications with safe interpolation, health dependencies, persistent volumes, networks, profiles, and upgrades. Use when a request mentions compose.yaml, docker-compose.yml, docker compose up/config/down, Compose profiles, service dependencies, or local multi-service stacks."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/containers/docker-compose
  license: MIT
---

# Docker Compose manage

Keep this skill focused on Compose files and lifecycle; image construction, Podman, registry administration, and runtime hardening have separate skills.

## Triggers

- `compose.yaml`, `compose.yml`, `docker-compose.yml`, `docker compose config|up|down|watch`
- Multi-service networking, profiles, overrides, health checks, named volumes, or Compose troubleshooting

## Load order (SAD KITTI)

```sadkitti
IF task involves Compose syntax, stack configuration, validation, or lifecycle
  REFERENCE "references/compose.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Inspect the Compose files and determine which override files, profiles, environment files, and persistent volumes are active.
2. Keep secrets out of committed YAML; fail closed for required substitutions, bind published ports to intended interfaces, and define readiness health checks for dependencies.
3. Render the merged configuration with `docker compose config` before changing or applying it; validate image references and resource settings.
4. Prefer reversible updates; never remove volumes or run destructive cleanup without listing affected data and obtaining explicit approval.

## Related skills

- Dockerfile/build changes → `infra-docker-image-build`
- Rootless/Quadlet Compose compatibility → `infra-podman-container-manage`
- Registry credentials and image digests → `infra-gcp-artifactRegistry-manage`
- Runtime hardening → `sec-container-runtime-harden`
- Production deployment strategies → `dev-release-rollout-manage`
