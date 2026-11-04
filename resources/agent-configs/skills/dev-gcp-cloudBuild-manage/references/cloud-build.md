# Google Cloud Build patterns

## Trigger and pipeline design

Trigger definitions are separate Cloud Build resources; they are not declared by `steps` in the build YAML. Record the repository connection, event, branch or tag filter, region, config path, trigger substitutions, and build service account for each trigger. Inspect trigger definitions read-only before changing a pipeline.

| Pipeline | Inputs | Required result | Identity boundary |
|---|---|---|---|
| PR validation | Pull request and its source revision | Lint, tests, and blocking security scans; publish nothing | No registry write and no secrets for untrusted/fork PRs |
| Main build | Merge commit on the protected default branch | Repeat required checks, then build and publish only after all pass | Dedicated writer limited to the intended repository |
| Release verification | Protected semantic-version tag | Prove tag → commit → already-built artifact → digest; do not rebuild or republish | Read-only access to the artifact under verification |

Use separate, user-managed service accounts per trust boundary. Grant only the required logging and resource roles; do not use “omit the step” as the publishing control. A PR identity should lack registry write permission, the main publisher should write only to its target, and a verification identity should be read-only. When a custom service account is set, configure an explicit logging destination such as `options.logging: CLOUD_LOGGING_ONLY` (or a deliberately configured log bucket).

Keep PR, merge, and tag triggers narrow and explicit. Treat fork-controlled source as untrusted: do not expose credentials, writable registry access, or a trusted cache to it. If a trigger's actual filter, identity, or substitutions are managed outside the YAML, inspect that resource as well; changing the YAML alone does not change the trigger.

## Substitutions and step data flow

Use custom substitutions named `_UPPER_CASE` for non-secret configuration and built-ins such as `PROJECT_ID`, `COMMIT_SHA`, and `SHORT_SHA` for build metadata. Substitutions are not secrets and may appear in build configuration or logs. Prefer an explicit `env:` allowlist for `script:` steps:

```yaml
substitutions:
  _REGION: us-central1
  _UV_IMAGE: ghcr.io/astral-sh/uv:0.13.6-python3.11-bookworm
  _CLOUD_CLI_IMAGE: gcr.io/google.com/cloudsdktool/google-cloud-cli:590.0.0

steps:
  - id: deps
    name: ${_UV_IMAGE}
    env:
      - UV_CACHE_DIR=/workspace/.uv-cache
      - UV_PYTHON_VERSION=3.11.18
    script: |
      #!/usr/bin/env bash
      set -euo pipefail
      uv lock --check
      uv sync --locked --all-packages
```

Cloud Build substitutes fields such as `env:` and `args:` before execution, while scripts consume environment variables. Map only values a step needs, or use `automapSubstitutions` deliberately; build-level automatic mapping exposes all built-in and custom substitutions to every step unless overridden at the step level. In `args:`, use `$$NAME` when the shell, rather than Cloud Build, must expand `$NAME`. Triggered builds have substitution behavior that differs from manual builds; explicitly validate required values instead of relying on an omitted substitution to fail.

Give each step a stable `id`. Use `waitFor: ['-']` only for independent steps that can start immediately; otherwise wait on the actual prerequisite IDs. A package/publish step must explicitly wait for every required lint, typecheck, test, and scan step. Avoid implicit ordering assumptions when adding a gate.

## Secrets and service-account access

Use Secret Manager only when a build genuinely needs a credential. Declare the secret at build scope and inject it only into the step that uses it:

```yaml
availableSecrets:
  secretManager:
    - versionName: projects/${PROJECT_ID}/secrets/<SECRET_NAME>/versions/${_SECRET_VERSION}
      env: BUILD_TOKEN

steps:
  - id: authenticated-check
    name: ${_CLOUD_CLI_IMAGE}
    secretEnv: ['BUILD_TOKEN']
    script: |
      #!/usr/bin/env bash
      set -euo pipefail
      tool --token-file <(printf '%s' "$BUILD_TOKEN")
```

Grant `secretmanager.secretAccessor` on the individual secret to the relevant build service account, not project-wide. Pin a numbered secret version for repeatable releases; use `latest` only when the operational rotation contract explicitly requires it. Never echo a secret, put it in substitutions, enable `set -x` around its use, or pass it to a PR build that can execute untrusted code.

## Python and blocking scan gates

Treat the committed `pyproject.toml`, `uv.lock`, and Python-version policy as the build inputs. A typical dependency step runs `uv lock --check` and `uv sync --locked`; independent typecheck, compile, test, and scan steps can then share the installed environment. Keep check tools in a locked project group and invoke them through that lock rather than fetching an unpinned tool in CI.

