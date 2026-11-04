# Python dependency scanning

## Lockfile-first scan

The latest upstream release pages checked on `2026-10-28` reported pip-audit `2.10.1` and OSV-Scanner `v2.7.0`; pin those exact versions in the project toolchain and verify release checksums/signatures where available. For `uv` projects, verify the lock before scanning and export the locked third-party set rather than inspecting an ambient environment:

```bash
uv lock --check
uv export --locked --all-packages --no-emit-workspace --no-hashes \
  --format requirements-txt > /tmp/requirements.scan.txt
uvx pip-audit==2.10.1 --requirement /tmp/requirements.scan.txt --desc on
uvx pip-audit==2.10.1 --requirement /tmp/requirements.scan.txt \
  --format json --output /tmp/pip-audit.json
```

`--no-emit-workspace` avoids treating workspace members as third-party packages; include development/optional groups only when they are deployed or exposed in CI. `--no-hashes` is for the scanner export, not a replacement for `uv sync --locked` hash checks.

Use OSV-Scanner `v2.7.0` for the lockfile and other supported ecosystems; pin its verified release binary and checksum in the toolchain:

```bash
osv-scanner scan source -L uv.lock
osv-scanner scan source -r . --format sarif --output /tmp/osv.sarif
```

Keep executable versions in the project lock or immutable CI image; do not use a mutable tool tag.

## Triage and ignores

| Situation | Action |
|---|---|
| Patch/minor fix exists | Upgrade the affected package minimally, regenerate lock, run tests |
| Major upgrade required | Create a reviewed change and track compatibility work |
| No fix or unreachable code | Assess exposure, mitigate, and use a narrow ignore with owner/reason/expiry |
| Dev-only dependency | Lower priority, but address if the build environment is exposed |
| Large backlog | Gate on new high/critical findings with fixes; schedule full rescans |

Do not leave permanent suppressions. Reject expired exceptions in CI.

## CI boundary

Run on pull requests with a validator identity that has no publish permission; run a scheduled full scan so advisories discovered after the commit are caught. Start with advisory output only when a real backlog exists, and record the blocking threshold and transition condition. Cloud Build or another CI system should cache dependency downloads without exposing long-lived keys.

## Other ecosystems

Use each ecosystem's lockfile-native scanner where applicable (`npm audit`, `govulncheck`, `cargo audit`, or Bundler audit). Do not mix first-party source SAST, image scanning, SBOM generation, or incident response into this dependency workflow.