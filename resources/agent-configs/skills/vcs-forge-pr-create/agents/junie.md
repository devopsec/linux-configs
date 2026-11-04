# Junie specifics — vcs-forge-pr-create

- Follow the skill `SKILL.md` workflow; load `references/` only as needed.
- Scratch outputs under `/tmp`; do not pollute the project with temp files.
- Use `forge` (see vcs-forge-any-manage) only after confirming repo/branch; never force-push. `gh` is not used.
- No git commits unless the user explicitly requests `vcs-git-commit-create`.
