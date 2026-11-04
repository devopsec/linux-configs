---
name: dev-gcp-cloudBuild-manage
description: "Design, review, and troubleshoot Google Cloud Build pipelines. Use when a task mentions Cloud Build, cloudbuild.yaml, gcloud builds or triggers, substitutions, availableSecrets/secretEnv, service accounts, PR/main/release pipeline separation, caching, uv/Python CI, or blocking scan gates."
---

# Google Cloud Build manage

## Triggers

- Cloud Build YAML, triggers, build substitutions, and step ordering.
- Secret Manager integration through `availableSecrets` and `secretEnv`.
- Build service accounts, PR/main/release boundaries, logs, and Artifact Registry access.
- `/workspace` and cross-build caching, Python/uv build steps, or vulnerability-scan gates.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF task involves Cloud Build configuration, triggers, identities, secrets, or build gates
  REFERENCE "references/cloud-build.md"
IF a project companion exists at "project-refs/dev-gcp-cloudBuild-manage/isen-cloud-build.md"
  REFERENCE that companion for local mappings and known exceptions only
CACHE loaded reference summaries for the rest of this task
```

Load the project companion only when working in the matching repository; keep its identities and local exceptions out of generic guidance.

## Workflow

1. Map each trigger event, branch/tag filter, region, configuration file, service account, and permitted output before editing.
2. Keep PR validation, post-merge publishing, and release verification as distinct pipelines with separate least-privilege identities.
3. Use explicit substitutions/environment mapping, secrets only in trusted steps, and `waitFor` dependencies that make every required check a prerequisite to publishing.
4. Make tests and security scans blocking by default. Any temporary exception must be reviewed, conspicuous, scoped, and time-bounded; never mask scanner failures.
5. Cache only non-sensitive dependencies, distinguishing data shared among steps in one build from cache persisted between builds.
6. Validate YAML and the step graph; run a build only in an approved sandbox. Do not mutate triggers, IAM, or production artifacts without explicit approval.

## Related skills

- Artifact Registry repository and IAM work → `infra-gcp-artifactRegistry-manage`
- Version tags and release policy → `dev-release-semver-manage`
- Python dependency or source scanning → `sec-python-dependency-scan` / `sec-code-sast-scan`

## References

| File | When |
|------|------|
| [references/cloud-build.md](references/cloud-build.md) | Cloud Build design, config, security, and validation |
