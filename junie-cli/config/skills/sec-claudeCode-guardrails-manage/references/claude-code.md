# Claude Code guardrails

Upstream relied on `CLAUDE.md` "NEVER …" lists and an invented `.agent-permissions.yaml`; neither is enforced. This file uses the enforced mechanisms (settings permissions, modes, hooks, sandbox, managed settings). Based on Claude Code docs (`docs.claude.com/en/docs/claude-code/settings`, `/permissions`, Oct 2026) — key names evolve, verify with `/status`, `/permissions`, and the settings reference.

## Contents

1. Files and precedence
2. Permission rules
3. Modes
4. Hooks as enforcement
5. Sandbox and network
6. Headless / CI
7. Baseline `.claude/settings.json`
8. Gotchas

## 1. Files and precedence (highest first)

1. **Managed** — `managed-settings.json` (system dir), MDM policy, or server-managed from the admin console. Cannot be overridden.
2. **CLI flags / `--settings`** for the session.
3. **Project local** — `.claude/settings.local.json` (personal, git-excluded; "Yes, don't ask again" writes `allow` rules here).
4. **Project shared** — `.claude/settings.json` (commit it: team permissions + hooks).
5. **User** — `~/.claude/settings.json`.

`CLAUDE.md` is context, not policy. Check effective sources with `/status` (`Setting sources`) and `claude doctor`.

## 2. Permission rules

```json
{
  "permissions": {
    "allow": ["Bash(uv run pytest:*)", "Bash(uv run ruff check:*)", "Bash(git status)", "Bash(git diff:*)"],
    "ask":   ["Bash(git push:*)", "Bash(gcloud:*)", "Bash(tofu:*)", "WebFetch"],
    "deny":  ["Read(./.env)", "Read(./.env.*)", "Read(./**/*.pem)", "Read(./**/*.key)", "Read(./secrets/**)",
              "Bash(curl:*)", "Bash(wget:*)", "Bash(sudo:*)", "Bash(npm publish:*)"]
  }
}
```

- Evaluation: **deny > ask > allow**; an `allow` in local settings does not outrank an `ask`/`deny` from project or managed settings.
- Tool specifiers: `Bash(<cmd prefix>:*)`, `Read(<gitignore-style path>)`, `Edit(<path>)`, `WebFetch(domain:<host>)`, MCP tools as `mcp__<server>__<tool>` (or `mcp__<server>` for all).
- `Read`/`Edit` denies cover Claude's file tools; a shell `cat .env` is a `Bash` call — deny broad interpreters/fetchers or use the sandbox to close that path.
- `additionalDirectories` widens file access beyond the project — keep empty unless needed.

## 3. Modes (`permissions.defaultMode`)

`default` (ask per rules) · `acceptEdits` (auto-accept file edits) · `plan` (read-only planning) · `bypassPermissions` (no prompts). Newer versions add an `auto` mode — check your version's reference.

- `auto` and `bypassPermissions` cannot be set from project or local settings (user/managed only) — a cloned repo can't escalate itself.
- Org policy: set `"disableBypassPermissionsMode": "disable"` under `permissions` in managed settings.
- `--dangerously-skip-permissions` only in a disposable container/VM without real credentials.

## 4. Hooks as enforcement

`PreToolUse` hooks run before a tool call; exit code 2 blocks it and feeds stderr back to Claude.

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-secrets.sh" } ] }
    ]
  }
}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/block-secrets.sh — reads the tool call JSON on stdin
set -euo pipefail
cmd="$(jq -r '.tool_input.command // empty')"
if grep -Eq '(\.env\b|\.pem\b|id_rsa|id_ed25519|secure_credentials|gcloud .*print-access-token)' <<<"${cmd}"; then
  echo "Blocked by guardrail: command touches secret material" >&2
  exit 2
fi
```

Hooks are code executed with your privileges: review hook scripts in PRs like any other code; hooks from untrusted repos are an attack vector (Claude Code asks to trust a new project's settings — read them first).

## 5. Sandbox and network

Claude Code ships an OS sandbox for Bash (`/sandbox`; settings under the `sandbox` key — e.g. `enabled`, filesystem and network allow lists; verify current key names in the settings reference). Same runtime family as Junie's `srt`. Use it with an allowlisted domain set for untrusted repos; combine with permission denies (sandbox covers Bash, permissions cover native tools).

## 6. Headless / CI

`claude -p "<task>" --output-format stream-json --verbose --allowedTools "<list>" [--disallowedTools "<list>"]`. In Cloud Build: API key from Secret Manager, explicit `--allowedTools`, no push credentials, results to a PR. `--disable-slash-commands` disables skills/commands (useful for baselines, see `dev-agents-evals-create`).

## 7. Baseline `.claude/settings.json` (commit)

- `allow`: project test/lint/format commands, read-only git.
- `ask`: `git push`, cloud CLIs, IaC, package installs, `WebFetch`.
- `deny`: secret paths, `curl`/`wget`/`ssh`/`scp`, `sudo`, publish commands.
- `hooks.PreToolUse`: secret-pattern blocker (above).
- No `defaultMode` escalation; MCP servers listed explicitly (avoid `enableAllProjectMcpServers: true`).

## 8. Gotchas

- Local "don't ask again" approvals accumulate in `.claude/settings.local.json` — review periodically.
- Settings reload live; a malicious edit to settings by the agent itself is a risk — `deny` `Edit(./.claude/**)` for untrusted tasks.
- Command-prefix rules can be bypassed by wrappers (`env X=1 curl …`, `bash -c`) — prefer deny-by-default + sandbox over long allow lists.
