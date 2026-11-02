---
description: "Manage Junie agents — inventory, docs, tune, steer, skills, workflow, sadkitti"
allowPromptArgument: true
---

EXECUTE IMMEDIATELY — one shell call. No planning, repo exploration or guideline loading.

```bash
python3 ~/.junie/custom/scripts/agentmgr/agentmgr.py $prompt
```

- Bare `/agentmgr` → script defaults to `status`. Pass `$prompt` through **unchanged** as argv.
- If the script exits 2 and stderr has `not found` plus `hint:`, retry with the suggested name or run the hinted `... list`; for a parse/usage error (e.g. natural-language input), run `... agentmgr.py <subcmd> -h`, map the request onto real flags using the table below, echo the resolved command, run once more. Never add `--write`/`--force` unless the user typed them.
- Summarize stdout in chat; bulky output → `/tmp/agentmgr-*.md`. Never print secrets. No git commit.

**Intent → argv**

| User wants | argv |
|------------|------|
| health check of the agent setup | `test` |
| overview / what is installed | `status` · `inventory` · `paths` |
| read a guideline doc | `docs show agents --format toc` (`docs list` for names) |
| why is setting X what it is | `config get X` (`config show --which settings`) |
| tokens / cost / tool use of the last session | `workflow audit latest` (`--mermaid` for a graph) |
| check a skill or all skills | `skills validate NAME` · `skills list` |
| check the slash commands | `commands lint --examples` |
| tuning advice | `tune show --recommend` → apply with `tune set KEY VALUE --write` |
| change a setting | `config set KEY VALUE --write` (file inferred from KEY; `--which` to override) |
| set reasoning effort for a model | `tune effort MODEL low --write` |
| find a skill by keyword | `skills list -q WORD` |
| MCP servers configured | `mcp` |
| available / configured models | `models` |
| steering templates | `steer templates` |

**Preconditions / side effects**

- Reads `~/.junie/` (override with `--junie-home PATH`). `config set` / `tune set|effort` are **dry-run** unless `--write`; on write, a timestamped backup goes to `.agentmgr-backups/` next to the edited file (`<file dir>/.agentmgr-backups/`) unless `--no-backup`.
- Without `--which`, `config set` and `tune set` pick the file from KEY: `model`, `modelForLaunch`, `braveMode`, `subagentsMode`, `ecoMode`, `eventDensityMode`, `diffViewMode`, `provider` → `settings.json`; any other key → `config.json`.
- Global flags `--json`, `--no-color`, `--color`, `--junie-home PATH` work before or after the subcommand (`--json status` = `status --json`).
- Exit codes: `0` ok · `1` a check or operation failed (e.g. `test`/`lint`/`validate` found problems, `workflow audit` cannot resolve its events file, or a `sadkitti graph` renderer fails) · `2` usage or resolution error (missing docs/skills/commands names, config keys and steer templates print a `hint:` on stderr and nothing on stdout).
- `steer scaffold` prints unless `--write`; `sadkitti graph --png/--svg` needs the external renderer installed.

**Next steps**

- `test` or `sadkitti lint` failures → fix the referenced doc path, rerun `test`.
- `commands lint --examples` failure → fix the example or the script's argparse, rerun.

Examples (each line is valid argv after `/agentmgr`):

```text
status
docs show agents --format toc
skills validate dev-project-todo-implement
tune show --recommend
workflow audit latest --mermaid
commands lint --examples
status --json
config get token-budget
tune effort MODEL low
```
