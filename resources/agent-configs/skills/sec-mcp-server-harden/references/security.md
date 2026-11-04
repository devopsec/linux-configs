# MCP Server Security Hardening

Derived from BagelHole/DevOps-Security-Agent-Skills `security/ai/mcp-server-security` (MIT, see `LICENSE.txt`), rewritten: Python/FastMCP first, upstream bugs fixed (symlink prefix check, unused SSRF blocklist, literal DB password), GCP/systemd deployment.

## Contents

1. Threat model
2. Transport
3. Authentication and credentials
4. Tool authorization
5. Input validation (schema, SQL, paths)
6. Outbound network / SSRF
7. Rate limits and budgets
8. Audit logging
9. Deployment hardening (systemd, container, GCP)
10. Security tests
11. Pre-production checklist

## 1. Threat model

| Threat | Vector | Primary control |
|---|---|---|
| Unauthorized tool access | Agent calls a tool the user may not use | Per-role allowlist, deny by default (§4) |
| Prompt injection via resources/results | Untrusted text in resources or API responses steers the agent | Treat results as data; flag untrusted origin; human approval for destructive tools |
| Data exfiltration | Results leak secrets/PII to the client | Field-level output filtering, redaction (§8) |
| SSRF | Tool fetches internal URLs or the cloud metadata server | Domain allowlist + resolved-IP check (§6) |
| Credential theft | Tokens stored in code, logs, or world-readable files | Secret Manager / env, hashed API keys (§3) |
| DoS / cost blow-up | Call floods, huge payloads | Rate limits, payload caps, token budgets (§7) |
| MITM | Plain HTTP transport | TLS 1.2+ (prefer 1.3), mTLS for service-to-service (§2) |
| Supply chain | Malicious MCP package / `npx -y` of unpinned server | Pin versions, lockfiles (`uv.lock`, `package-lock.json`), review before install |

## 2. Transport

- **stdio (local)**: the trust boundary is the process. Run as the invoking user, never root; scope filesystem roots explicitly in client config. For Node servers use the permission model (`node --permission --allow-fs-read=<dir> --allow-fs-write=<dir>`; older runtimes may require `--experimental-permission`). Pin the Node and server-package versions in the project lockfile/image and test the selected permission flags in CI; never use `npx -y <pkg>` with an unpinned latest package.
- **Streamable HTTP (remote)**: terminate TLS at a reverse proxy or GCP HTTPS load balancer; bind the app to loopback (`127.0.0.1`) behind it. Disable TLS < 1.2. Use mTLS (client certs) between internal services.
- Validate the `Origin` header on HTTP transports and bind local dev servers to loopback only (MCP spec DNS-rebinding guidance).

## 3. Authentication and credentials

- Remote servers: OAuth 2.1 (MCP authorization spec) with audience-bound tokens; validate `aud`, `iss`, `exp` on every request; never pass the client's token through to upstream APIs (token passthrough is explicitly forbidden by the spec).
- Simple deployments: hashed API keys with expiry and per-key tool scope. Store only the hash; compare by hash lookup (or `hmac.compare_digest` when comparing directly).

```python
import hashlib, hmac, os, time

def hash_key(plain: str) -> str:
    pepper = os.environ["MCP_KEY_PEPPER"]            # from Secret Manager, not code
    return hmac.new(pepper.encode(), plain.encode(), hashlib.sha256).hexdigest()

KEYS: dict[str, dict] = {}                           # hash -> {"user", "tools", "expires"}

def validate_key(plain: str) -> dict | None:
    rec = KEYS.get(hash_key(plain))
    if rec is None or time.time() > rec["expires"]:
        return None
    return rec
```

- Upstream API credentials: least privilege, read from env injected by systemd `LoadCredential=`/`EnvironmentFile=` (mode 0600) or fetched from GCP Secret Manager at start-up (`gcloud secrets versions access latest --secret=<name>` for ops; client library in code). Never log them, never return them in tool output.

## 4. Tool authorization

