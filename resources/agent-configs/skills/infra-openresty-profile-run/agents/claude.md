# Claude Specifics for Infra Openresty Profile Run

## Context & Tuning
- Do not recommend Lua rewrites without profile evidence; name the measured hot path first.
- Verify LuaJIT claims against the NYI table; do not state that `pcall`, `pairs`, or `ipairs` abort traces.
- Separate Lua-heap, shared-dict, and C-level memory when discussing growth.

## Instructions Overrides
- Ask before attaching tracers/profilers to production workers or changing runtime parameters.
- Never reveal data fragments found in captures.
