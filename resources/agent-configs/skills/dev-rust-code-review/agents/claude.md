# Claude specifics — dev-rust-code-review

- When the user invoked a review command or asked for findings in a structured form, follow
  that format (e.g. a findings tool) instead of the markdown template in SKILL.md.
- Run `review-scan.sh`, `scan-legacy.sh`, and `rust-env.sh` in one turn (independent), then
  read only the flagged regions plus the changed functions with Read offsets — don't load
  whole large files.
- For big diffs, delegate per-crate reading to an Explore agent with the checklist section
  names; verify every finding it returns against the code yourself before reporting.
- Clippy/tests/Miri execute the project's `build.rs` and proc macros — ask first if the code
  is not the user's own (e.g. a third-party PR). Use a long Bash timeout or
  `run_in_background` for first builds.
- Don't edit files during a review unless asked. Don't commit.
