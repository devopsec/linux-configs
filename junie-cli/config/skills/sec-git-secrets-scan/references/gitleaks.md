# Gitleaks

Gitleaks `v8.30.1` was the latest release page version checked on `2026-10-28`. Pin its binary/container to that exact release or immutable digest and verify checksums/signature before use.

## Select coverage

Use a range for a PR, staged checks for pre-commit, directory scanning for a non-Git tree, and full history for repository exposure review:

```bash
gitleaks git --redact --log-opts="<base-ref>..<head-ref>" .
gitleaks git --redact --report-format sarif \
  --report-path /tmp/gitleaks.sarif .
gitleaks dir --redact <directory>
gitleaks git --staged --redact .
```

Always enable redaction and store reports privately. A historical scan should use the correct repository and refs; shallow clones can miss prior exposure.

## Configuration

Extend the default rules and add narrow organization-specific patterns. Allowlist only known fixtures or encrypted test material; broad path/regex exclusions can hide real credentials. Prefer one documented inline allow marker for a confirmed false positive.

```toml
[extend]
useDefault = true

[[rules]]
id = "example-token-pattern"
description = "Placeholder pattern for an organization-specific token"
regex = '''<non-secret-pattern>'''
keywords = ["<non-secret-keyword>"]

[allowlist]
description = "Reviewed non-production fixtures only"
paths = ['''tests/fixtures/''']
```

## Incident handling

A true finding is a possible compromise. Revoke/rotate the credential first, then remove it from current files and coordinate any Git history rewrite with repository owners. See the provider-specific skills for rotation; do not include raw findings in the report.