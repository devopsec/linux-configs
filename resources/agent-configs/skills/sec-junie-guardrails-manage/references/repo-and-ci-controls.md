# Repo and CI controls for agent-produced changes

Derived from upstream `security/ai/ai-coding-agent-guardrails` (MIT). Rewritten: Cloud Build instead of GitHub Actions, firewalld/nftables instead of hostname-based iptables (resolved once at insert time), attribution trailers dropped (our policy forbids co-author/attribution trailers), fictional `.agent-permissions.yaml` replaced by real agent configs (see `junie-cli.md`, `claude-code.md`).

## Contents

1. Secret scanning (pre-commit + CI)
2. Review gates
3. Container sandbox for unattended agents
4. Network egress for agent hosts
5. Audit trail
6. Team policy checklist

## 1. Secret scanning

Pre-commit (`.pre-commit-config.yaml`; Gitleaks v8.30.1, checked against the official release page on 2026-10-28):

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
```

CI pull-request pipeline (Cloud Build example), using the pinned upstream image:

```yaml
steps:
  - id: gitleaks
    name: ghcr.io/gitleaks/gitleaks:v8.30.1
    args: ["detect", "--source=.", "--no-banner", "--redact", "--exit-code=1"]
```

Patterns to make sure are covered (gitleaks defaults do most): GCP service-account JSON (`"type": "service_account"`, `private_key`), private key PEM headers, GitHub/Slack/cloud tokens, `.env` files committed, connection strings with inline passwords. Add `.env*`, `*.pem`, `*.key`, `secrets/` to `.gitignore`. Rotation after a leak → `sec-secrets-any-manage`.

## 2. Review gates

- Branch protection on `main`: PR required, ≥1 human approval, required checks (tests, lint, gitleaks, SAST), no force-push, no admin bypass.
- Agents work on branches (`agent/<task>`), never push to `main`; agents hold no merge rights.
- `CODEOWNERS` should protect the repository's infrastructure, deployment, and agent-policy paths so agent PRs touching them need an owner. Adapt this schematic to the actual layout:

```
/infrastructure/        @<infra-owners>
/deployment/            @<ops-owners>
/agent-policy/          @<agent-policy-owners>
```

- Label agent PRs (e.g. `agent-generated`) and state the agent + task in the PR description (provenance without commit trailers).
- CI checks for agent PRs: full test suite, coverage not decreasing on changed files, SAST (`sec-code-sast-scan`), dependency diff review (`sec-supplyChain-any-manage`), and a diff-size limit that forces human scoping.

## 3. Container sandbox for unattended agents

```bash
# run the agent against a copy of the repo; no host creds, no docker socket
docker run --rm \
  --network none \
  --read-only --tmpfs /tmp:rw,size=512m \
  --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 512 --memory 4g --cpus 2 \
  -u "$(id -u):$(id -g)" \
  -v "${REPO_COPY}:/workspace:rw" -w /workspace \
  "<agent-image>@sha256:<digest>" <agent command>
```

- `--network none` by default; if the agent needs the model API, use a dedicated network with an egress proxy allowlisting the provider domain + package registries.
- Never mount SSH key directories, the gcloud credentials directory, the docker socket, or the host home. Pass only a scoped model API key via env from Secret Manager.
- Rootless podman works the same on RHEL (`podman run … --userns=keep-id`).

## 4. Network egress for agent hosts (VM / runner)

Domain-based egress belongs in a proxy (Squid/Envoy allowlist) or the agent's own sandbox network filter; IP rules with hostnames resolve once and go stale. Host-level backstop:

- RHEL (firewalld): default-deny outbound via a policy object, allow DNS to the resolver, 443 to the proxy only.
- Debian/nftables: `owner` match on the agent UID → accept to proxy IP:port, drop rest.
- GCP: VPC egress firewall rules (deny all egress at low priority, allow to proxy / Private Google Access), runner VM with a minimal-scope service account, metadata server reachable only if the agent truly needs ADC.

Detailed firewall syntax → `sec-network-perimeter-manage`.

## 5. Audit trail

- Keep agent transcripts (Junie: `~/.junie/sessions/…/transcript.md`; Claude: stream-json output in CI artifacts) for agent-run CI jobs; retain per policy, redact secrets.
- Log tool calls with: timestamp, agent, task id, tool, args (redacted), result. Ship CI logs to Cloud Logging → BigQuery sink for querying (`sec-cloud-auditLogging-manage`).
- Periodically diff allowlist/permission files and review new allow rules.

## 6. Team policy checklist

```
[ ] Approved agents and versions listed; installs pinned/verified (no curl|sh)
[ ] Default ask; unattended high-privilege modes only in sandbox/containers
[ ] Secret files unreadable by agents (permissions + sandbox + .gitignore)
[ ] Agents cannot push to protected branches or merge
[ ] Agent PRs labelled, CODEOWNERS on sensitive paths, required checks green
[ ] Secret scanning in pre-commit and CI
[ ] Egress restricted for unattended agents
[ ] Transcripts retained for CI agent runs; allowlists reviewed monthly
[ ] Injection red-team cases in the eval suite (`dev-agents-evals-create`)
```
