# Claude Code Tuning: web-playwright-browser-automate

## Style

- Keep instructions concise and imperative: check, open, snapshot, interact, re-snapshot, capture.
- Run one `playwright-cli` command at a time and inspect its output before issuing the next, rather than batching a long sequence of interactions blind.

## Commands

- Prerequisite check: `command -v playwright-cli >/dev/null 2>&1`
- Core loop: `playwright-cli open <url>` -> `playwright-cli snapshot` -> `playwright-cli click/fill/... <ref>` -> `playwright-cli snapshot`
- See `references/cli.md` for the full command reference and `references/workflows.md` for recipes.

## Safety

- If the prerequisite check fails, stop immediately and surface the install instructions from `SKILL.md` to the user; do not fall back to `npx` or write a wrapper script yourself.
- Avoid `run-code`/`eval` unless there is no explicit `playwright-cli` command that achieves the same result.
