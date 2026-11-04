# Global commands catalog (`~/.junie/commands/`, `~/.claude/commands/`)

User-level slash commands shared by Junie CLI and Claude Code. Project commands may also live in `.junie/commands/` or
`.claude/commands/`. `<agent>` below means `junie` or `claude`.

| Command | Script / target | Purpose |
|---------|-----------------|--------|
| **`/histmgr`** | `~/.<agent>/custom/scripts/histmgr/histmgr.py` | Session history (Junie or Claude Code): `list`, `show`, `mine`, `choose`, `delete`, `stats`, `patterns` |
| **`/agentmgr`** | `~/.<agent>/custom/scripts/agentmgr/agentmgr.py` | Agent mgmt: `status`, `docs`, `skills`, `commands` (`lint --examples`), `config`, `steer`, `sadkitti`, `test`, `mcp`; Junie-only `tune`, `workflow`, `models` |
| **`/sectool`** | `~/.<agent>/custom/scripts/sectools/sectool.py` | Security tools: `audit` (live GCP), `review` (IaC), `remediate`, `refactor` (non-interactive by default) |
| **`/find-housing`** | `~/.<agent>/custom/scripts/find-housing/find_housing.py` | Craigslist apartment search (no LLM): `--city` (required unless in `~/.config/find_housing.cfg`), rent/bed/bath filters, `--query`, `--details`, `--format table\|json` |

**Direct (no agent) shims:** `~/.<agent>/custom/bin/{agentmgr,histmgr,sectool,find-housing}` (symlink onto `PATH` / `~/.local/bin` if desired). They resolve the script next to themselves, so either agent's copy works. Prefer these when you want zero-LLM latency.

**Target agent (`histmgr`, `agentmgr`):** `--agent junie|claude`, else `AGENT_TARGET`, else the agent that launched the process (Claude Code exports `CLAUDECODE`; Junie its session variables), else the only installed agent, else an interactive prompt when run standalone in a terminal; without a terminal the tools exit 2 asking for `--agent`. Inside an agent the command body already passes `--agent <that agent>`; a user `--agent` in the arguments wins. `--home PATH` overrides the selected agent's home. `sectool` and `find-housing` have no agent-specific state.

**`--check-args` (all scripts):** parse-only mode — prints the resolved argparse namespace as JSON, exits 0, touches no files/sessions/cloud and resolves no agent. `histmgr`/`agentmgr` take it as a global flag before the subcommand; `sectool --check-args <tool> [args]` forwards it to the tool. `agentmgr commands lint --examples` uses it to validate every example line in `~/.<agent>/commands/*.md`.

## Agent-agnostic command templates

The source files live in the linux-configs repo under `resources/agent-configs/commands/` and are **templates**: each agent's
`sync.sh` renders them into that agent's `commands/` dir. Use these placeholders instead of agent paths or argument syntax:

| Placeholder | Junie CLI | Claude Code |
|-------------|-----------|-------------|
| `{{agent_home}}` | `~/.junie` | `~/.claude` |
| `{{agent}}` | `junie` | `claude` |
| `{{args}}` | `$prompt` | `$ARGUMENTS` |

Keep both frontmatter keys: `allowPromptArgument: true` (Junie: optional free-form text) and `argument-hint` (Claude Code
completion hint); each agent ignores the other's key. Never write a literal dollar placeholder in a template — Junie
treats every `$name` other than `$prompt` as a **required** named argument.

## How Junie custom-command arguments work

Junie is **not** shell argv parsing and **not** Claude Code `$ARGUMENTS` (Claude Code substitutes `$ARGUMENTS` and `$1`…`$9`, all optional, and appends the text when neither appears). The `{{args}}` template placeholder renders to the right form for each agent.

