---
name: dev-release-semver-manage
description: "Determine SemVer bumps from Conventional Commits, prepare changelogs and release notes, and manage protected version tags and release-artifact verification. Use when a request mentions semver, vX.Y.Z, version bump, Conventional Commits, CHANGELOG.md, git-cliff, release notes, release tag, or release verification."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/release/semantic-versioning
  license: MIT
---

# Release SemVer manage

This skill handles version selection, human-facing notes, and release identity. Provider-specific pipeline mechanics and deployment rollouts live elsewhere.

## Triggers

- `vX.Y.Z` tags, SemVer bumps, prereleases, Conventional Commits, `CHANGELOG.md`, or release notes
- `git-cliff`, `uv version`, release PRs, tag protection, or tag-to-build artifact verification

## Load order (SAD KITTI)

```sadkitti
IF file "~/.junie/custom/configs/dev/release-semver.toml" exists
  REFERENCE "~/.junie/custom/configs/dev/release-semver.toml"
ELSE use defaults: SemVer 2.0.0; Conventional Commits; git-cliff v2.14.2 (checked 2026-10-28); changelog reviewed by a human; immutable protected tags
IF task involves bump selection or changelog/release-note generation
  REFERENCE "references/semver-changelog.md"
IF task involves protected tag or artifact verification flow
  REFERENCE "references/release-pipeline.md"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Review commits since the last release and determine the public compatibility boundary; breaking changes are major after 1.0, minor before 1.0.
2. Generate and review changelog/release notes; keep one authoritative version source and describe migrations for breaking changes.
3. Verify the target commit has a successful immutable build artifact and that the release pipeline proves tag, commit, and digest correspondence.
4. Obtain explicit approval before creating or publishing a tag/release; never move or delete a published tag to repair a failed release.

The versioning/release policy example is `assets/config.example.toml`; do not create or modify files under `~/.junie/custom`.

## Related skills

- Commit message conventions → `vcs-git-commit-create`
- GitHub Actions/Jenkins CI → `dev-github-actions-manage`, `dev-jenkins-pipeline-manage`
- In-house Cloud Build pipeline behavior → `dev-gcp-cloudBuild-manage`
- Progressive deployment/rollback → `dev-release-rollout-manage`
- Image digest and registry controls → `infra-gcp-artifactRegistry-manage`
