# Incident communications and post-incident review

## Internal updates

Use a consistent restricted-channel update:

```text
[SEV<n>] <incident-id> — <summary>
Status: Investigating | Contained | Eradicating | Recovering | Resolved
IC: <role/name>   Tech lead: <role/name>   Comms: <role/name>
Detected: <UTC time>   Impact: <known facts and unknowns>
Done: <verified actions>
Next: <actions and ETA>
Decisions needed: <none or approval request>
Next update: <UTC time>
```

State facts and unknowns; avoid speculation. Never include credentials, raw evidence, personal data, or bearer credentials in broad channels. Record severity changes explicitly.

## Customer and regulator communications

The comms lead coordinates every external statement with legal, the customer owner, and the applicable regulator/contract owner. Report verified facts, affected data categories, mitigation, recommended customer action, and a monitored contact path; do not disclose raw evidence or blame.

Notification deadlines depend on jurisdiction, data type, role, contract, and awareness time. Record the awareness timestamp, identify the applicable regulator from approved incident configuration, and have counsel confirm the deadline. This skill is operational guidance, not legal advice.

## Post-incident review

Hold the review promptly after resolution, with timing set by severity and organizational policy. Keep the review blameless and fact-based:

1. Reconstruct the timeline and decisions.
2. Identify technical root cause and contributing system conditions.
3. Record what went well and what slowed response.
4. Assign prevention, detection, and response actions, each with one owner and due date.
5. Update the relevant runbooks, detections, and threat model.

Store reports in the approved incident system. Put sensitive evidence and personal data only in the restricted evidence store; link by access-controlled reference.

## Metrics

Track detection time, acknowledgement time, mitigation/recovery time, overdue action items, and repeat incidents. Define measurement boundaries consistently and review trends rather than treating a single target as proof of readiness.