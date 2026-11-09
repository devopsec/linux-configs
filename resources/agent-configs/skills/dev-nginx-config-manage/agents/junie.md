# Junie CLI Specifics for Dev Nginx Config Manage

## Context & Tuning
- Load `references/nginx-gotchas.md` first; load recipes, tuning, keyval, and testing references only when the task needs them.
- Validate with `nginx -t` (project's nginx image tag when available) before proposing a reload; list the curl checks that prove each change.
- When a snippet comes from a blog or gist, run the verification routine in `references/sources.md` before using it.

## Instructions Overrides
- No commits; require approval before production reloads or TLS/access-policy changes.
- Redact private keys, certificates, htpasswd contents, and secret-bearing upstream URLs.
- Scratch configs and test output go in `/tmp`, never in the repo.