Deny by default; explicit deny wins; unknown role or missing session ⇒ deny (upstream silently fell back to a read-only role — do not).

```yaml
# config/tool-policy.yaml
policies:
  - role: developer
    allowed_tools: [read_file, search_code, run_tests]
  - role: readonly-agent
    allowed_tools: [read_file, list_directory, query_database]
dangerous_tools:
  execute_command: {risk: critical, requires_approval: true, max_per_session: 5}
  write_file:      {risk: high, requires_approval: true}
  query_database:  {risk: medium, allowed_operations: [SELECT]}
```

```python
def is_tool_allowed(policies: dict, role: str | None, tool: str) -> bool:
    policy = policies.get(role) if role else None
    if policy is None:
        return False
    if tool in policy.get("denied_tools", []):
        return False
    return tool in policy.get("allowed_tools", []) or "*" in policy.get("allowed_tools", [])
```

- Enforce in the server (a wrapper around every tool handler), not just in the client UI.
- Set MCP annotations honestly (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) — clients use them for approval prompts, but annotations are hints, not enforcement.
- Destructive tools: require explicit confirmation parameter and support a dry-run mode.

## 5. Input validation

- Strict schemas for every tool (Pydantic `model_config = ConfigDict(extra="forbid")`, Zod `.strict()`); bound string lengths, enum values, integer ranges; reject, don't coerce.
- Cap request body size at the proxy and in the app.

**SQL** — parameterized queries only; never interpolate agent text. Regex "forbidden pattern" filters are a weak extra layer, not a control. Real controls are a read-only role, row-level security, and timeouts (PostgreSQL / Cloud SQL):

```sql
-- password set out-of-band from Secret Manager, never in SQL files
CREATE ROLE mcp_readonly LOGIN;
GRANT USAGE ON SCHEMA app TO mcp_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO mcp_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO mcp_readonly;
ALTER TABLE app.customer_data ENABLE ROW LEVEL SECURITY;
CREATE POLICY mcp_access ON app.customer_data FOR SELECT TO mcp_readonly USING (sensitivity_level < 3);
ALTER ROLE mcp_readonly SET statement_timeout = '10s';
ALTER ROLE mcp_readonly SET default_transaction_read_only = on;
```

SQLite: open read-only via URI `file:<db>?mode=ro` with `uri=True`. BigQuery: dedicated service account with `roles/bigquery.dataViewer` on specific datasets + `maximum_bytes_billed` per query.

**Paths** — resolve symlinks *before* the containment check and compare path components, not string prefixes (upstream used `startsWith(root)` which accepts `/workspace-evil`):

```python
import os
from pathlib import Path

ROOT = Path(os.environ["MCP_SANDBOX_ROOT"]).resolve(strict=True)

def safe_path(user_path: str) -> Path:
    p = (ROOT / user_path).resolve()          # follows symlinks
    if not p.is_relative_to(ROOT):            # component-wise (Python 3.9+)
        raise PermissionError(f"path escapes sandbox: {user_path!r}")
    return p
```

TOCTOU remains possible if an attacker can write inside the root; combine with OS-level confinement (§9).

## 6. Outbound network / SSRF

Two layers, both required: (1) scheme + host allowlist, (2) resolve the host and reject private, loopback, link-local (includes the cloud metadata server), and reserved addresses — then connect to the *checked* IP to defeat DNS rebinding. Also disable automatic redirects or re-validate each hop.

```python
import ipaddress, socket
from urllib.parse import urlsplit

ALLOWED_HOSTS = {"api.github.com", "pypi.org"}

def check_outbound(url: str) -> list[str]:
    u = urlsplit(url)
    if u.scheme != "https" or u.hostname not in ALLOWED_HOSTS:
        raise PermissionError(f"blocked: {url}")
    ips = {ai[4][0] for ai in socket.getaddrinfo(u.hostname, u.port or 443)}
    for ip in map(ipaddress.ip_address, ips):
        if not ip.is_global or ip.is_multicast:
            raise PermissionError(f"blocked non-public address for {u.hostname}")
    return sorted(ips)                         # pin the connection to these
```

