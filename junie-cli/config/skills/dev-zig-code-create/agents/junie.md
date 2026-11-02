# Junie specifics — dev-zig-code-create

- Execute the SKILL.md `sadkitti` routing block literally; load only the references it selects.
- Prefer project `just`/`mise` tasks (`just test`, `mise run build`) when present (see
  dev-just-recipe-manage / dev-mise-task-manage); fall back to `scripts/check.sh`.
- Use the terminal tool with an extended timeout for the first `zig build` (std compile).
- Search std with `scripts/std-find.sh` rather than opening large std files; when you must
  open one, use `get_file_structure` first (e.g. `Io.zig` is ~3.5k lines).
- Ask inline (numbered list) before: installing/upgrading Zig, changing
  `.minimum_zig_version`, adding a dependency via `zig fetch --save`, or porting to another
  Zig series.
- No commits; the user reviews and submits changes.
