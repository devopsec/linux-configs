---
name: web-playwright-browser-automate
description: Use when the task requires automating a real browser from the terminal (navigation, form filling, snapshots, screenshots, data extraction, UI-flow debugging) via the `playwright-cli` command. Requires `playwright-cli` to already be installed globally on the system.
---

# Web Playwright Browser Automate

## Overview

Drive a real browser from the terminal using `playwright-cli`. Treat this skill as CLI-first automation, not `@playwright/test` — do not pivot to writing test spec files unless the user explicitly asks for them.

## Prerequisite check (required, always first)

Before proposing or running any command, verify `playwright-cli` is installed and reachable:

```bash
command -v playwright-cli >/dev/null 2>&1
```

- If found, proceed with the workflow below.
- If NOT found: stop immediately, warn the user that `playwright-cli` is not installed, and do not attempt to install it, substitute `npx`, or fall back to any bundled wrapper. Ask the user to install it first, e.g.:

```bash
npm install -g @playwright/cli@latest
playwright-cli --help
```

Re-run the `command -v` check after the user confirms installation before continuing.

## Core workflow

1. Open the page.
2. Snapshot to get stable element refs.
3. Interact using refs from the latest snapshot.
4. Re-snapshot after navigation or significant DOM changes.
5. Capture artifacts (screenshot, pdf, traces) when useful.

Minimal loop:

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli click e3
playwright-cli snapshot
```

## When to snapshot again

Snapshot again after:
- navigation
- clicking elements that change the UI substantially
- opening/closing modals or menus
- tab switches

Refs can go stale. When a command fails due to a missing ref, snapshot again.

## Recommended patterns

### Form fill and submit

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "<password>"
playwright-cli click e3
playwright-cli snapshot
```

### Debug a UI flow with traces

```bash
playwright-cli open https://example.com --headed
playwright-cli tracing-start
# ...interactions...
playwright-cli tracing-stop
```

### Multi-tab work

```bash
playwright-cli tab-new https://example.com
playwright-cli tab-list
playwright-cli tab-select 0
playwright-cli snapshot
```

## References

Open only what you need:
- CLI command reference: `references/cli.md`
- Practical workflows and troubleshooting: `references/workflows.md`

## Guardrails

- Never proceed without a successful `command -v playwright-cli` check; do not substitute `npx`, a bundled wrapper script, or any other fallback for a missing installation.
- Always snapshot before referencing element ids like `e12`.
- Re-snapshot when refs seem stale.
- Prefer explicit commands over `eval` and `run-code` unless needed.
- When you do not have a fresh snapshot, use placeholder refs like `eX` and say why; do not bypass refs with `run-code`.
- Use `--headed` when a visual check will help.
- Keep captured artifacts (screenshots, PDFs, traces) in a scratch/temp directory unless the user asks to keep them in the project.
- Default to CLI commands and workflows, not Playwright test specs.

## Agent-specific notes

See `agents/junie.md` and `agents/claude.md` for tool-specific tuning.

## Source

Adapted from the `playwright` skill in [JetBrains/skills](https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/playwright/SKILL.md) (originally authored by OpenAI, Apache-2.0 licensed). The bundled wrapper script and `npx`-based fallback install from the source skill were intentionally removed; this skill always requires a globally installed `playwright-cli`.
