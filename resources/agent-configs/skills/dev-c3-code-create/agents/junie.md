# Junie specifics — dev-c3-code-create

- Execute the SKILL.md `sadkitti` routing block literally; load only the selected references.
- Prefer project `just`/`mise` tasks when present (dev-just-recipe-manage / dev-mise-task-manage);
  otherwise `scripts/check.sh`.
- Use `scripts/std-find.sh` instead of opening large stdlib files; if you must open one, use
  `get_file_structure` first.
- Use the terminal tool with an extended timeout for the first `c3c build`.
- Ask inline (numbered list) before: installing/upgrading c3c, `c3c vendor-fetch`, adding
  dependencies, enabling `--trust=full`, or porting to another C3 release.
- No commits; the user reviews and submits changes.