| Mechanism | Frontmatter / body | Invocation | When it runs |
|-----------|-------------------|------------|--------------|
| Required named arg | Dollar-sign placeholder in body (e.g. `$file`) | `/explain file=src/main.kt` | Only after **all** named args are provided; Tab hints missing names |
| Optional free-form text | `allowPromptArgument: true` + optional `$prompt` in body | `/histmgr` or `/histmgr list --limit 10` | Bare command runs immediately; trailing text fills `$prompt` (or is appended as `User Input: ...` if `$prompt` is omitted) |
| Catch-all `ARGUMENTS` placeholder | **Do not use** | Tab shows `ARGUMENTS=` | Blocks bare run — this was the bug in early global commands |

### Fast CLI-wrapper pattern (recommended)

Keep the command body **small** (<~50 lines) and wire `{{args}}` straight into the script so the agent does one bash call on the happy path. Body shape (see `resources/agent-configs/commands/histmgr.md` as the reference):

- Frontmatter: `description` + `allowPromptArgument: true`
- Body line: `EXECUTE IMMEDIATELY — one shell call.`
- Body bash: `python3 {{agent_home}}/custom/scripts/<name>/<name>.py {{args}}` (add `--agent {{agent}}` when the script manages agent state)
- **Recovery rule:** only if the script exits 2 (argparse usage error, e.g. natural-language input) the agent runs `<script> <subcmd> -h`, maps the request onto real flags, echoes the resolved command and runs once more; destructive flags (`--yes`, `--write`, `--apply`) are never guessed.
- **Intent → argv** table (≤8 rows) so natural-language requests map onto real flags.
- **Preconditions / side effects** (cwd, credentials, files written) and **Next steps** (what to offer after the run).
- Trailing ```` ```text ```` block: one valid argv line per example — the **first** such block is what `agentmgr commands lint --examples` validates.

Rules:

1. YAML: `description` + `allowPromptArgument: true`.
2. Template bodies use **`{{args}}` only** for arguments (rendered to `$prompt` / `$ARGUMENTS`). Do **not** add `$HOME`, `$ARGS`, `$file`, etc. — in Junie every other `$name` becomes a **required** `name=value` arg and blocks bare `/cmd`.
3. Use `{{agent_home}}/...` for paths, never `~/.junie/...`, `~/.claude/...` or `$HOME/...`, inside command templates.
4. Script itself must default when argv is empty (bare `/cmd` → empty arguments).
5. For true zero-LLM runs, use the shim: `~/.<agent>/custom/bin/agentmgr status` (or on `PATH`).

**Authoring checklist for CLI-style commands**

1. Frontmatter: `description` + `allowPromptArgument: true`.
2. Body: **only** `{{args}}` as the argument placeholder (or none — trailing text becomes `User Input:` in Junie and is appended in Claude Code).
3. Document a **default** action for bare `/name` (implemented in the Python CLI).
4. Body contains the intent → argv table, preconditions/side effects, the exit-2 recovery rule and next-step hints.
5. Script supports `--check-args` (parse, print JSON namespace, exit 0, no side effects) and every example line passes `agentmgr commands lint --examples` (`failures: 0`).
6. Put non-trivial logic in `resources/agent-configs/custom/scripts/<name>/` (installed as `~/.<agent>/custom/scripts/<name>/`); mutating actions are non-interactive and need an explicit flag (`--yes`, `--write`, `--apply`), with `--dry-run` preview.
7. Add an optional `custom/bin/<name>` shim (link onto `PATH`) for direct execution; agent-aware tools must accept `--agent` and use `agent_target.resolve_agent`.

## `/histmgr`

**Command file:** `~/.<agent>/commands/histmgr.md` (template: `resources/agent-configs/commands/histmgr.md`)  
**Frontmatter:** `allowPromptArgument: true` + `argument-hint`; body `{{args}}`  
**Default (bare `/histmgr` or `histmgr`):** `mine --limit 20 --no-interactive`

```bash
python3 ~/.<agent>/custom/scripts/histmgr/histmgr.py <subcommand> [options]
# or: histmgr <subcommand> [options]
```

| Subcommand | Role |
|------------|------|
| `list` | Filter sessions (`--project`, `--query`, `--since`, `--until`, `--tag`, `--status`, `--min-kb`, `--limit`) |
| `show` | Metadata + optional transcript (`--transcript`, `--max-chars`) |
| `mine` | Rank reusable skill/command candidates; `--exclude-existing`, `--min-hits`, `--tag`, `--guidance`, `--no-interactive` |
| `choose` | Select candidates (`--ids`, `--as skill|command`, `--write`, `--guidance`) |
| `delete` | Remove sessions; always prefer `--dry-run` first; live session protected unless `--force-current` |
| `stats` | Project + pattern histograms (`--tag` supported) |
| `patterns` | Dump built-in mine regex rules |
| `--check-args` (global) | Parse-only; prints namespace JSON, no session access |

**Side effects:** only `delete` writes — Junie: session dirs + `index.jsonl` rows; Claude Code: `<id>.jsonl`, its `<id>/` sidecar, `file-history/<id>`, `session-env/<id>` (project `memory/` untouched). Typical flow: `mine --exclude-existing` → `choose --ids … --as skill|command --write /tmp/….json` → author the artifact.

**Examples**

```text
/histmgr
/histmgr list --project linux-configs --limit 30
histmgr --agent claude list -n 10
histmgr mine --tag kamailio --exclude-existing
/histmgr delete --dry-run --until 2025-01-01
histmgr --check-args list -p x -n 5
```

## `/agentmgr`

**Command file:** `~/.<agent>/commands/agentmgr.md` (template: `resources/agent-configs/commands/agentmgr.md`)  
**Frontmatter:** `allowPromptArgument: true` + `argument-hint`; body `{{args}}`  
**Default (bare `/agentmgr` or `agentmgr`):** `status`

```bash
python3 ~/.<agent>/custom/scripts/agentmgr/agentmgr.py <subcommand> [options]
# or: agentmgr <subcommand> [options]
```

| Subcommand | Role |
|------------|------|
| `status` / `paths` / `inventory` | Agent home overview, resolved paths, docs/skills/commands/models/mcp inventory |
| `docs` | Pretty-print agent docs (`show|list|tree|index`; formats `pretty|toc|outline|raw`) |
| `skills` | `list` / `show` / `validate` (wraps `validate.py`) |
| `commands` | `list` / `show` / `lint` custom slash commands (arg UX); `lint --examples` runs every ```` ```text ```` example through `<script> --check-args` and fails on drift |
| `config` | `show` / `get` / `set` for `config.json` + `settings.json` (Claude Code: `settings.json` only; set is dry-run unless `--write`) |
| `tune` | Junie only: tuning snapshot, recommendations, `effort`, convenience `set` |
| `steer` | Decision-routing templates, scan existing SAD KITTI blocks, scaffold steering docs |
| `workflow` | Junie only: audit session `events.jsonl` (tokens, tools, guideline interlock; `--mermaid`) |
| `sadkitti` | `scan` / `lint` / `graph` (text, mermaid, plantuml, optional png/svg/pandoc) |
| `test` | Combined sadkitti lint + skill sanity + optional workflow audit |
| `mcp` / `models` | List MCP servers (Claude Code: `~/.claude.json`, env/header values redacted) / Junie model configs |
| `--check-args` (global) | Parse-only; prints namespace JSON, no filesystem access |

