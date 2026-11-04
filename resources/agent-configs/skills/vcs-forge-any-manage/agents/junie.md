# Junie specifics — vcs-forge-any-manage

- Execute the SKILL.md `sadkitti` routing block literally; load only the references it selects.
- Run `scripts/forge-ctx.sh` with the terminal tool before the first write in a session.
- Ask inline (numbered list) before any mutating forge call: PR/issue create/edit/close,
  comments, reviews, merges, label/milestone/release/secret/repo changes, `ci run|retry|cancel`,
  and `forge api -X POST|PATCH|PUT|DELETE`.
- Put long bodies in a scratch file under `/tmp` and pass `-b "$(cat /tmp/body.md)"`.
- Never run `forge auth login` with a literal `--token`; ask the user to run it with
  `--token-cmd`. Never print `forge auth status` token-cmd lines into reports.
- No commits; no force pushes.
