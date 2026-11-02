# Runbook layout and template

## Location and naming

Follow the repository's documentation structure. When the repository uses the standard runbook tree, keep operator procedures under `documentation/user/runbooks/` and maintain its index. Use lowercase kebab-case filenames and one operation per document.

```text
documentation/user/runbooks/
  README.md
  <service>/<operation>.md
```

## Runbook skeleton

```markdown
# Runbook: <service> — <operation>

| Owner | Version | Last reviewed | Last tested | Severity | Trigger |
|---|---|---|---|---|---|
| <team> | 1.0 | YYYY-MM-DD | YYYY-MM-DD / never | SEVn | <alert or symptom> |

## Overview
What the procedure does, when to use it, when not to use it, and expected duration.

## Prerequisites
- [ ] Access: <approved role and access path>
- [ ] Tools: <required tools and version constraints>
- [ ] Incident channel and IC approval, if this is incident work
- [ ] Verified backup/snapshot before a destructive step

## Procedure
### 1. <Action>
Why this step exists.

```bash
<command with explained placeholders>
```

**Expected:** <observable result>. **If not:** <troubleshooting branch>.

### 2. ⚠ DESTRUCTIVE — <Action>
Preview first, state the point of no return, then show the approved action.

## Verification
- [ ] <health check and expected result>
- [ ] <log/metric check and expected result>

## Rollback
Numbered reverse steps, or state that the action is not reversible and link to restore guidance.

## Troubleshooting
| Symptom | Likely cause | Resolution |
|---|---|---|
| | | |

## Escalation
<Role/rotation and escalation threshold; no personal phone numbers.>

## Related
- <related procedures, dashboards, code/config of record>

## Change log
| Date | Author | Version | Change |
|---|---|---|---|
| YYYY-MM-DD | <name> | 1.0 | Initial |
```

## Index

Keep an index with service, runbook link, trigger, severity, owner, and last-tested date. Link procedures from relevant alerts and incident playbooks. Prefer links to code/config of record over copied large configuration blocks that will drift.

Use MAJOR.MINOR versioning: change MAJOR when steps or ordering change; MINOR for clarifications or contacts. Preserve prior versions through repository history and mark obsolete procedures deprecated rather than silently deleting them.