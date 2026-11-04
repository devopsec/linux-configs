# Junie (Junie CLI) Specifics for MCP Server Creation

When using Junie to build MCP servers, leverage its deep integration with the codebase and terminal.

## Tool Usage
- **Search**: Use `search_project` to find existing MCP server implementations or utility functions in this repo that can be reused.
- **Editing**: Use `multi_edit` for simultaneous changes to `index.ts`, `types.ts`, and `package.json`.
- **Validation**: Use `bash` to run `npm run build` or `python -m py_compile` frequently.

## Context & Performance
- Junie is optimized for lean context. When researching APIs, use `fetch_url` to get only the necessary documentation.
- When implementation grows large, prefer editing specific files rather than the whole project.

## Safety & Destructive Operations
- Junie requires explicit user confirmation for destructive operations. If your MCP server includes destructive tools, ensure they are correctly annotated with `destructiveHint: true`.
- Before running evaluations, confirm with the user that the target environment is safe for automated tool calls.
