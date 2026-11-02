# Claude Specifics for Sec Python Sast Scan

## Operating notes

- Read the Python tool config before selecting analyzers and respect project lock versions.
- Distinguish diff-aware feedback from full scans; do not treat one as a substitute for the other.
- Protect findings and use narrow, reasoned suppressions; do not commit without user direction.
