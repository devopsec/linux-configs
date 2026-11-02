# Junie CLI Specifics for Sec Code Semgrep Scan

## Operating notes

- Execute SAD KITTI config selection; use OpenGrep by default and CodeQL only when the scope warrants it.
- Pin rules/engines, verify the base commit, and keep SARIF private.
- No commits; do not weaken a baseline or make a gate blocking without agreement.
