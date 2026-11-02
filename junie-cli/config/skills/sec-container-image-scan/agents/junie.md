# Junie CLI Specifics for Sec Container Image Scan

## Operating notes

- Read the container scan config and pin scanner/DB policy before scanning.
- Scan the immutable deployed digest, redact reports, and keep exceptions owned and expiring.
- No commits; request approval before changing registry policy or deployment gates.
