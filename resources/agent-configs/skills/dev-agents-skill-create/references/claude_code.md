# Claude Code Guidelines

Claude Code is Anthropic's CLI-based agent. When creating a skill for Claude Code, follow these guidelines.

## Architecture & Configuration
- **Configuration**: Claude Code often uses a `CLAUDE.md` file in the project root for general instructions, but can also load skills from standardized folders if configured.
- **Environment**: Terminal-based, optimized for fast iteration and code modification.
- **Tools**: Similar to Junie, it has file system and terminal access.

## Documenting for Claude Code
When writing `agents/claude.md` for a new skill:
1. **Style**: Claude Code prefers concise, imperative instructions.
2. **Commands**: Mention specific shell commands that Claude Code should use if they are part of the workflow.
3. **Safety**: Claude Code has built-in safety prompts, but the skill should emphasize reviewing generated code before execution.

## Tuning for Claude
- Claude is very good at following complex logic but can sometimes get stuck in loops. Use the `agents/claude.md` to provide "circuit-breaker" logic or alternative paths if a task fails.
- Emphasize the use of its built-in linter and test runner if applicable.
