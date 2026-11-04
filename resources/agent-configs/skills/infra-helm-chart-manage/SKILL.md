---
name: infra-helm-chart-manage
description: "Author, lint, render, package, and operate Kubernetes Helm charts and releases with Helm 4. Use when requests mention Chart.yaml, values.yaml, templates, Chart.lock, OCI chart, `helm upgrade`, or Helm rollback."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/orchestration/helm-charts
  license: MIT
---

# Helm chart manage

Author reproducible charts and operate releases through an explicit render, diff, approval, and rollback path.

## Triggers

- Helm chart, `Chart.yaml`, `values.yaml`, `Chart.lock`, templates, OCI charts
- `helm lint`, `helm template`, upgrade/install, release history, rollback, CRDs

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or Kubernetes README if present
IF task involves chart layout, rendering, release, or rollback
  REFERENCE "references/helm-chart.md"
IF the chart deployment is also a Kustomize overlay
  REFERENCE skill "infra-kustomize-overlay-manage"
IF workload templates or cluster security policy is needed
  REFERENCE skill "infra-kubernetes-workload-manage" OR "sec-kubernetes-cluster-harden"
CACHE cluster context, namespace, chart version, values source, and release owner
```

## Workflow

1. Confirm Helm binary (`4.3.1`, checked 2026-10-28), target context, release, namespace, and chart version.
2. Keep chart version and application version separate; lock dependencies and images by digest.
3. Run `helm lint`, render exact production values, and server-side validate against the target cluster version.
4. Review a release diff, CRD changes, hook behavior, permissions, and secret references before approval.
5. Apply with failure rollback and wait settings; verify release status and retain the previous revision.
6. Roll back via Helm only after understanding data/schema compatibility.

## Related skills

- `infra-kubernetes-workload-manage` — workload semantics and read-only diagnostics.
- `infra-kustomize-overlay-manage` — overlays and rendering.
- `sec-kubernetes-cluster-harden` — workload/cluster security controls and certificates.
- `infra-gcp-artifactRegistry-manage` — registry authentication where available.
