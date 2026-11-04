---
name: "dev-kamailio-platform-manage"
description: "Manage Kamailio and related SIP platform work: modules, modparam, routing scripts, pike/rate-limiting, TLS/mTLS paths, dSIPRouter integration, RPC/cfg.get hot-reload, install/configure scripts, and Kamailio build issues. Use when tasks mention Kamailio, kamcmd, kamctl, dsiprouter, SIP routing, pike, htable, dispatcher, or platform SIP config."
---

# Kamailio platform manage

Domain skill for Kamailio-centric platforms (upstream Kamailio trees, dSIPRouter, custom carrier platforms).

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves routing scripts or kamailio.cfg fragments
  REFERENCE "references/config-and-routing.md"
IF task involves modules, modparam, or hot-reload / RPC
  REFERENCE "references/modules-modparam-rpc.md"
IF task involves pike, rate limit, ddos, or htable counters
  REFERENCE "references/rate-limiting.md"
IF task involves TLS, mTLS, certificates, or WSS
  REFERENCE "references/tls-and-transport.md"
IF task involves dSIPRouter or GUI-backed settings
  REFERENCE "references/dsiprouter-integration.md"
IF task involves build, CMake, modules Makefile, or install packaging
  REFERENCE "references/build-install.md"
CACHE loaded reference summaries for the rest of this task
```

Do **not** preload every reference. Jump only for the active branch.

## Workflow

1. **Identify tree & role**
   - Upstream Kamailio source vs packaged install vs platform overlay (e.g. `platforms/*/kamailio`).
   - Runtime vs build-time change.

2. **Capture runtime context** (when touching live behavior)
   - Config path (`kamailio.cfg`, `kamailio-*.cfg`, includes).
   - Module set and how params are set (`modparam`, DB, GUI, RPC).
   - Whether changes must be hot-reloadable without full restart.

3. **Implement with platform conventions**
   - Match existing cfg style (route names, indentation, `#!ifdef` patterns).
   - Prefer runtime-tunable params when the platform already exposes them (GUI/RPC).
   - Keep listen/TLS path changes consistent across install + configure + runtime scripts.

4. **Validate**
   - `kamailio -c -f <cfg>` config check when available.
   - Targeted module tests or dry-run scripts the repo already uses.
   - For rate-limit: confirm pike/htable windows and error responses match docs.

5. **Docs**
   - Update module/platform notes if operator-facing behavior changes.
   - Record new `modparam` names and RPC keys.

## Safety

- Never commit private certs/keys; only paths and file modes.
- Do not expose production dispatcher lists or carrier credentials in chat.
- Full restart only when hot-reload cannot apply; say so explicitly.
- Build fixes: prefer project CMake/Make over deleting random generated files (see also `dev-project-fixIssue-fromLogs`).

## Related skills

- Log triage spanning non-SIP stacks → `dev-project-fixIssue-fromLogs`
- Bash install/configure scripts → `dev-bash-script-review` / `dev-bash-utility-create`
- Spec-driven SIP/HTTP features → `dev-project-spec-implement`

## References

| File | When |
|------|------|
| [references/config-and-routing.md](references/config-and-routing.md) | cfg, routes, branching |
| [references/modules-modparam-rpc.md](references/modules-modparam-rpc.md) | modules, modparam, RPC |
| [references/rate-limiting.md](references/rate-limiting.md) | pike / rate_limiting |
| [references/tls-and-transport.md](references/tls-and-transport.md) | TLS/mTLS/WSS |
| [references/dsiprouter-integration.md](references/dsiprouter-integration.md) | dSIPRouter |
| [references/build-install.md](references/build-install.md) | build & packaging |
