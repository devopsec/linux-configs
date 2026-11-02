# GitHub Actions

Reviewed release pins (checked 2026-10-28):

| Action | Release | Immutable commit SHA |
|---|---|---|
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `astral-sh/setup-uv` | `v10.3.2` | `07a047e608db84b3d8c06cd9a7c7dcc9c355c18e` |
| `google-github-actions/auth` | `v3.0.0` | `7c6bc770dae815cd3e89ee6cdf493a5fab2cc093` |
| `google-github-actions/setup-gcloud` | `v3.0.1` | `aa5489c8933f4cc7a4f7d45035b3b1440c9c10db` |

Self-hosted Actions Runner `2.338.0` is the release checked on 2026-10-28. Pin every action to its reviewed 40-character commit SHA and record the release tag beside the SHA; use the release-published checksum for runner downloads.

Pin third-party actions by full commit SHA (`uses: owner/action@<40-hex> # vX.Y.Z`); let Dependabot/Renovate bump them.

## Baseline workflow (Python + uv)

```yaml
name: ci
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
permissions:
  contents: read                       # default-deny; widen per job
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  validate:
    runs-on: ubuntu-24.04
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1; checked 2026-10-28
        with: { persist-credentials: false }
      - uses: astral-sh/setup-uv@07a047e608db84b3d8c06cd9a7c7dcc9c355c18e # v10.3.2; checked 2026-10-28
        with: { enable-cache: true }
      - run: uv lock --check
      - run: uv sync --locked --all-packages
      - run: uv run ty check src
      - run: uv run pytest -q
      - run: |
          uv export --locked --no-emit-workspace --no-hashes --format requirements-txt > req.txt
          uvx pip-audit -r req.txt
      - run: git ls-files -z '*.sh' | xargs -0 -r shellcheck -S error
```

## GCP without keys (Workload Identity Federation)

```yaml
jobs:
  publish:
    needs: validate
    if: github.event_name == 'push'
    runs-on: ubuntu-24.04
    permissions: { contents: read, id-token: write }
    environment: production              # required reviewers / branch rules
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1; checked 2026-10-28
      - uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3.0.0; checked 2026-10-28
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}   # projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<prov>
          service_account: ${{ vars.GCP_PUBLISHER_SA }}
      - uses: google-github-actions/setup-gcloud@aa5489c8933f4cc7a4f7d45035b3b1440c9c10db # v3.0.1; checked 2026-10-28
      - run: gcloud auth configure-docker "${{ vars.GCP_REGION }}-docker.pkg.dev" --quiet
```

Restrict the WIF provider with an attribute condition (e.g. `assertion.repository == "org/repo" && assertion.ref == "refs/heads/main"`). No JSON keys in secrets.

## Patterns

- Matrix example (CPython `3.12.16` and `3.13.18`, checked 2026-10-28): `strategy: { fail-fast: false, matrix: { python: ["3.12.16", "3.13.18"] } }`.
- Job deps: `needs: [validate]`; outputs via `$GITHUB_OUTPUT` (`echo "digest=$d" >> "$GITHUB_OUTPUT"`).
- Reusable workflows: `on: workflow_call` with typed `inputs`/`secrets`; call `uses: org/repo/.github/workflows/x.yml@<sha>`; pass `secrets: inherit` only within the same org/trust.
- Manual: `workflow_dispatch` with `inputs` (choice types as allowlists).
- Schedules: `cron` in UTC; jobs on default branch only.
- Artifacts: `upload-artifact` with `retention-days`; artifacts are not a release store.
- Environments: protection rules + environment-scoped secrets for deploy jobs.

## Security

- `pull_request_target` and `workflow_run` run with base-repo secrets: never check out or execute fork code there. The pinned checkout `v7.0.1` refuses unsafe fork checkout by default; do not opt out.
- Untrusted input (`github.event.pull_request.title`, branch names, issue bodies) must not be interpolated into `run:`; pass via `env:` and quote: `env: { TITLE: ${{ github.event.pull_request.title }} }` → `"$TITLE"`.
- `permissions:` minimal at workflow level; `persist-credentials: false` unless pushing.
- Mask derived secrets: `echo "::add-mask::$value"`.
- Audit workflows with `zizmor` or `actionlint`.

## Self-hosted runners

- Use ephemeral runners (`--ephemeral`, or Actions Runner Controller on GKE); never attach self-hosted runners to public repos.
- Install: download the pinned release tarball **and verify its SHA-256** (published in the release notes) before `./config.sh`:

```bash
RUNNER_VERSION=2.338.0        # checked 2026-10-28
curl -fsSLO "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
echo "af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32  actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | sha256sum -c -
tar -xzf "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
./config.sh --url "https://github.com/${OWNER}/${REPO}" --token "${RUNNER_REG_TOKEN}" --ephemeral --unattended
```

Registration token is short-lived (from API/UI); never commit it. Run as a dedicated unprivileged user via the generated systemd service.

## Debugging

- Re-run with debug logging (`ACTIONS_STEP_DEBUG=true` repo variable/secret, or "Enable debug logging" on re-run).
- With forge (`vcs-forge-any-manage`; `gh` is not used): `forge ci list [-b branch] [--workflow file]`,
  `forge ci view <run-id>` (lists job IDs) then `forge ci log <job-id>` for a failed job,
  `forge ci retry <run-id>`, `forge ci run <file> -b <ref> -F key=value` (ask first: it starts a run).
  Check runs for a commit: `forge api 'repos/{owner}/{repo}/commits/<sha>/check-runs' | jq '.check_runs[] | {name, conclusion}'`.
- Local: `act` for rough checks (not identical to hosted runners).

| Symptom | Fix |
|---|---|
| Workflow not triggering | YAML error, path/branch filters, file not on default branch for `workflow_dispatch`/`schedule` |
| `Resource not accessible by integration` | missing `permissions:` scope |
| OIDC `audience`/`subject` mismatch | WIF attribute condition vs repo/ref |
| Cache never restores | key includes changing value; use `hashFiles('uv.lock')` |
| Runner offline / refuses jobs | runner below minimum version — update |
