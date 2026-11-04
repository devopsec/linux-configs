# Junie specifics — dev-rust-code-review

- Execute the SKILL.md `sadkitti` routing block literally; load only the references it selects.
- Run `scripts/review-scan.sh` and `scan-legacy.sh` with the terminal tool; open only the
  flagged regions and changed functions (`get_file_structure` first for large files).
- Prefer project `just`/`mise` lint/test tasks when present over the raw clippy command.
- Ask inline (numbered list) before building or running tests on code that isn't the
  user's own (third-party PRs), and before installing audit tools (`cargo install cargo-audit`).
- Read-only review: no edits unless the user asks for fixes. No commits.
