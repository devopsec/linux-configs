# Claude specifics — Linux host firewall

- Never mix firewalld-managed state with unmanaged nftables/iptables rules.
- Add required access before tightening policy, then validate allowed and denied paths.
- Treat skipped/unreadable policy as unknown, not compliant.