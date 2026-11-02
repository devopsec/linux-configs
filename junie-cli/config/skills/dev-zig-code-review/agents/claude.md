# Claude specifics — dev-zig-code-review

- When the user invoked a review command or asked for findings in a structured form, follow
  that format (e.g. a findings tool) instead of the markdown template in SKILL.md.
- Run both scan scripts in one turn (independent), then read only the flagged regions plus the
  changed functions with Read offsets — don't load whole large files.
- For big diffs, delegate per-directory reading to an Explore agent with the checklist section
  names; verify every finding it returns against the code yourself before reporting.
- Building/running tests executes the project's build.zig — ask first if the code is not the
  user's own (e.g. a third-party PR). Don't edit files during a review unless asked.
