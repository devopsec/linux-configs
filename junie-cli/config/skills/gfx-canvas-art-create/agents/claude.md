# Claude Specifics for Gfx Canvas Art Create

## Context & Tuning

This skill originates from Anthropic's own `canvas-design` skill for Claude/Claude Code, which can use its code-execution/canvas tooling directly to render the `.pdf`/`.png` artifact. When running as Claude Code, prefer generating the artifact through a script (Python/JS) executed in the sandbox rather than hand-drawn markup.

## Instructions Overrides

None beyond the main `SKILL.md` — this port preserves the original workflow and guidelines as-is.

## Performance Notes

- Reuse fonts from `assets/canvas-fonts/` instead of fetching new ones, to avoid unnecessary network calls.
- Keep the two-pass workflow (philosophy, then canvas) as separate turns/tool calls so each artifact can be reviewed before the next step.
