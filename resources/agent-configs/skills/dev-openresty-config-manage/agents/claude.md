# Claude Specifics for Dev Openresty Config Manage

## Context & Tuning
- Verify API availability per phase before writing Lua; do not assume cosockets work everywhere, and remember `return`/`rewrite` run before `access_by_lua*`.
- Prefer non-blocking `lua-resty-*` libraries and `ngx.timer.at` for background work.
- Treat LuaJIT performance claims as unverified until checked against the NYI table (`references/luajit-performance.md`).

## Instructions Overrides
- Ask before production reloads.
- Never reveal secrets handled by Lua code.
