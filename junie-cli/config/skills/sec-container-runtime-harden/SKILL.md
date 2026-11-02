---
name: sec-container-runtime-harden
description: "Assess and harden OCI container images and Docker/Podman runtime settings: non-root identity, read-only filesystems, capabilities, seccomp, resource limits, image scanning, and socket/mount risks. Use when a request mentions container hardening, Docker run security flags, Trivy, Grype, distroless, container CVEs, privileged mode, or container escape exposure."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/hardening/container-hardening
  license: MIT
---

# Container runtime harden

Apply least privilege at image and runtime boundaries. Kubernetes admission and cluster policy are outside this skill.

## Triggers

- Image/runtime security reviews, `--privileged`, host mounts, container sockets, capabilities, seccomp, or read-only root filesystems
- Container vulnerability scans, Trivy, Grype, non-root identity, distroless images, or runtime resource limits

## Load order (SAD KITTI)

```sadkitti
IF file "~/.junie/custom/configs/security/container-runtime.toml" exists
  REFERENCE "~/.junie/custom/configs/security/container-runtime.toml"
ELSE use defaults: Trivy image scan; fail on HIGH and CRITICAL; preserve default seccomp, AppArmor, and SELinux policy
IF task involves image or runtime security controls
  REFERENCE "references/runtime-hardening.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Identify engine, privilege boundary, image digest, host policy, and workload needs; use only the selected scanner and thresholds from config or defaults.
2. Check image provenance, secrets/layers, base-image digest, user, filesystem, capabilities, mounts/sockets, network exposure, and resource limits.
3. Recommend the smallest safe change, scan the exact digest, and record any exception with an owner, rationale, and expiry; do not weaken a gate to clear findings.
4. Validate behavior in a non-production environment before recommending deployment.

The bundled scanner/runtime settings example is `assets/config.example.toml`; do not create or modify files under `~/.junie/custom`.

## Related skills

- Image build changes → `infra-docker-image-build`
- Compose configuration → `infra-docker-compose-manage`
- Podman/Quadlet policy → `infra-podman-container-manage`
- Kubernetes security context and policy → `sec-kubernetes-cluster-harden`
- SBOM, signing, and attestations → `sec-artifact-sbom-sign`