GCP: the metadata server (`metadata.google.internal`, link-local) hands out service-account tokens — block it for any tool that fetches user-supplied URLs, and give the VM a minimal-scope service account. Add VPC egress firewall rules (deny-all egress + allow to required destinations) as the network-layer backstop.

## 7. Rate limits and budgets

- Per-client token bucket on calls/minute plus a cap on concurrent calls; return a clear retry-after error.
- Per-session budgets: max tool calls, max result bytes, max LLM tokens (if the server calls models). Per-tool caps for dangerous tools (e.g. `execute_command` ≤ 5 per session).
- Truncate/paginate large results instead of returning them whole.

## 8. Audit logging

One structured JSON line per invocation: `id, timestamp, user, session, tool, params (redacted), result: success|error|denied, duration_ms, error`. Redact keys matching `password|token|secret|api_key|authorization|cookie` and values that look like credentials. Log denials too — they are the attack signal. On GCP write to stdout/journald and ship to Cloud Logging; route to BigQuery via a log sink for retention/analysis. Optionally add OpenTelemetry spans per tool call; pin the SDK/exporter to the application lockfile and record its release-check date when changing it.

## 9. Deployment hardening

**systemd unit (our default for VMs)** — drop-in hardening:

```ini
[Service]
User=mcp
Group=mcp
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ReadWritePaths=/var/lib/mcp-server
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes   # drop for Node/JIT runtimes
SystemCallFilter=@system-service
SystemCallArchitectures=native
CapabilityBoundingSet=
LoadCredential=api-token:/etc/mcp-server/api-token
```

Check with `systemd-analyze security <unit>`. On RHEL keep SELinux enforcing; label custom paths with `semanage fcontext` + `restorecon` rather than disabling. Python deps: `uv sync --frozen` from `uv.lock`.

**Container** — multi-stage build, pinned base image digest, non-root `USER`, `--read-only` rootfs with a tmpfs for scratch, `--cap-drop=ALL`, `--security-opt no-new-privileges`, default seccomp profile (or a tighter custom one), no package managers or shells beyond what's needed. Push to Artifact Registry and scan there. Kubernetes: NetworkPolicy deny-all + explicit egress.

## 10. Security tests (run in a CI pull-request pipeline)

- Authorization: every role × every tool matrix; unknown role and missing session must be denied.
- Input fuzzing: oversized strings, wrong types, extra fields, unicode/NUL bytes, `../` and absolute paths, symlink pointing outside root, sibling-prefix directory (`<root>-evil`).
- SSRF: must block — non-HTTPS schemes, `localhost`, IPv6 loopback, RFC 1918 hosts, link-local/metadata hostname, a hostname that *resolves* to a private address, redirects to blocked hosts; must allow — allowlisted public hosts.
- Rate limits: burst above limit returns rate-limit error; budget exhaustion stops the session.
- Secrets: grep logs produced by the test run for injected canary credentials — must find none.

## 11. Pre-production checklist

```
[ ] TLS on every HTTP transport; mTLS for service-to-service; loopback bind behind proxy
[ ] OAuth 2.1 / hashed API keys enforced on every request; no token passthrough
[ ] Tool allowlist per role, deny by default; dangerous tools require approval + dry-run
[ ] Strict schemas on all tool params; payload size caps
[ ] SQL parameterized; read-only DB role, RLS, statement timeout
[ ] Filesystem sandbox: resolve-then-contain check + OS confinement
[ ] Outbound allowlist + resolved-IP check; metadata server unreachable; egress firewall
[ ] Rate limits and per-session budgets
[ ] Structured audit log with redaction, denials logged, shipped to Cloud Logging
[ ] Non-root, systemd hardening / read-only container, seccomp
[ ] Dependencies pinned (uv.lock / package-lock.json), versions reviewed
[ ] Authz, fuzz, SSRF and rate-limit tests green in CI
```
