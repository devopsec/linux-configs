# Claude Specifics for Sec Python Dependency Scan

## Operating notes

- Follow SAD KITTI and consult only the dependency scanning/config sections required.
- Use the lockfile, redact report data, and preserve owner/reason/expiry for exceptions.
- Do not make major dependency upgrades or CI gates blocking without reviewed approval.
