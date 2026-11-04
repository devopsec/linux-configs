---
description: "Manage coding-agent session history (Junie CLI, Claude Code) — list/filter, mine skills/commands, delete safely"
allowPromptArgument: true
argument-hint: "[list|show|mine|choose|delete|stats|patterns] [args...]"
---

EXECUTE IMMEDIATELY — one shell call. No planning, repo exploration or guideline loading.

```bash
python3 {{agent_home}}/custom/scripts/histmgr/histmgr.py --agent {{agent}} {{args}}
```

- Bare `/histmgr` → script defaults to `mine --limit 20 --no-interactive` over this agent's history. Pass the arguments through **unchanged** as argv.
- Target agent: `--agent {{agent}}` (this agent) is already set; a user-supplied `--agent junie|claude` in the arguments wins (last one counts), e.g. to mine the other agent's sessions.
- If the script exits 2 (usage error, e.g. natural-language input): run `... histmgr.py <subcmd> -h`, map the request onto real flags using the table below, echo the resolved command, run once more. Never guess destructive flags (`--yes`, `--force-current`).
- Summarize stdout in chat; never dump full transcripts; bulky output → `/tmp/histmgr-*.md`. No git commit.

**Intent → argv**

| User wants | argv |
|------------|------|
| recent sessions for project X | `list -p X -n 20` |
| sessions matching text / date range | `list -q REGEX --since YYYY-MM-DD --until YYYY-MM-DD` |
| what can I turn into a skill/command | `mine --exclude-existing` (narrow: `--tag kamailio`) |
| the other agent's history | `--agent junie list -n 20` · `--agent claude mine` |
| details / transcript of one session | `show SESSION_ID --transcript --max-chars 8000` |
| free disk / prune old sessions | `delete --dry-run --until YYYY-MM-DD` → after explicit OK: same + `--yes` |
| usage statistics | `stats` (or `stats --tag TAG`) |
| which patterns does `mine` detect | `patterns` |

**Preconditions / side effects**

- Junie: reads `~/.junie/sessions/<id>/` + `index.jsonl`. Claude Code: reads `~/.claude/projects/<cwd>/<id>.jsonl` (titles from `ai-title` records, text from user/assistant messages). Override the home with `--home PATH`.
- Only `delete` writes. Junie: removes session dirs + `index.jsonl` rows. Claude Code: removes `<id>.jsonl`, its `<id>/` sidecar, `file-history/<id>` and `session-env/<id>`; project `memory/` is never touched. Live sessions (this one, and Claude Code processes still running) are protected unless `--force-current`.
- `--since/--until` are `YYYY-MM-DD`; `-p` is a substring of the project dir; `-q` is a regex.

**Next steps**

- After `mine`: offer `choose --ids ID[,ID] --as skill|command --write /tmp/histmgr-choice.json`, then author via skill `dev-agents-skill-create`.
- After `delete --dry-run`: show the list, wait for OK, then rerun with `--yes`.

Examples (each line is valid argv after `/histmgr`):

```text
list --project linux-configs --limit 30
mine --tag kamailio --exclude-existing
show session-abc123 --transcript --max-chars 8000
delete --dry-run --until 2025-01-01
stats
--agent junie list --limit 10
```
