# Playwright CLI Workflows

Requires `playwright-cli` to be installed globally (see the prerequisite check in `SKILL.md`). Snapshot often; refs go stale after navigation or significant DOM changes.

Save captured artifacts (screenshots, PDFs, traces) under a scratch/temp directory unless the user asks to keep them in the project.

## Basic navigation and interaction

```bash
playwright-cli open https://demo.playwright.dev/todomvc
playwright-cli snapshot
playwright-cli fill e1 "Buy milk"
playwright-cli press Enter
playwright-cli snapshot
```

## Data extraction

```bash
playwright-cli open https://example.com
playwright-cli snapshot
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
```

## Troubleshooting

- **Command not found**: `playwright-cli` is not installed globally. Stop and follow the prerequisite check in `SKILL.md` — do not fall back to `npx` or a bundled script.
- **Stale ref errors** (e.g. "element not found" for a previously valid ref like `e12`): re-run `playwright-cli snapshot` and use the fresh refs.
- **Flaky waits**: prefer explicit `playwright-cli` commands over `run-code`/`eval` loops; only use `run-code "await page.waitForTimeout(...)"` when there is no better signal to wait on.
- **Dialogs blocking interaction**: use `playwright-cli dialog-accept` or `playwright-cli dialog-dismiss` before continuing.
- **Debugging a flow**: wrap the interactions with `playwright-cli tracing-start` / `playwright-cli tracing-stop` and inspect the resulting trace.
