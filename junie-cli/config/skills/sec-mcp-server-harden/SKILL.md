---
name: sec-mcp-server-harden
description: "Threat-model and harden MCP servers, transports, tool authorization, input validation, SSRF boundaries, and deployment. Use when users ask for MCP server security reviews, FastMCP/TypeScript hardening, OAuth, tool policies, or production readiness checks."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/ai/mcp-server-security
  license: MIT
---

# MCP Server Security Hardening

Use when server-side MCP controls are in scope; keep tool implementation guidance in `dev-agents-mcpServer-create` and link to it rather than duplicating it.

## Triggers

- MCP server security review, production hardening, authorization, authentication, or transport choice.
- Tool schemas, SQL/path access, outbound requests, SSRF, rate limits, audit logs, or security tests.

## Load order (SAD KITTI)

```sadkitti
IF file exists "~/.junie/custom/configs/security/mcp-server.toml"
  REFERENCE "~/.junie/custom/configs/security/mcp-server.toml"
ELSE
  USE the security-test and transport defaults listed below
IF task involves MCP server threat modeling or hardening
  REFERENCE "references/security.md"
CACHE only the controls relevant to the selected transport and tools
```

## Workflow

1. Model trust boundaries, identities, exposed tools, data stores, and consequences of compromised tool output.
2. Choose local stdio or remote HTTP deliberately; require TLS/authentication for remote servers and deny-by-default authorization in server code.
3. Validate schemas, parameters, filesystem roots, SQL, and outbound destinations; cap request size, calls, and spend.
4. Redact audit events, test negative authorization/SSRF cases, and review deployment permissions before release.

## Security-test defaults

- Use strict schema tests, per-role denial tests, path/symlink boundary tests, DNS/IP SSRF cases, and read-only database roles.
- Follow the optional TOML selection; never install an unpinned server package or expose credentials in examples/logs.
- Optional security-test choices are illustrated in `assets/config.example.toml`; do not create global config files automatically.

## Related skills

- MCP server implementation and protocol patterns → `dev-agents-mcpServer-create`.
- LLM tool-call and output controls → `sec-llm-io-guard`.
- Coding-agent prompt injection via MCP results → `sec-agents-promptInjection-defend`.
