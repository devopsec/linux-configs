# Linux host firewalls

## Choose one manager

| Host | Typical choice | Guardrail |
|---|---|---|
| RHEL-family | firewalld | Use its zones and persistent configuration; do not mix unmanaged nftables rules. |
| Debian server/edge | nftables | Keep a reviewed ruleset and timed rollback for remote changes. |
| Small Debian/Ubuntu host | ufw | Confirm the management allow rule before enabling. |
| Legacy host | iptables | Establish whether rules are managed by firewalld, Docker, or another service first. |

Run `bash scripts/firewall-audit.sh -q` for a read-only local summary. Full output may disclose network topology; restrict storage and redact it before sharing.

## Safe change pattern

1. Capture current active and persistent state, management path, interfaces, and approved flows.
2. Add required access before restricting existing access. Use temporary firewalld rules where appropriate or validate nftables syntax with `nft -c -f`.
3. Schedule a timed rollback before remote changes. Never use `nft flush ruleset` or `ufw reset` on a remote host without a confirmed console path and approved rollback.
4. Apply only after approval; verify both allowed and denied paths, service behavior, and persistence.
5. Update the maintained configuration source; do not leave undocumented console-only changes.

## Service-specific considerations

- Restrict SSH, database, RPC, and administrative interfaces to the approved management range; obtain that range from user/config input.
- SIP signalling sources and media port bounds belong to `sec-sip-exposure-manage`; do not copy sample CIDRs or RTP ranges.
- Docker-published traffic may bypass simple INPUT-chain assumptions; bind services to private interfaces or apply an explicit container-forward policy.
- Do not mix raw nftables/iptables commands with firewalld-managed state; reloads can remove unmanaged rules.

## Audit interpretation

The bundled script checks the local manager, default inbound policy, listeners, SIP helper module, and conntrack pressure. A `WARN` on a public bind means verify source restrictions in the firewall; it is not by itself proof that the port is reachable. A skipped or unreadable policy is unknown, not a pass.