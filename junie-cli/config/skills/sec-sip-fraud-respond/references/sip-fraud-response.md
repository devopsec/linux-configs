# SIP fraud and abuse response

## Signals and scope

Investigate deviations from the approved calling baseline, including:

- Unexpected outbound calls or cost spikes, especially to restricted/high-cost destinations
- A burst of failed registrations or INVITEs, new source identities, or unusual client identifiers
- New or elevated rate-limit/ban events and unexplained routing changes
- CDR differences in source account, destination prefix, duration, and time-of-day patterns

Read the affected SIP target, htable name, CDR source, RTP range, and any applicable regulator from `~/.junie/custom/configs/security/incident-response.toml`. If a required value is missing, ask the user; do not guess a target, table, range, or jurisdiction.

## Preserve and contain

1. Assign an IC and establish the UTC window, affected tenant/trunk, business baseline, and current billing impact.
2. Preserve relevant signaling metadata, CDR exports, and audit logs before changing routes or accounts when safe. Avoid recording RTP/media unless separately authorized and necessary.
3. For active fraud, use the narrowest reversible edge, identity, or route control approved by the IC. Read source ranges and target tags from the approved config and verify the current rule set before changing it.
4. For a Kamailio htable action, confirm the configured table and key semantics with the platform owner before issuing an RPC change. Record the command, approver, and expiry/review time.
5. Ask the carrier to suspend or limit the affected route when edge controls cannot stop billing quickly enough.

An example of a runtime-only host firewall block (substitute only an approved source range):

```bash
firewall-cmd --add-rich-rule="rule family=\"ipv4\" source address=\"${SOURCE_CIDR}\" drop"
```

For cloud controls, use reviewed infrastructure as code when possible. If the incident requires an emergency rule, have an authorized operator confirm network, source range, protocol/ports, target, priority, and rollback before applying it.

## Investigate and recover

- Compare CDRs against a recent normal baseline by account, destination, time window, and call outcome.
- Correlate signaling logs with authentication outcomes, source metadata, rate-limit events, and change/audit records.
- Keep network/media ranges and destination prefixes from the approved site configuration; do not broaden analysis to unrelated tenants.
- Rotate abused credentials, validate dial-plan restrictions, and review rate limits after evidence is preserved.
- Test approved inbound/outbound calls and billing status before removing temporary controls; the IC and carrier approve restoration.

Treat CDRs, phone numbers, and signaling captures as sensitive personal data. Restrict storage and sharing, document applicable retention, and ask counsel to confirm notification obligations for the configured regulator.