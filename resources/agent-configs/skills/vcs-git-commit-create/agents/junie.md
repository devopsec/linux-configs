# Junie specifics — vcs-git-commit-create

- Default to **message-only** unless the user clearly ordered a commit/amend.
- Junie global policy often forbids autonomous commits — still follow this skill's approval gate even when commit mode is requested.
- Show `git status --short` + proposed message before any `git add`/`git commit`.
- Do not add `Co-authored-by` trailers unless the user or active project guidelines explicitly require it for this repo.
- Never push or `--force`.
- Scratch: redirect large diffs to `/tmp` when summarizing.