**Examples**

```text
/agentmgr
/agentmgr docs show agents --format toc
agentmgr skills validate dev-project-todo-implement
/agentmgr workflow audit latest --mermaid
/agentmgr commands lint --examples
```

Migrated workflow test tools live under `~/.<agent>/custom/scripts/agentmgr/lib/`.

## `/sectool`

**Command file:** `~/.<agent>/commands/sectool.md` (template: `resources/agent-configs/commands/sectool.md`)  
**Frontmatter:** `allowPromptArgument: true` + `argument-hint`; body `{{args}}`  
**Default (bare `/sectool` or `sectool`):** list tools + usage; bare tool name (`sectool review`) → that tool's `--help`

```bash
python3 ~/.<agent>/custom/scripts/sectools/sectool.py [--check-args] <tool> [args]
# or: sectool <tool> [args]
```

**Preconditions:** run from the **IaC repo root** — `review` scans `./platforms/**/*.tf` (no path argument exists); `review`/`audit` write `.audits/<id>/gcp-<subsystem>.json` into cwd. `audit` runs `gcloud` against the active project: needs `gcloud auth` and **explicit user OK** before running (credentials rule in `general-guidelines.md`). `review` is offline.

| Tool | Flags | Notes |
|------|-------|-------|
| `audit` | `-p gcp` `-s iam compute network storage functions databases analytics` `-i AUDIT_ID` | Live GCP scan; findings `fail`/`pass` with `remediation` commands |
| `review` | same `-p` / `-s` / `-i` | Static IaC scan of `platforms/`; same JSON schema as `audit` |
| `remediate` | `[AUDIT_ID] -l --apply ID... --skip ID... --skip-all --dry-run` | Live-system follow-up to `audit` |
| `refactor` | same as `remediate` | IaC follow-up to `review`/`audit` (adds file location) |

