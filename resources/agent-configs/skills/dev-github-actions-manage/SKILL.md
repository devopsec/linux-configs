---
name: dev-github-actions-manage
description: "Create, debug, and secure GitHub Actions workflows, reusable workflows, environments, OIDC federation, and hosted or self-hosted runners. Use when a request mentions .github/workflows, GitHub Actions, workflow YAML, uses:, permissions:, pull_request_target, GITHUB_TOKEN, OIDC, or runner failures."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/ci-cd/github-actions
  license: MIT
---

# GitHub Actions manage

Manage GitHub Actions only; Cloud Build is an in-house skill and Jenkins has a separate skill.

## Triggers

- `.github/workflows/*.yml`, `uses:`, workflow events, permissions, concurrency, reusable workflows, or environments
- GitHub-hosted/self-hosted runners, OpenID Connect, Workload Identity Federation, `pull_request_target`, or Actions security reviews

## Load order (SAD KITTI)

```sadkitti
IF file "~/.junie/custom/configs/dev/github-actions.toml" exists
  REFERENCE "~/.junie/custom/configs/dev/github-actions.toml"
ELSE use defaults: actionlint for workflow syntax; zizmor for workflow security review
IF task involves GitHub Actions workflow design, execution, or security
  REFERENCE "references/github-actions.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Map event triggers, trust level (fork or trusted branch), permissions, secret exposure, runner type, and artifacts produced.
2. Set minimal workflow/job `permissions`; pass untrusted event data through quoted environment variables, not interpolated shell source.
3. Pin third-party actions to reviewed full commit SHAs, disable persisted checkout credentials unless required, and use OIDC instead of long-lived
   cloud keys.
4. Run configured syntax/security checks, verify the workflow on a safe branch, and report required permission or runner changes.

The tool-selection example is `assets/config.example.toml`; do not create or modify files under `~/.junie/custom`.

## Related skills

- Jenkins pipelines → `dev-jenkins-pipeline-manage`
- In-house Cloud Build → `dev-gcp-cloudBuild-manage`
- Release versioning and rollout → `dev-release-semver-manage`, `dev-release-rollout-manage`
- Image build and registry details → `infra-docker-image-build`, `infra-gcp-artifactRegistry-manage`
