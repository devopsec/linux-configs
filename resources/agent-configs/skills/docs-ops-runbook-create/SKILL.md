---
name: docs-ops-runbook-create
description: "Create, review, test, and maintain operational runbooks and SOPs with prerequisites, safe steps, expected results, verification, rollback, escalation, and ownership. Use when a task mentions an on-call runbook, SOP, recovery procedure, troubleshooting guide, operational playbook, runbook review, or game day."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - compliance/continuity/runbook-creation
  license: MIT
---

# Operational runbook authoring

Write procedures that an on-call engineer can follow without tribal knowledge. Ground every operational command in the repository or an approved authoritative source.

## Triggers

- Create or update a runbook, SOP, on-call procedure, recovery guide, or troubleshooting guide
- Review, test, version, index, or rehearse an operational procedure

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF the repository contains documentation/agent/bash-guidelines.md
  REFERENCE "documentation/agent/bash-guidelines.md" AT SECTION "Interactive & Orchestration Command Style"
IF creating a new runbook or index
  REFERENCE "references/runbook-template.md"
IF reviewing, testing, versioning, or linting runbooks
  REFERENCE "references/review-testing.md"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Scope one operation and one service; identify trigger, audience, impact, owner, and authoritative configuration.
2. Read the repository's units, scripts, configuration, and existing procedures; ask for missing site values instead of inventing them.
3. Draft prerequisites, numbered steps, expected outputs, verification, rollback, troubleshooting, escalation, related procedures, and change history.
4. Label destructive steps, put a dry-run or read-only preview first, explain the point of no return, and require approval.
5. Test on an approved non-production target, shellcheck extracted scripts, arrange a peer walkthrough, and record the actual test date.
6. Register the runbook in the repository's index, and link it from the relevant alert or incident procedure.

## Safety

- Use placeholders or approved TOML settings for hosts, IPs, CIDRs, buckets, credentials, and targets; never include authentication material or customer data.
- Do not execute a procedure while authoring it unless the user explicitly requests an operational action.
- If an action is irreversible, state that clearly and require a verified backup and approval first.

## Related skills

- Incident roles, escalation, and PIR → `sec-ops-incident-respond`
- Bash script review and ShellCheck → `dev-bash-script-review`
- Repository documentation and index upkeep → `docs-project-documentation-update`
