# Junie Tuning: web-playwright-webapp-test

## Tool usage

- Run `scripts/with_server.py --help` and any Playwright automation scripts via `bash`; this is not covered by the specialized search/edit tools.
- Write disposable automation scripts with `create` into a scratch/temp directory (e.g. `/tmp`), run them with `bash`, then delete them once the task is done — don't leave one-off test scripts in the project repo.
- Check for `playwright` availability first (`python3 -c "import playwright"`) and confirm the Chromium browser binary is installed; only propose an install command if the check fails, and confirm with the user before installing anything.
- Use `open` on saved screenshots (PNG) to visually inspect results when needed, instead of guessing layout from DOM text alone.
- Load `examples/*.py` only when you need a concrete pattern; do not paste their full contents into the conversation.

## Context window

- Do not read `scripts/with_server.py` source unless a customized solution is truly required — call it with `--help` first and treat it as a black box, per the skill's own guidance.
- Do not paste full `page.content()` or long screenshot/log dumps back into the conversation; summarize only the relevant selectors/log lines.

## Workflow notes

- Always wait for `networkidle` before inspecting a dynamic page; if a selector-based action fails, re-run the reconnaissance step (screenshot/content/locator listing) rather than guessing a new selector blind.
- If the app requires a dev server, always run `python3 scripts/with_server.py --help` first before constructing the `--server`/`--port` invocation.
- Always close the browser (`browser.close()`), including on failure paths, to avoid leaking headless Chromium processes in the session.
