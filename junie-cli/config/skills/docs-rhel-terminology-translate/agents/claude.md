# Claude Code Specifics for RHEL Terminology Translate

## Context & Tuning

Claude Code loads Agent Skills from `.claude/skills/` or an equivalent skills directory and follows the same progressive-disclosure model (frontmatter always resident, body loaded on trigger, `references/` loaded on demand). No changes to the trigger description are needed for Claude.

If Claude Code has an MCP server configured that exposes RHEL system diagnostic tools (matching the tool names listed in `SKILL.md`), use it the same way described in the main workflow. Otherwise, answer purely from the translation tables.

## Instructions Overrides

None — the core workflow in `SKILL.md` applies as-is.

## Performance Notes

- Prefer Claude's file-search/grep tools to jump directly to the relevant table row in `references/translation-tables.md` rather than reading the entire file when the user's terminology is already known.
