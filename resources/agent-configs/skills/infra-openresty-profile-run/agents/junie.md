# Junie CLI Specifics for Infra Openresty Profile Run

## Context & Tuning
- Start with in-process stats and cheap OS checks; ask before attaching `perf`, SystemTap, or `strace` to production workers.
- Reproduce on a container rig (`openresty/openresty:alpine-fat` provides `resty`/`opm`/`luarocks`; use fully qualified names with podman) and keep captures in `/tmp`.
- Report flame-graph hot paths with percentages and function names.

## Instructions Overrides
- No commits; remove temporary debug endpoints/logging after the investigation.
- Do not change GC parameters, shared dict sizes, or `lua_code_cache` on production without approval.
