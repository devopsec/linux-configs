# Junie CLI Specifics for Sec Git Secrets Scan

## Operating notes

- Execute the configured Gitleaks scan with redaction and the requested Git range.
- Never reveal raw report findings; route real credentials to the appropriate rotation owner.
- No commits; coordinate any Git history rewrite with repository maintainers.
