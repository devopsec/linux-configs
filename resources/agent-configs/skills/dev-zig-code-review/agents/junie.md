# Junie specifics — dev-zig-code-review

- Execute the SKILL.md `sadkitti` block; load `tiger-style.md` only when its condition holds.
- Run `scripts/review-scan.sh` and `scan-legacy.sh` in the terminal tool; keep only the summary
  and the hits in files under review.
- Use `get_file_structure` before opening large Zig files; open targeted ranges around hits and
  changed functions.
- Report in the SKILL.md template; ask inline (numbered list) whether to apply fixes after the
  review — never edit during the review itself.
- No commits; the user reviews and submits changes.