**Non-interactive contract (`remediate`/`refactor`):** `--help` always works (no `.audits/` needed). Without a TTY (Junie) and without action flags the tool **lists** pending finding IDs read-only and exits 0. Status is only changed by `--apply ID...` (then the agent performs the listed fix), `--skip ID...` or `--skip-all`; `--dry-run` previews; unknown ID → exit 1, nothing written. The interactive `[a]pply/[s]kip/[d]iscuss` loop only runs on a real terminal. `AUDIT_ID` defaults to the newest audit when the script is called directly; via the dispatcher pass it explicitly (bare tool name shows help).

**Examples**

```text
/sectool
/sectool review -s iam network
sectool refactor -l
/sectool refactor 20260101-000000-review
/sectool remediate 20260101-000000-audit --dry-run --skip gcp-iam-001
sectool --check-args review -s iam
```

**Agent duties:** narrow scope (`-s`); redact secrets; ask before `audit` and before any `--apply`; summarize by severity; bulky output under `/tmp/sectool-*.log`.

## `/find-housing`

**Command file:** `~/.<agent>/commands/find-housing.md` (template: `resources/agent-configs/commands/find-housing.md`)  
**Frontmatter:** `allowPromptArgument: true` + `argument-hint`; body `{{args}}`  
**Default (bare `/find-housing`):** usage on stderr, exit 2 (`--city` is required unless set in the config file). The command body passes `--format json` before the arguments, so a user `--format table` overrides it (last value wins); direct CLI default is `table`.

```bash
python3 ~/.<agent>/custom/scripts/find-housing/find_housing.py --format json <args>
```

| Option | Role |
|--------|------|
| `--city` (required unless `city` is in the config) | City name mapped to a Craigslist subdomain; unknown cities fall back to the name without spaces |
| `--max-rent`, `--min/max-bedrooms`, `--min/max-bathrooms` | Search filters |
| `--query` | Free-text search (URL-encoded) |
| `--max-listings` | Result cap, default 10 |
| `--details` / `--no-details` | Adds each posting body (one request per listing, capped by `--max-listings`); `--no-details` overrides a config `details = yes` |
| `--format table\|json` | Output; JSON is `{city, count, listings[]}` |
| `--check-args` | Parse-only; prints the fully merged namespace JSON (CLI + config + defaults), exit 0, no network |

**Config file (optional):** `~/.config/find_housing.cfg`, one section `[find_housing]`. Keys mirror the CLI flags: `city`, `max_rent`, `min_bedrooms`, `max_bedrooms`, `min_bathrooms`, `max_bathrooms`, `query`, `max_listings`, `details`, `format`. Precedence: CLI flag > config file > built-in default (`max_listings` 10, `format` table, `details` no). A missing file behaves as before. `query =` (empty) means no query. Values are not interpolated (`%` is literal). `city`, `query` and `format` may be wrapped in one matching pair of single or double quotes (removed); an unmatched quote stays literal. Inline comments start at ` #` or ` ;` (whitespace required before the marker), so `city = boston # home` means `boston`; other punctuation such as `query = dog & cat` is kept as-is. Cross-source rule: a CLI flag replaces the config value for the same key only; if a config `min_*`/`max_*` then conflicts with the opposite CLI bound (config `min_bedrooms = 3` plus `--max-bedrooms 2`), exit 2 with a message naming the config path/value and the CLI flag/value; nothing is dropped silently. Booleans accept yes/no, on/off, true/false, 1/0.

