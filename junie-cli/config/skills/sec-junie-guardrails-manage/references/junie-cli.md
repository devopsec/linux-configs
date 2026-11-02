# Junie CLI guardrails

Local addition (not upstream). CLI behavior checked 2026-10-28 against the official Junie CLI reference and environment-variable docs; configuration schemas can evolve, so re-check the named reference before proposing a schema change.

## Contents

1. Config files and what they control
2. Inspecting safely
3. allowlist.json
4. Sandbox mode and sandbox.json
5. Headless / CI
6. Recommended baseline
7. Gotchas

## 1. Config files

| File (global, `~/.junie/`) | Controls | Notes |
|---|---|---|
| `allowlist.json` | which sensitive actions run without asking | global only — a project `.junie/allowlist.json` is **not** read (feature request JUNIE-2496) |
| `sandbox.json` | OS sandbox policy for agent commands + native edit tools | global only; project-local copy ignored with a warning, so a cloned repo cannot widen it |
| `settings.json` | UI/session preferences such as `stepsLimit` and model choice | user interface/session settings; not an enforcement boundary |
| `secure_credentials.json`, `config.json` | auth / provider config | **never open or print**; out of scope for guardrail reviews beyond "exists, mode 0600" |

Project-scoped guidance lives in `AGENTS.md` / `.junie/` guidelines and skills — advisory, not enforcement.

## 2. Inspecting safely

Dump shape (keys, types, list lengths) and enum-like fields only; never values of free-form strings:

```bash
python3 - <<'EOF'
import json, pathlib
def shape(v):
    if isinstance(v, dict): return {k: shape(x) for k, x in v.items()}
    if isinstance(v, list): return [f"{len(v)} x {type(v[0]).__name__ if v else '-'}"]
    return type(v).__name__
for name in ("allowlist.json", "sandbox.json", "settings.json"):
    p = pathlib.Path.home() / ".junie" / name
    print(name, json.dumps(shape(json.loads(p.read_text())), indent=1) if p.exists() else "missing")
EOF
```

Safe-to-print fields for a posture report: `defaultBehavior`, `allowReadonlyCommands`, the set of `action` values, rule *counts* per group, `network.unrestricted`, and domain list lengths. Prefixes/paths may be printed when the user asks; they are not secrets but can reveal project names.

## 3. allowlist.json

```json
{
  "defaultBehavior": "ask",
  "allowReadonlyCommands": true,
  "rules": {
    "executables": { "rules": [
      { "pattern": "git push*", "action": "ask" },
      { "prefix": "git", "action": "allow" },
      { "pattern": "uv run pytest*", "action": "allow" },
      { "pattern": "uv run ruff *", "action": "allow" }
    ]},
    "fileEditing":        { "rules": [ { "prefix": "src/", "action": "allow" } ] },
    "readOutsideProject": { "rules": [] },
    "readSecretFile":     { "rules": [] },
    "mcpTools":           { "rules": [ { "prefix": "<server>_get", "action": "allow" } ] }
  }
}
```

- Groups: `executables` (terminal commands), `fileEditing` (edits outside the project and build scripts anywhere), `readOutsideProject`, `readSecretFile`, `mcpTools`.
- Rule = `prefix` (literal start) **or** `pattern` (glob: `*` no `/`, `**` any, `?` one char) + `action` `allow|ask`. No `deny` action — anything not allowed asks.
- **First match wins**, top to bottom: put narrow `ask` rules above broad `allow` prefixes (e.g. `git push*` ask above `git` allow).
- Chained (`&&`, `;`, `|`) and nested (`$(…)`, backticks, `<(…)`) commands: every part must be allowed. Multi-line commands always ask.
- Keep `readSecretFile` empty. Avoid `prefix` rules for interpreters/launchers (`python`, `bash`, `node`, `npx`, `uv run` without a pattern, `make`) — they allow arbitrary code.
- "Always allow" on a file-open prompt is stored under `fileEditing` (grants edit, not just read) — review and prune after interactive sessions.

## 4. Sandbox mode and sandbox.json

- Enable per session: `junie --sandbox` or `/sandbox` (macOS/Linux; Linux needs `bubblewrap`, `socat`, `ripgrep`; Ubuntu AppArmor may need the bundled setup script — inspect it, run with `--check` first).
- Restricts terminal commands **and** native edit tools to: project dir, its git dir, temp dirs, curated tool caches. Startup self-test verifies a forbidden write is blocked.
- `sandbox.json` keys: `allowWrite`, `denyWrite`, `allowRead` (re-allow single paths inside a denied dir), `denyRead`, `ignoreViolations`, `network.{unrestricted, allowedDomains, deniedDomains, allowUnixSockets, allowAllUnixSockets, allowSystemCertificateValidation, allowLocalBinding}`.
- Path forms: `${PROJECT_DIR}`, `${TMPDIR}`, `${GIT_DIR}`, `${GIT_COMMON_DIR}`, `${SSH_AUTH_SOCK}`, leading `~`, else literal absolute paths — **no globs**.
- Network filter: `"unrestricted": false` + `allowedDomains` (`example.com` / `*.example.com`, no scheme/port/path). Derive a narrow allowlist from the approved model provider, package registries, and required service APIs; do not copy another project's hosts or allow broad cloud wildcards by default.
- Editing `sandbox.json`: shell commands cannot (it is on deny-write); a native edit tool naming exactly that file + a fresh "Allow once" approval is required each time — elevated modes and saved approvals cannot bypass it.
- Do not add private keys to `allowRead`; for git over SSH rely on the agent socket (`${SSH_AUTH_SOCK}`), else use HTTPS remotes.
- Violations show above the prompt and in the transcript (`/sandbox` for the session breakdown).

## 5. Headless / CI

`junie --auth="${JUNIE_API_KEY}" "<task>"` (and `--review` for commit review); options/env vars per `junie.jetbrains.com/docs/parameters.html`. Install via a package manager or a pinned release with checksum verification — never pipe a downloaded install script into a shell. In Cloud Build: API key from Secret Manager (`availableSecrets`), run in an ephemeral container, no push credentials in the build step, agent output goes to a PR for human review.

## 6. Recommended baseline (developer laptop / VM)

```
defaultBehavior: ask
allowReadonlyCommands: true
executables: ask-rules for push/publish/install/mutating cloud CLIs first, then allow project test/lint/format patterns
fileEditing: project source dirs only; no home/dotfile prefixes
readOutsideProject: only specific read-only doc paths if needed
readSecretFile: empty
mcpTools: allow read-only tool name prefixes only
sandbox: on for unfamiliar repos; network.unrestricted=false with a short allowedDomains list
```

## 7. Gotchas

- Saved approvals accumulate silently: diff `allowlist.json` periodically (it is plain JSON; keep a private backup before edits).
- `allowReadonlyCommands: true` relies on Junie's read-only classification; a "read-only" command that prints a secret file is still exfiltration if output reaches an untrusted channel.
- Sandbox protects the filesystem/network for agent commands; it does not stop the model from echoing secrets it already read into the chat or a commit.
