# Junie CLI Specifics for Dev Openresty Config Manage

## Context & Tuning
- Resolve the target phase first, then load only the matching sections of `references/openresty-api.md` and `references/examples.md`.
- Run `openresty -t`, then exercise the Lua path with real requests (curl); config checks do not catch Lua runtime errors. A container (`openresty/openresty:alpine`, or `alpine-fat` for `resty`) is a safe way to run them; use fully qualified image names with podman.
- Remember workers run unprivileged: mounted Lua and key files must be readable by that user.

## Instructions Overrides
- No commits; require approval before production reloads.
- Never log or print tokens, auth headers, or secrets.
- Scratch projects and test output go in `/tmp`, never in the repo.
