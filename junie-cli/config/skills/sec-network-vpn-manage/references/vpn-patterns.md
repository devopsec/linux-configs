# VPN design patterns

## Choose the least operationally complex option

| Need | Starting point |
|---|---|
| Administrative access to GCP VMs | IAP, if it meets access requirements |
| Small private mesh | WireGuard or a managed mesh approved by the organization |
| Site-to-site with dynamic routing | GCP HA VPN and Cloud Router, after peer ownership and route review |
| Compatibility with existing OpenVPN clients | OpenVPN |

OpenVPN 2.7.8 was the stable version checked 2026-10-28 ([official release history](https://community.openvpn.net/ReleaseHistory)); use the exact approved package build.

## Key and route handling

- Generate distinct keys/PSKs per peer and store private material in Secret Manager or an approved vault.
- Never put private keys/PSKs in skill files, repositories, command arguments, logs, or chat. Deliver client configuration through an approved private channel and revoke/reissue after compromise.
- Define routes from approved CIDRs only. Prefer narrow split routes; a full-tunnel route requires explicit owner approval and DNS/egress planning.
- Enable forwarding/NAT only when the device is an approved gateway; identify the corresponding cloud and host firewall rules.
- For managed meshes, review tags/ACLs and subnet-router approvals before advertising routes.

## Change and verification sequence

1. Confirm purpose, peer ownership, endpoint, routes, address allocation, cryptographic policy, and key lifecycle.
2. Review proposed IaC and firewall changes; stage the tunnel before changing administrative access.
3. Verify peer identity, latest handshake, routes, DNS behavior, and allowed/denied reachability.
4. Keep console access and a rollback path. Test failover for site-to-site tunnels and document peer revocation.

## Troubleshooting

| Symptom | Check |
|---|---|
| No handshake | endpoint, UDP allowance, peer key, clock, and NAT path |
| Tunnel up but no traffic | approved route prefixes, forwarding, cloud/host firewall, return path |
| MTU-related stalls | path MTU and encapsulation overhead, changed only after controlled test |
| DNS leak or resolution failure | split/full tunnel resolver policy and approved DNS route |
| BGP down | peer ASN, tunnel interface addresses, routing policy, and peer-side logs |