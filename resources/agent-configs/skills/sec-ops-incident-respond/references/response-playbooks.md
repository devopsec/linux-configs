# Incident triage and response playbooks

## Severity and roles

| Severity | Example impact | Initial acknowledgement | Update cadence |
|---|---|---|---|
| SEV1 | Active breach, ongoing exfiltration, severe outage, or abuse causing immediate harm | Immediate paging | Frequent, set by IC |
| SEV2 | Confirmed compromise contained or major customer-facing degradation | Urgent paging | Regular, set by IC |
| SEV3 | Suspicious activity or limited impact with no active spread | On-call review | Set by incident lead |
| SEV4 | Policy violation or blocked low-impact activity | Ticket/queue | As needed |

When uncertain, begin at the higher plausible severity and downgrade only after evidence supports it.

- **Incident commander (IC):** owns scope, prioritization, approvals, and resolution.
- **Technical lead:** develops and verifies mitigation and recovery steps.
- **Comms lead:** coordinates internal/external updates with legal and customer owners.
- **Scribe:** maintains the UTC timeline, decisions, commands, and evidence references.

For suspected compromise, use a restricted out-of-band channel and assume ordinary email/chat may be visible to the attacker.

## Response phases

1. **Triage:** validate the signal, set severity, identify affected systems/data, assign roles, and start a timeline.
2. **Preserve:** capture volatile state and durable evidence before isolation when safe; use `sec-ops-forensics-collect`.
3. **Contain:** apply the narrowest reversible action that stops current harm; the IC approves production changes.
4. **Scope:** establish entry vector, affected identities/resources, time window, and data impact using trusted logs.
5. **Eradicate:** rebuild from a known-good source or remove the verified cause; rotate every credential the affected system could access.
6. **Recover:** restore from verified backups, return service in phases, and watch for recurrence.
7. **Learn:** meet applicable notification duties, complete a blameless review, and track prevention/detection/response actions.

## Scenario checklists

### Compromised identity or leaked credential

1. Confirm identity type, identifier, owner, and where it may have been exposed.
2. Preserve relevant access logs before revoking access when feasible.
3. Disable or rotate the smallest affected credential/identity; check its active sessions and dependent workloads.
4. Review grants, key creation, data access, and persistence for the incident window.
5. Remove attacker-created access, deploy a least-privilege replacement, and monitor for reuse.

### Compromised host or workload

1. Preserve volatile and disk evidence; do not reboot or terminate without IC approval unless active harm requires it.
2. Isolate through a narrow, documented control that keeps required responder access where safe.
3. Hunt for persistence and lateral movement using trusted logs and a verified copy/image.
4. Rebuild from a known-good image rather than cleaning in place; rotate reachable credentials.
5. Restore traffic only after health and integrity checks pass.

### Data exposure

1. Identify affected records, resource owner, principal, time window, and access path.
2. Preserve audit events and current access policy before removing public or over-broad access.
3. Stop ongoing access through a reviewed reversible change; verify the exposure is closed.
4. Quantify data categories and affected subjects with the data owner; consult counsel on notification obligations.
5. Retain evidence in the approved restricted store and document residual risk.

SIP-specific fraud response belongs to `sec-sip-fraud-respond`; host/cloud evidence handling belongs to `sec-ops-forensics-collect`.