```ini
[find_housing]
city = san francisco
max_rent = 3000
min_bedrooms = 1
max_bedrooms = 3
min_bathrooms = 1
max_bathrooms = 2.5
query = dog friendly
max_listings = 5
details = no
format = table
```

Unknown sections or keys, duplicate keys, bad numbers, negative values, `max_listings < 1`, min greater than max, or an invalid `format`/`details`/`city` exit 2 with the file path and key on stderr (no traceback, no network). Unreadable paths (for example a directory) also exit 2. Lint `--examples` runs with the real `~/.config` file, so a broken config or a config min above an example's `--max-*` value will make lint fail.

**Dependencies:** PEP 723 inline (aiohttp, beautifulsoup4). The script re-runs itself under `uv run --quiet` (via `subprocess`, one level only, guarded by `FIND_HOUSING_UV_REEXEC`) on the search path when those are missing, so plain `python3` works for `--check-args` and usage errors. uv's stdout/stderr pass through; if uv exits 2 the script reports the failure and exits 1.

**Exit codes:** 0 success (incl. zero results), 2 argument error, 1 network, parse, or dependency-resolution failure (stderr message, empty stdout). A uv dependency failure is reported as 1, never 2.

**Examples**

```text
--city "san francisco" --max-rent 3000 --min-bedrooms 1 --format json
--city austin --min-bedrooms 2 --max-bedrooms 3 --min-bathrooms 1 --details --format json
--city "new york" --max-listings 20 --format table
```

## Authoring new commands

1. Add the template `resources/agent-configs/commands/<name>.md` (linux-configs repo) with YAML frontmatter:
   - `description` (required)
   - `allowPromptArgument: true` when trailing text should be optional (recommended for script wrappers)
   - `argument-hint` for Claude Code's completion hint
2. Prompt body: **EXECUTE IMMEDIATELY** + one bash line with `{{args}}` only; default bare behavior in the script; intent table, preconditions, exit-2 recovery rule, next steps, ```` ```text ```` examples (see "Fast CLI-wrapper pattern").
3. Put non-trivial logic in `resources/agent-configs/custom/scripts/<name>/` (Python/Bash); implement `--check-args`.
4. Optional: wrapper in `resources/agent-configs/custom/bin/<name>` (link onto `PATH`) for direct runs.
4a. Run `junie-cli/sync.sh` and `claude-code/sync.sh` to render and install it for both agents.
5. Document the command in this catalog.
6. Prefer idempotent, non-interactive CLIs (`--yes`, `--dry-run`); never mutate on EOF/no-TTY.
7. Run `agentmgr commands lint --examples` → `failures: 0`.
8. After editing commands, start a **new agent session** (Junie: or re-open `/commands`) so the CLI reloads definitions.

### Agent-session PATH (custom/bin shims)

`~/.<agent>/custom/bin` is **not** added to global login PATH by default. For shim access inside one agent only:

1. **Launch wrapper (process-wide PATH):** a `junie()` / `claude()` function in `~/.profile` (and/or `~/.bashrc` / `~/.zshrc`) that prepends that agent's `custom/bin` only for its process tree via `PATH=… command junie` (or an absolute binary path). Avoid `export PATH=…/custom/bin` unless you want shims in every shell — run standalone, `histmgr`/`agentmgr` then ask which agent to target.
2. **One-shot:** `PATH="$HOME/.junie/custom/bin:$PATH" junie` or `PATH="$HOME/.claude/custom/bin:$PATH" claude`

