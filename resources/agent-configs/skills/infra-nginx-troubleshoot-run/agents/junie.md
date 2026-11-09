# Junie CLI Specifics for Infra Nginx Troubleshoot Run

## Context & Tuning
- Start read-only: logs, `nginx -T`, `ss`, `/proc`, counters. Summarize by message pattern before reading raw lines.
- Reproduce suspected causes in a container lab (see the runbook) before proposing a production change.
- Keep captures and logs in `/tmp`; redact tokens, cookies, keys, and client IPs when quoting.

## Instructions Overrides
- No commits; no reloads, restarts, sysctl changes, setsebool, or packet captures without approval.
- Present each fix with a verification command and a rollback.