For a dependency audit, export only third-party dependencies and fail the step on scanner findings or scanner errors:

```bash
uv export --locked --all-packages --no-emit-workspace --format requirements-txt \
  -o /workspace/requirements.scan.txt
uv run --locked --group ci pip-audit --requirement /workspace/requirements.scan.txt
```

Make required scans blocking in both PR validation and the merge build. Do not add `allowFailure`, `allowExitCodes`, `|| true`, or status-swallowing logic to a required gate. If an approved temporary exception is unavoidable, document the exact finding, owner, expiry/revisit date, affected branch, and compensating check; keep it conspicuously advisory and do not describe it as a pass. Scanner startup, feed, or authentication failures are not clean results. Release verification should validate the exact artifact produced by the gated main build rather than skip the gate or rebuild from the tag.

If no test runner exists, report that tests were not run rather than converting absence into a passing test result. For a dynamically detected runner, first prove that the selected Python interpreter works; a failed import alone cannot distinguish a missing test package from a broken environment.

## Caching and reproducibility

Cloud Build's `/workspace` volume and named volumes share data among steps for the duration of one build. Setting `UV_CACHE_DIR=/workspace/.uv-cache` avoids repeat downloads among those steps, but does **not** persist a cache across separate builds. For cross-build reuse, follow Cloud Build's Cloud Storage cache pattern or a registry-backed build cache; key it on the lockfile, Python version, OS/architecture, and relevant tool versions. Do not treat cached state as authoritative, cache secrets, share writable trusted caches with untrusted PRs, or reuse an interpreter-specific `.venv` across incompatible environments.

Use immutable artifact identities (for example, the source commit) and record a checksum and source metadata. A release check should compare the downloaded artifact against both its checksum sidecar and its recorded metadata. A retry that finds an existing immutable version must verify the bytes and source revision; unknown API/authentication outcomes must fail closed.

## Checked version pins

Checked 2026-10-28 against official release sources. Use exact version tags and preferably their verified image digests; do not use floating `stable`, `slim`, or `latest` tags in a release-critical build.

| Component | Version checked | Selection note |
|---|---:|---|
| Google Cloud CLI | `590.0.0` | Versioned CLI container tag; Oct 20 release |
| uv | `0.13.6` | Versioned uv image/tool; Oct 27 release |
| Python | `3.15.1` | Current stable release; Oct 21 |
| Python 3.11 line | `3.11.18` | Patch release for projects constrained to Python 3.11; Oct 25 |

Choose the Python line from the project's compatibility policy rather than upgrading it solely to match the newest release. Keep the `uv` executable and interpreter pinned independently where needed; a `python3.11` image tag is a minor-line tag, not a patch-level pin. The lockfile pins Python package resolution, not the container image itself.

## Safe inspection and validation

- Read the config and trigger definition before proposing a change; check that all required checks are ancestors of packaging/publishing.
- Parse YAML locally and review Cloud Build's schema; do not treat successful YAML parsing as proof of valid Cloud Build fields or IAM.
- Use read-only `gcloud builds triggers list` / `describe` commands to inspect triggers. Submit builds only to an approved sandbox, never to a production publishing target as a test.
- Report changes to trigger filters, service accounts, IAM, secret access, scanner enforcement, and artifact permissions separately.

## Sources (checked 2026-10-28)

- [Cloud Build build-config schema](https://docs.cloud.google.com/build/docs/build-config-file-schema)
- [Run Bash scripts](https://docs.cloud.google.com/build/docs/configuring-builds/run-bash-scripts) and [substitution values](https://docs.cloud.google.com/build/docs/configuring-builds/substitute-variable-values)
- [Secret Manager in Cloud Build](https://docs.cloud.google.com/build/docs/securing-builds/use-secrets)
- [Pass data between build steps](https://docs.cloud.google.com/build/docs/configuring-builds/pass-data-between-steps) and [speeding up builds](https://docs.cloud.google.com/build/docs/optimize-builds/speeding-up-builds)
- [Google Cloud CLI release notes](https://docs.cloud.google.com/sdk/docs/release-notes) and [Docker images](https://docs.cloud.google.com/sdk/docs/downloads-docker)
- [uv Docker integration](https://docs.astral.sh/uv/guides/integration/docker) and [uv releases](https://github.com/astral-sh/uv/releases)
- [Python downloads](https://www.python.org/downloads/)