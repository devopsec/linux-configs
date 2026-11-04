---
name: infra-linux-ssh-manage
description: "Configure and troubleshoot OpenSSH clients and servers, key authentication, restricted accounts, and bastion access. Use when a task mentions sshd_config, authorized_keys, ProxyJump, key rotation, SSH port changes, or SSH login failures."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/servers/ssh-configuration]
  license: MIT
---

# Linux OpenSSH administration

## Triggers

- Harden or troubleshoot `sshd`, client config, SSH keys, or restricted access.
- Configure a bastion, `ProxyJump`, port forwarding, or host/user certificate flow.
- Rotate keys or change an SSH listener without losing administrative access.

## Load order (SAD KITTI)

```sadkitti
REQUIRE host access policy and project AGENTS.md if present
REFERENCE "references/ssh.md"
IF target is a Google Compute Engine VM
  REFERENCE current OS Login and IAP SSH documentation if those features are in use
CACHE only the applicable client, server, or key guidance
```

## Workflow

1. Identify the SSH implementation/version, distro policy, access path, and recovery console or second session.
2. Capture effective settings with `sshd -T` and inspect relevant files without exposing private key or credential contents.
3. Make the smallest change in an included drop-in; preserve the existing identity provider and approved crypto policy.
4. Validate with `sshd -t`, inspect effective values, and test a new connection before closing the working session.
5. For key rotation, add and verify the replacement first; remove the old key only after successful authentication.

## Safety

- Keep a working session open during server, PAM, firewall, or listener changes; ask before applying changes on production hosts.
- Never read, log, or transmit private keys. Verify a changed host key through an independent trusted channel before accepting it.
- Do not paste a hard-coded algorithm list; use the distro crypto policy and confirm supported algorithms on the actual host.

## Related skills

- Account, sudo, and OS Login identity → `infra-linux-users-manage`
- SSH firewall exposure → `sec-network-perimeter-manage`
- TLS policy and certificates → `sec-network-tls-manage`
- GCP VM access → `infra-gcp-compute-manage`

## References

- [references/ssh.md](references/ssh.md) — safe change procedure, keys, bastions, forwarding, and troubleshooting.
