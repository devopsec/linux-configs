---
name: infra-gcp-artifactRegistry-manage
description: "Create and administer Google Cloud Artifact Registry Docker repositories, IAM, authentication, image publication, digest lookup, and cleanup policies. Use when a request mentions Artifact Registry, gcloud artifacts repositories, docker.pkg.dev, registry writer/reader roles, immutable tags, or GCP container image retention."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/containers/container-registries
  license: MIT
---

# GCP Artifact Registry manage

This skill covers only Google Cloud Artifact Registry. Other providers and image construction are handled by related skills.

## Triggers

- `gcloud artifacts repositories`, `docker.pkg.dev`, Docker-format repositories, or Artifact Registry IAM
- Image push/pull authentication, immutable tags, digest lookup, retention, or vulnerability occurrences

## Load order (SAD KITTI)

```sadkitti
IF task involves a registry image build
  REFERENCE "references/artifact-registry.md"
CACHE loaded reference summary for the rest of this task
```

## Workflow

1. Ask for or read the configured project, location, repository, image, and caller identity; never infer site values or embed service-account keys.
2. Choose the narrowest IAM role: writers only for publishing identities, readers for deployers; prefer workload identity or attached service accounts.
3. Use immutable tags when policy allows and deploy by digest; verify the pushed digest before recording it in a release manifest.
4. Preview cleanup policy effects before applying them and retain rollback/release artifacts for the agreed window.

## Related skills

- Docker image construction → `infra-docker-image-build`
- Podman registry configuration → `infra-podman-container-manage`
- Supply-chain signing/SBOM → `sec-artifact-sbom-sign`
- CI publishers → `dev-github-actions-manage`, `dev-jenkins-pipeline-manage`, or in-house `dev-gcp-cloudBuild-manage`
- Release tagging and artifact verification → `dev-release-semver-manage`
