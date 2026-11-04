# Junie specifics — gfx-mcp-image-create

- Use the configured local image MCP tool only; do not call external HTTP image APIs unless the user names one.
- Place outputs under the project assets path the user chose; never invent binary bytes in chat.
- No git commit of generated binaries unless explicitly requested.
