---
description: "Manage coding agents (Junie CLI, Claude Code) — inventory, docs, config, skills, commands, steer, sadkitti; tune/workflow for Junie"
allowPromptArgument: true
argument-hint: "[subcommand] [args...]"
---

EXECUTE IMMEDIATELY — one shell call. No planning, repo exploration or guideline loading.

```bash
python3 {{agent_home}}/custom/scripts/agentmgr/agentmgr.py --agent {{agent}} {{args}}
```

- Bare `/agentmgr` → script defaults to `status` for this agent. Pass the arguments through **unchanged** as argv.
- Target agent: `--agent {{agent}}` (this agent) is already set; a user-supplied `--agent junie|claude` in the arguments wins (last one counts), e.g. to inspect the other agent's home.
- If the script exits 2 and stderr has `not found` plus `hint:`, retry with the suggested name or run the hinted `... list`; for a parse/usage error (e.g. natural-language input), run `... agentmgr.py <subcmd> -h`, map the request onto real flags using the table below, echo the resolved command, run once more. Exit 2 with `Junie-specific` means the subcommand needs `--agent junie`. Never add `--write`/`--force` unless the user typed them.
- Summarize stdout in chat; bulky output → `/tmp/agentmgr-*.md`. Never print secrets. No git commit.

**Intent → argv**

| User wants | argv |
|------------|------|
| health check of the agent setup | `test` |
| overview / what is installed | `status` · `inventory` · `paths` |
| the other agent's setup | `--agent junie status` · `--agent claude status` |
| read a guideline doc | `docs show agents --format toc` (`docs list` for names) |
| why is setting X what it is | `config get X` (`config show --which settings`) |
| change a setting | `config set KEY VALUE --write` (Junie: file inferred from KEY; Claude Code: `settings.json`) |
| check a skill or all skills | `skills validate NAME` · `skills list` |
| find a skill by keyword | `skills list -q WORD` |
| check the slash commands | `commands lint --examples` |
| MCP servers configured | `mcp` (env/header values are redacted for Claude Code) |
| Junie: tokens / cost / tool use of the last session | `--agent junie workflow audit latest` (`--mermaid` for a graph) |
| Junie: tuning advice / reasoning effort | `--agent junie tune show --recommend` · `--agent junie tune effort MODEL low --write` |
| Junie: available / configured models | `--agent junie models` |
| steering templates | `steer templates` |

**Preconditions / side effects**

- Reads `{{agent_home}}/` (override with `--home PATH`; Junie also `--junie-home PATH`). Claude Code MCP servers come from `~/.claude.json` (`mcpServers` only). `config set` / `tune set|effort` are **dry-run** unless `--write`; on write, a timestamped backup goes to `<file dir>/.agentmgr-backups/` unless `--no-backup`.
- Junie: without `--which`, `config set` and `tune set` pick the file from KEY: `model`, `modelForLaunch`, `braveMode`, `subagentsMode`, `ecoMode`, `eventDensityMode`, `diffViewMode`, `provider` → `settings.json`; any other key → `config.json`. Claude Code has only `settings.json`; credential helpers and `autoMode` need `--force`.
- `tune`, `workflow` and `models` are Junie-specific and exit 2 for Claude Code.
- Global flags `--agent`, `--home`, `--json`, `--no-color`, `--color` work before or after the subcommand (`--json status` = `status --json`).
- Exit codes: `0` ok · `1` a check or operation failed (e.g. `test`/`lint`/`validate` found problems, `workflow audit` cannot resolve its events file, or a `sadkitti graph` renderer fails) · `2` usage or resolution error (unknown agent, Junie-only subcommand, missing docs/skills/commands names, config keys and steer templates print a `hint:` on stderr and nothing on stdout).
- `steer scaffold` prints unless `--write`; `sadkitti graph --png/--svg` needs the external renderer installed.

**Next steps**

- `test` or `sadkitti lint` failures → fix the referenced doc path, rerun `test`.
- `commands lint --examples` failure → fix the example or the script's argparse, rerun.

Examples (each line is valid argv after `/agentmgr`):

```text
status
docs show agents --format toc
skills validate dev-project-todo-implement
commands lint --examples
status --json
config get model
--agent junie tune show --recommend
--agent junie workflow audit latest --mermaid
--agent claude mcp
```
