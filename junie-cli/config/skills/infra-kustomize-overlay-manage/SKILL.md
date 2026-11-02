---
name: infra-kustomize-overlay-manage
description: "Build, render, validate, and apply Kubernetes Kustomize bases and overlays with digest-pinned images and scoped patches. Use when requests mention kustomization.yaml, `kubectl apply -k`, `kubectl kustomize`, overlays, components, patches, or Kustomize image updates."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/orchestration/kustomize
  license: MIT
---

# Kustomize overlay manage

Maintain base/overlay composition for Kubernetes manifests, then render and diff the exact environment before applying.

## Triggers

- `kustomization.yaml`, base/overlay, component, strategic/JSON patch
- `kubectl apply -k`, `kubectl kustomize`, image digest, ConfigMap generator

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or Kubernetes README if present
IF file exists "~/.junie/custom/configs/infra/kustomize.toml"
  REFERENCE "~/.junie/custom/configs/infra/kustomize.toml"
ELSE
  use kubectl's embedded Kustomize renderer; use standalone Kustomize 5.8.3 only when a required feature is absent
IF task involves overlays, patches, generators, or rendering
  REFERENCE "references/kustomize-overlays.md"
IF a release is managed by Helm
  REFERENCE skill "infra-helm-chart-manage"
IF workload security policy is involved
  REFERENCE skill "infra-kubernetes-workload-manage" OR "sec-kubernetes-cluster-harden"
CACHE context, namespace, overlay path, target server version, and image digest
```

## Workflow

1. Confirm context, overlay, management owner, Kubernetes API version, and image provenance.
2. Render locally with the configured tool; run schema validation and server-side dry-run against the target cluster.
3. Review patch targets, selectors, namespace, generators, secret handling, and deletion/pruning effects.
4. Apply only after explicit approval; use the owning overlay source and avoid unmanaged pruning.
5. Verify the rollout, generated ConfigMap hashes, and controller health.

## Related skills

- `infra-kubernetes-workload-manage` — workloads, rollout checks, diagnostics.
- `infra-helm-chart-manage` — Helm charts and releases.
- `sec-kubernetes-cluster-harden` — security policies and hardening.
