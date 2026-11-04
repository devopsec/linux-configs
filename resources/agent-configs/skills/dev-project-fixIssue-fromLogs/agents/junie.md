# Junie specifics — dev-project-fixIssue-fromLogs

- Redirect large log greps to `/tmp`; never flood the session with full build logs.
- Use `rg`/`grep_search` for signatures; `open` with line numbers for cited source.
- Prefer [RUN_VERIFY]/SETUP] only as needed after a concrete fix hypothesis.
- No commits.
