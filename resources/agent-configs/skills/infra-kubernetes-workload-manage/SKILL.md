---
name: infra-kubernetes-workload-manage
description: "Operate Kubernetes workloads with kubectl, including deployments, statefulsets, jobs, rollouts, probes, resource limits, and read-only diagnostics. Use when requests mention kubectl, pods, CrashLoopBackOff, rollout, HPA, namespace workload, or Kubernetes events/logs."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/orchestration/kubernetes-ops
  license: MIT
---

# Kubernetes workload manage

Use kubectl to inspect and operate application workloads; keep Helm/Kustomize-managed objects in their source tool.

## Triggers

- `kubectl`, pod, Deployment, StatefulSet, DaemonSet, Job, CronJob, HPA, PDB
- CrashLoopBackOff, ImagePullBackOff, rollout, probes, namespace resources, Kubernetes events/logs

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves workload lifecycle, kubectl diagnostics, rollouts, or resources
  REFERENCE "references/workload-operations.md"
  REFERENCE "scripts/k8s-diagnose.sh" only for read-only cluster/pod diagnostics
  REFERENCE "assets/deployment-template.yaml" only for a hardened Deployment skeleton
IF a release is managed by Helm
  REFERENCE skill "infra-helm-chart-manage"
IF a release is managed by Kustomize
  REFERENCE skill "infra-kustomize-overlay-manage"
IF task is cluster-level security policy or certificate management
  REFERENCE skill "sec-kubernetes-cluster-harden"
CACHE kube context, namespace, resource owner, and production status before commands
```

## Workflow

1. Print and confirm the active context, cluster, namespace, and resource owner before any command that changes state.
2. Start with read-only `get`, `describe`, `events`, and bounded logs; redact credentials and user data in outputs.
3. Diagnose scheduling, readiness, image identity, resources, configuration, and service endpoints before proposing a fix.
4. Use probes, requests, security contexts, disruption budgets, and immutable image digests for workload manifests.
5. Preview changes; apply only with explicit approval. Roll Helm/Kustomize objects through their owning tool, not `kubectl rollout undo`.
6. Verify readiness, events, metrics, and application-level behavior after an approved rollout.

## Related skills

- `infra-helm-chart-manage` — chart packaging and release lifecycle.
- `infra-kustomize-overlay-manage` — base/overlay rendering and apply.
- `sec-kubernetes-cluster-harden` — PSA, RBAC, NetworkPolicy, and cert-manager.
- `infra-gcp-gke-manage` — GKE cluster and node operations.
