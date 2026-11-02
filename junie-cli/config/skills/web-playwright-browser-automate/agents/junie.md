# Junie Tuning: web-playwright-browser-automate

## Tool usage

- Run `playwright-cli` commands via `bash`; this CLI is not covered by the specialized search/edit tools.
- Always run the `command -v playwright-cli` prerequisite check with `bash` before issuing any other `playwright-cli` command in a session.
- If the check fails, stop and report to the user that `playwright-cli` is missing, with the install instructions from `SKILL.md`. Do not attempt to install it yourself unless the user explicitly asks you to.
- Use `open` on captured `screenshot`/`pdf` artifacts to visually inspect results when needed, instead of guessing from `snapshot` text alone.

## Context window

- Load `references/cli.md` only when you need the full command list; load `references/workflows.md` only when troubleshooting or looking for a recipe.
- Do not paste full `snapshot` output back into the conversation; summarize the relevant refs/elements only.

## Workflow notes

- All captured artifacts (screenshots, PDFs, traces) must go under `/tmp` or the scratch directory (see the global scratch-directory convention) unless the user explicitly wants them kept in the project repo.
- Never substitute `npx @playwright/cli` or any bundled wrapper script for a missing global `playwright-cli` install — this skill intentionally has no bundled scripts and always requires the real CLI.
