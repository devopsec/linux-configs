---
name: infra-podman-container-manage
description: "Manage Podman containers and images on Linux hosts, especially rootless Podman, Buildah, pods, Quadlet/systemd units, and SELinux volume labeling on RHEL-family distributions. Use when a request mentions podman, rootless containers, podman.socket, Quadlet, *.container units, Buildah, subuid/subgid, or SELinux container volumes."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/containers/podman
  license: MIT
---

# Podman container manage

Use Podman-specific host/runtime operations here. Docker Compose portability and registry configuration are handled by separate skills.

## Triggers

- `podman run|build|inspect|system`, rootless containers, `podman.socket`, pods, or Buildah
- Quadlet `.container`/`.volume`/`.network` units, systemd integration, UID maps, or SELinux labels

## Load order (SAD KITTI)

```sadkitti
IF task involves rootless Podman, Quadlet, Buildah, or SELinux container behavior
  REFERENCE "references/podman.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Identify the distribution, SELinux state, rootless/rootful requirement, service lifecycle, and required port/network behavior.
2. Prefer rootless execution where feasible; inspect subordinate UID/GID mappings before changing them and use distribution-managed Podman packages.
3. For persistent services, prefer Quadlet-managed systemd units; review volume labels, resource limits, capabilities, and secret injection.
4. Validate generated units with the Quadlet dry-run path and inspect service logs before enabling any host-level change. Treat rootful, network, and relabel operations as privileged changes requiring approval.

## Related skills

- Compose application definitions → `infra-docker-compose-manage`
- Dockerfile/BuildKit image builds → `infra-docker-image-build`
- Artifact Registry auth and image references → `infra-gcp-artifactRegistry-manage`
- Container isolation controls → `sec-container-runtime-harden`
- Host firewall/SELinux baseline → `sec-linux-hostFirewall-manage`
