# Junie specifics — dev-zig-version-migrate

- Execute the SKILL.md `sadkitti` block for every series step between source and target; load
  only those per-version references.
- Run `scripts/scan-legacy.sh` in the terminal tool; paste only the summary plus the hits for
  the file being edited into your reasoning, not the full listing.
- One series step per plan item; mark it done only after `zig build test` passes on that
  step's compiler (or note that the intermediate compiler was unavailable).
- Ask inline (numbered list) before: changing the target series, bumping dependencies, or
  editing CI files that pin the Zig version.
- No commits; the user reviews and submits changes.
