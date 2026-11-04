# Tag-driven release pipeline

Provider-specific pipeline mechanics belong to `dev-github-actions-manage`, `dev-jenkins-pipeline-manage`, or the in-house `dev-gcp-cloudBuild-manage`. This file covers the provider-neutral release process; retain the project's `release.yaml` name only where that configured pipeline uses it.

## Model

```
merge to protected branch ──► build pipeline ──► <pkg>/git-<SHORT_SHA>  (immutable build; checksum + metadata)
                                      ▲
tag vX.Y.Z ─────► tag-triggered release.yaml ───────┘ proves: tag → commit → git-<SHA> → sha256:<digest>
                                      │
                                      ▼
            release manifest (deployments repo, reviewed PR)  ──►  image bake / rollout
```

- **Build ≠ release.** Every merge yields a build; only a tag makes a release. Semantic versions are metadata, never registry addresses.
- **Tag = authoritative identity + approval event.** Protected tag rule `v*`: anyone with write access may create, nobody may update/delete.
- **Verification creates nothing.** The release identity is read-only on the registry; recording the mapping is a separate reviewed PR.

## Cutting a release (checklist)

1. Fetch tags and review the commit range from the last release tag to the approved release branch.
2. Compute version: `git cliff --bumped-version` (sanity-check against the commits).
3. Changelog/notes: `git cliff --unreleased --tag vX.Y.Z` → paste into the GitHub Release, or merge a changelog PR first (then the tagged commit is the changelog merge — wait for *its* build).
4. Confirm the green merge-build check on the exact target commit.
5. Create the protected `vX.Y.Z` tag and release record in the configured forge only after user approval.
6. Check the provider's read-only run history for the tag-triggered `release.yaml` result; Cloud Build command details belong in `dev-gcp-cloudBuild-manage`.
7. On success: PR the proven `{version, commit, build, sha256}` into the release manifest; downstream bake/rollout keys off it.

Annotated tags may carry claims (`sha256:<digest>`, short SHA); the pipeline holds them to it. Lightweight tags (release button) make no claims — the chain is the proof.

## Failure handling

| Failure | Meaning | Action |
|---|---|---|
| no artifact for commit | tagged before merge build finished / build failed | do **not** move the tag; fix/wait, cut next patch `vX.Y.(Z+1)` |
| commit/version mismatch | metadata from a different build | investigate publishing pipeline; next patch after fix |
| digest mismatch (sidecar or metadata) | tampering or corruption | treat as security incident (`sec-ops-incident-respond`); do not deploy |
| tag message claims different digest | wrong annotated tag message | next patch with a correct message or a lightweight tag |

## Pre-releases

`vX.Y.Z-rc.N` tags for staging soak; the tag trigger regex decides whether RCs run verification (`^v\d+\.\d+\.\d+(-rc\.\d+)?$`). Promote by tagging the **same commit** `vX.Y.Z` — the artifact digest is identical, so the proof carries over.

## Hotfix

Branch from the release tag only if `main` has moved on with unreleasable changes: `git switch -c hotfix/vX.Y.(Z+1) vX.Y.Z` → fix → the hotfix branch needs its own build pipeline trigger (merge builds only run on `main`) → tag → forward-port the fix to `main`. Prefer fixing forward on `main` when possible.
