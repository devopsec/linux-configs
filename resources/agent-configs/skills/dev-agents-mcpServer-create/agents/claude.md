# Claude Code Specifics for MCP Server Creation

Claude Code is highly effective at generating TypeScript and Python code and can quickly iterate on MCP server implementations.

## Development Workflow
- **Fast Iteration**: Use Claude's ability to run shell commands to bootstrap projects and install dependencies immediately.
- **Testing**: Claude can use the MCP Inspector (`npx @modelcontextprotocol/inspector`) to interactively test tools.

## Context Management
- Claude handles large files well, but for very complex MCP servers, it's still better to split tools into logical modules (e.g., `src/tools/users.ts`, `src/tools/projects.ts`).

## Evaluation
- The provided evaluation harness (`scripts/evaluation.py`) defaults to using `claude-3-7-sonnet-20250219`.
- When running evaluations, Claude Code should monitor the output for any tool errors and fix the server implementation in real-time.

## Safety
- Remind the user to review all generated code, especially if it involves system calls or external API interactions.
