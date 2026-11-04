# Claude specifics — sec-mcp-server-harden

- Test deny-by-default authorization, malformed inputs, and network boundary checks per exposed tool.
- Keep production credentials out of test fixtures and never send a real write operation during validation.
- Cross-link to `dev-agents-mcpServer-create` for implementation details rather than duplicating them.
