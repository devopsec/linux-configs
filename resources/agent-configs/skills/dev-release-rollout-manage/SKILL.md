---
name: dev-release-rollout-manage
description: "Plan and operate progressive application releases to Linux VMs, SIP/RTP services, and Kubernetes using canary, rolling, blue-green, drain, health observation, and rollback procedures. Use when a request mentions rollout, canary, blue-green, rolling update, rollback, deployment drain, SIP dialog safety, MIG update, Kubernetes rollout, or Argo Rollouts."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/release/blue-green-deploy
  license: MIT
---

# Release rollout manage

Use this skill for deployment sequencing and rollback; it does not choose versions or build release artifacts.

## Triggers

- VM or Kubernetes canary/rolling/blue-green deployment, release manifest, or rollout strategy
- SIP/RTP service drain, active sessions, health thresholds, rollback, instance group updates, or Argo Rollouts

## Load order (SAD KITTI)

```sadkitti
IF task involves VM, instance-group, or SIP/RTP rollout
  REFERENCE "references/rollout-vm.md"
IF task involves Kubernetes rollout strategy
  REFERENCE "references/rollout-kubernetes.md"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Confirm the approved artifact digest, target population, maintenance window, operator/approver, current health baseline, and rollback target.
2. Define measurable abort thresholds and bake time before deployment; obtain missing site values from the user or approved config rather than guessing.
3. Start with one node or the smallest canary; for stateful/SIP services stop new traffic and wait for active sessions to drain before restart.
4. Expand only while health remains within agreed thresholds; rollback through the owning deployment mechanism and re-check health and data compatibility.
5. Obtain explicit approval before production rollout or rollback; record the deployed digest, result, and follow-up actions.

## Related skills

- Version/tag/release verification → `dev-release-semver-manage`
- VM provisioning and infrastructure → `infra-opentofu-any-manage`
- Kubernetes workload mechanics → `infra-kubernetes-workload-manage`
- SIP routing/service-specific drain details → `dev-kamailio-platform-manage`
- In-house release pipeline behavior → `dev-gcp-cloudBuild-manage`
