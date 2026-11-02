# Junie specifics — dev-c3-version-migrate

- Execute the SKILL.md `sadkitti` block for every version step crossed; load only those references.
- Run `scripts/scan-legacy.sh` in the terminal tool; keep only the summary and the hits for the
  file being edited in context.
- One version step per plan item; mark it done after the target compiler builds and tests pass
  (or note that it was unavailable).
- Ask inline (numbered list) before changing the target version, re-fetching vendor libraries,
  or editing CI files that pin c3c.
- No commits; the user reviews and submits changes.
