---
name: sec-ops-incident-respond
description: "Coordinate security incident triage, severity, roles, escalation, containment decisions, stakeholder communications, and post-incident reviews. Use when a task mentions a breach, compromise, incident commander, war room, escalation, incident update, notification deadline, post-mortem, PIR, MTTR, or tabletop exercise."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/operations/incident-response
    - compliance/continuity/incident-management
  license: MIT
---

# Security incident response

Coordinate response from declaration through recovery and lessons learned. Preserve evidence before containment where feasible; the incident commander (IC) approves production actions.

## Triggers

- Suspected breach, compromised identity/host, data exposure, or active abuse
- Incident severity, IC/war room, escalation, stakeholder updates, PIR, or tabletop

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/incident-response.toml" exists
  REFERENCE "~/.junie/custom/configs/security/incident-response.toml"
ELSE
  REFERENCE "assets/site-config.example.toml"
  ask the user for missing incident-specific targets, evidence destination, SIP controls, or applicable regulator
IF task involves triage, severity, roles, escalation, or recovery planning
  REFERENCE "references/response-playbooks.md"
IF task involves notifications, status updates, regulatory review, or post-incident metrics
  REFERENCE "references/comms-postmortem.md"
IF task involves host evidence collection or cloud snapshots
  REFERENCE skill "sec-ops-forensics-collect"
IF task involves SIP fraud or SIP-edge containment
  REFERENCE skill "sec-sip-fraud-respond"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Declare the incident, assign an IC and technical/comms leads, set severity, open a restricted channel, and start a UTC timeline.
2. Preserve volatile and durable evidence before containment when safe; record any action that changes the environment.
3. Contain with the narrowest reversible action; require explicit approval for destructive or irreversible changes.
4. Scope affected identities, systems, data, and time window; eradicate by rebuilding or rotating affected credentials rather than making undocumented ad hoc changes.
5. Recover from verified sources, monitor for recurrence, meet applicable notification obligations with legal, and track a blameless PIR to closure.

## Safety

- Treat evidence and incident communications as sensitive; never paste raw evidence, credentials, or personal data into chat or an unrestricted ticket.
- Do not shut down a suspect system before volatility capture unless active harm makes it necessary; document why.
- Read applicable regulator and site settings from the configured TOML or ask the user; do not infer them.

## Related skills

- Evidence collection and chain of custody → `sec-ops-forensics-collect`
- SIP fraud response → `sec-sip-fraud-respond`
- Runbook authoring → `docs-ops-runbook-create`
- Framework-specific reporting obligations → `sec-compliance-framework-assess`
