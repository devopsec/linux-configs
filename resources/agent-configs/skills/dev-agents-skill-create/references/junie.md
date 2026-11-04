# Junie (Junie CLI) Guidelines

Junie (specifically Junie CLI) is the primary agent used in this repository. When creating a skill for Junie, follow these guidelines.

## Architecture & Configuration
- **Configuration**: Junie looks for skills in `.junie/skills/` and `.agents/skills/`.
- **Environment**: Junie typically operates within a Linux terminal (Ubuntu) and has access to PyCharm IDE features and MCP tools.
- **Tools**: Junie has powerful file system, search, and terminal execution capabilities.

## Documenting for Junie
When writing `agents/junie.md` for a new skill:
1. **Tool Usage**: Explicitly mention which Junie tools (e.g., `search_project`, `multi_edit`) are best suited for the skill's tasks.
2. **Context Window**: Junie is optimized for lean context. Encourage Junie to use `open` with specific line numbers rather than `open_entire_file` for large files.
3. **Task Breakdown**: Junie performs best with clear, sequential steps and explicit status updates via `update_status`.

## Preferences
- **Language**: English (default) or the user's detected language.
- **Output**: Clean Markdown, no unnecessary verbosity.
- **Safety**: Junie requires explicit user confirmation for potentially destructive commands. The skill should remind Junie to ask for this confirmation.
