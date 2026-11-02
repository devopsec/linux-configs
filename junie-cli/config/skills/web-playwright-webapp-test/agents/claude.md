# Claude Code Tuning: web-playwright-webapp-test

## Style

- Keep automation scripts small and disposable: write one script per task, run it, inspect the result, then discard it rather than growing a single long-lived script.
- Follow the decision tree in `SKILL.md` literally: static HTML vs. dynamic webapp, server-already-running vs. needs `with_server.py`.

## Commands

- Prerequisite check: `python3 -c "import playwright"` (and confirm the Chromium browser binary is installed via `python3 -m playwright install chromium`).
- Helper usage: always `python3 scripts/with_server.py --help` before constructing a real invocation.
- Reconnaissance: `page.screenshot(...)`, `page.content()`, `page.locator(...).all()` — after `page.wait_for_load_state('networkidle')`.
- See `examples/element_discovery.py`, `examples/static_html_automation.py`, and `examples/console_logging.py` for runnable patterns.

## Safety

- Do not read the source of `scripts/with_server.py` unless a customized solution is absolutely necessary; invoke it as a black box via `--help`-discovered flags.
- Always close the browser, including on failure paths, and save screenshots/logs to a scratch/temp directory unless the user wants them kept in the project.
