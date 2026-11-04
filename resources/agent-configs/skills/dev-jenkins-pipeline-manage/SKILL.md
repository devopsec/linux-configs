---
name: dev-jenkins-pipeline-manage
description: "Design, debug, and secure Jenkins declarative/scripted pipelines, Jenkinsfiles, shared libraries, agents, credential bindings, and Configuration as Code. Use when a request mentions Jenkinsfile, Jenkins pipeline, Jenkins agents, JCasC, plugin configuration, credentials binding, or Jenkins build failures."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/ci-cd/jenkins
  license: MIT
---

# Jenkins pipeline manage

Keep pipeline logic in versioned repository code and restrict controller, agent, and production credential access.

## Triggers

- `Jenkinsfile`, declarative or scripted pipeline, shared library, multibranch job, or pipeline build failure
- Jenkins agents, JCasC, credentials binding, plugin inventory, controller hardening, or GitHub-to-Jenkins hooks

## Load order (SAD KITTI)

```sadkitti
IF task involves Jenkinsfile syntax, pipeline stages, agents, credentials, or controller configuration
  REFERENCE "references/jenkins.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Identify controller/agent topology, job trust boundaries, branch source, credential scope, and whether builds can execute untrusted contributions.
2. Prefer declarative pipelines, isolated/ephemeral agents, single-quoted shell steps around secrets, and shared libraries pinned to immutable revisions.
3. Keep validation, packaging, and publication separate; publication must depend on required validation and use a dedicated least-privilege identity.
4. Validate the Jenkinsfile with the configured linter, inspect plugin/runtime compatibility before upgrades, and report required controller or credential changes.

## Related skills

- GitHub Actions → `dev-github-actions-manage`
- In-house Cloud Build → `dev-gcp-cloudBuild-manage`
- Release lifecycle → `dev-release-semver-manage`, `dev-release-rollout-manage`
- Image build and registry → `infra-docker-image-build`, `infra-gcp-artifactRegistry-manage`
