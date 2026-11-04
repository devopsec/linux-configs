---
description: "Run IaC/GCP security tools (audit, review, remediate, refactor)"
allowPromptArgument: true
argument-hint: "[audit|review|remediate|refactor] [args...]"
---

EXECUTE IMMEDIATELY — one shell call. No planning, repo exploration or guideline loading.

```bash
python3 {{agent_home}}/custom/scripts/sectools/sectool.py {{args}}
```

- Bare `/sectool` → lists tools. First token is the tool (`audit|review|remediate|refactor`), the rest are tool args. Pass the arguments through **unchanged**; bare tool name → its `--help`. Works the same from any agent (no agent-specific state).
- If the script exits 2 (usage error, e.g. natural-language input or a path argument): run `... sectool.py <tool> --help`, map the request onto real flags using the table below, echo the resolved command, run once more. Never guess `--apply`/`--skip-all`.
- Summarize findings by severity; bulky output → `/tmp/sectool-*.log`. Redact secrets. No git commit.

**Intent → argv**

| User wants | argv |
|------------|------|
| scan the IaC code for security issues | `review` (narrow: `review -s iam network`) |
| see past audits/reviews | `refactor -l` (same as `remediate -l`) |
| what is still open in a review | `refactor AUDIT_ID` → non-interactive: lists pending finding IDs, writes nothing |
| record a code fix / defer a finding | `refactor AUDIT_ID --apply ID` · `--skip ID` (preview: `--dry-run`) |
| scan the **live** GCP project | `audit -s iam` — **ask the user first** (live cloud + credentials) |
| act on live-audit findings | `remediate AUDIT_ID --dry-run --apply ID` → after explicit OK without `--dry-run` |

**Preconditions / side effects**

- cwd **must be the IaC repo root**: `review` scans `./platforms/**/*.tf`; `review`/`audit` write `.audits/<id>/gcp-<subsystem>.json` into cwd. No path argument exists — `cd` there instead.
- `audit` calls `gcloud` against the active project: requires `gcloud auth` and explicit user OK before running (credentials rule). `review` is offline.
- `remediate`/`refactor` only mutate finding status via explicit `--apply/--skip/--skip-all`; `--apply` means the agent then performs the listed fix.

**Next steps**

- After `review`: `refactor AUDIT_ID` to list finding IDs, propose fixes, record them with `--apply ID` once done.
- After `audit`: `remediate AUDIT_ID` to list IDs; confirm each remediation command with the user before `--apply`.

Examples (each line is valid argv after `/sectool`):

```text
review --help
review -s iam network
refactor -l
refactor 20260101-000000-review
remediate 20260101-000000-audit --dry-run --skip gcp-iam-001
```
