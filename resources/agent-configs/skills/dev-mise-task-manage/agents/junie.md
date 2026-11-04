# Junie CLI Specifics for Dev Mise Task Management

- If a `mise-run_task` MCP tool is available, use it for execution only (task name); never for subcommands, discovery, help, or metadata. Otherwise use `mise run <task>`.
- Read the `mise://tasks` MCP resource, when exposed, for structured metadata (`source`, `config_sources`, dependencies).
- `mise-install_tool` may be unimplemented; fall back to the repository's normal CLI install flow.
