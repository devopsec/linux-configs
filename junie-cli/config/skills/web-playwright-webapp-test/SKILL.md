---
name: web-playwright-webapp-test
description: Use when the task requires testing or interacting with a local web application (static HTML or a dev server) by writing native Python Playwright scripts — verifying frontend functionality, debugging UI behavior, capturing screenshots, or viewing browser console logs.
license: Complete terms in LICENSE.txt
---

# Web Playwright Webapp Test

## Overview

Test local web applications by writing native Python Playwright scripts rather than reaching for a generic browser-automation CLI or ad-hoc curl-based checks. This skill packages a server-lifecycle helper and reference examples so scripts stay small and disposable.

## Bundled helper script

`scripts/with_server.py` manages server lifecycle (start, wait-until-ready, run command, clean up), and supports multiple servers at once.

**Always run it with `--help` first** to see current usage. Treat it as a black box — invoke it directly rather than reading its source, unless a customized solution is absolutely necessary. It exists precisely to avoid pulling large script internals into context.

```bash
python3 scripts/with_server.py --help
```

## Decision tree: choosing your approach

```
User task -> Is it static HTML?
├─ Yes -> Read the HTML file directly to identify selectors
│         ├─ Success -> Write a Playwright script using those selectors
│         └─ Fails/Incomplete -> Treat as dynamic (below)
│
└─ No (dynamic webapp) -> Is the server already running?
   ├─ No -> Run: python3 scripts/with_server.py --help
   │        Then use the helper + write a simplified Playwright script
   │
   └─ Yes -> Reconnaissance-then-action:
       1. Navigate and wait for networkidle
       2. Take a screenshot or inspect the DOM
       3. Identify selectors from the rendered state
       4. Execute actions with the discovered selectors
```

## Using with_server.py

Single server:

```bash
python3 scripts/with_server.py --server "npm run dev" --port 5173 -- python3 your_automation.py
```

Multiple servers (e.g. backend + frontend):

```bash
python3 scripts/with_server.py \
  --server "cd backend && python3 server.py" --port 3000 \
  --server "cd frontend && npm run dev" --port 5173 \
  -- python3 your_automation.py
```

The automation script itself should contain only Playwright logic — servers are managed automatically by the helper:

```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)  # Always launch chromium in headless mode
    page = browser.new_page()
    page.goto('http://localhost:5173')  # Server already running and ready
    page.wait_for_load_state('networkidle')  # CRITICAL: wait for JS to execute
    # ... your automation logic
    browser.close()
```

## Reconnaissance-then-action pattern

1. **Inspect the rendered DOM**:

```python
page.screenshot(path='/tmp/inspect.png', full_page=True)
content = page.content()
page.locator('button').all()
```

2. **Identify selectors** from the inspection results.
3. **Execute actions** using the discovered selectors.

## Common pitfall

- Don't inspect the DOM before waiting for `networkidle` on dynamic apps.
- Do wait for `page.wait_for_load_state('networkidle')` before inspection.

## Best practices

- Use the bundled helper script as a black box — check whether `scripts/with_server.py` can handle a task before writing custom server-management code; use `--help` to see usage, then invoke directly.
- Use `sync_playwright()` for synchronous scripts.
- Always close the browser when done, including on failure paths (e.g. `try`/`finally`).
- Use descriptive selectors: `text=`, `role=`, CSS selectors, or IDs.
- Add appropriate waits: `page.wait_for_selector()` or `page.wait_for_timeout()`.
- Save screenshots, PDFs, and logs to a scratch/temp directory (e.g. `/tmp`) unless the user asks to keep them in the project.

## Reference examples

Open only what you need under `examples/`:

- `element_discovery.py` — discovering buttons, links, and inputs on a page.
- `static_html_automation.py` — using `file://` URLs for local HTML.
- `console_logging.py` — capturing console logs during automation.

## Dependencies (check before installing)

Check first whether `playwright` is already importable, and whether the Chromium browser binary is installed; only install if missing, and ask the user before installing anything system-wide.

Prefer `uv` for Python dependency management:

```bash
uv pip install playwright
python3 -m playwright install chromium
```

If `uv` is unavailable:

```bash
python3 -m pip install playwright
python3 -m playwright install chromium
```

## Agent-specific notes

See `agents/junie.md` and `agents/claude.md` for tool-specific tuning.

## Source

Adapted from the `webapp-testing` skill in [JetBrains/skills](https://github.com/JetBrains/skills/blob/e0f258b5cfed145015cb3e48da9a97947f7c4ed7/webapp-testing/SKILL.md) (originally authored by Anthropic, Apache-2.0 licensed).
