---
name: infra-linux-users-manage
description: "Manage Linux users, groups, service accounts, sudo policy, PAM, SSSD, and access reviews on Debian-family and RHEL-family systems. Use when a task mentions useradd, group membership, sudoers, visudo, faillock, SSSD, service identities, or account deprovisioning."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/servers/user-management]
  license: MIT
---

# Linux user and privilege management

## Triggers

- Create or change a human account, service identity, group, or login shell.
- Scope sudo access, review PAM/faillock behavior, or connect a host to SSSD/AD.
- Lock, expire, or deprovision an account while preserving required evidence and data.

## Load order (SAD KITTI)

```sadkitti
REQUIRE host access policy and project AGENTS.md if present
REFERENCE "references/users.md"
IF the task is a Google Compute Engine VM with centralized login
  REFERENCE the current OS Login documentation and inspect existing IAM policy read-only
CACHE only the applicable account, sudo, or PAM guidance
```

## Workflow

1. Confirm host/distro, account purpose, approval, identity source, required groups, expiry, and data-retention needs.
2. Inspect existing identity and privileges with `getent`, `id`, `sudo -l`, and the active NSS/PAM configuration.
3. Prefer centralized identity and non-login service accounts; make the smallest change and preserve unrelated supplementary groups.
4. Validate sudo files using `visudo -cf <file>` before installation; test a new login/session and the exact authorized command.
5. For offboarding, inventory processes, scheduled jobs, keys, and owned data before locking or removing the account.

## Safety

- Never request, print, or store passwords, private keys, or shadow hashes; use an approved secret channel for bootstrap credentials.
- No `NOPASSWD: ALL`, shell/editor escape commands, or broad wildcard grants.
- `userdel -r`, home removal, process termination, and group changes require an explicit impact review and confirmation.

## Related skills

- SSH key restrictions and server access → `infra-linux-ssh-manage`
- Service units and `User=`/`Group=` → `infra-linux-systemd-manage`
- Host hardening and compliance baselines → `sec-linux-host-harden`
- GCP identity and OS Login → `infra-gcp-compute-manage`

## References

- [references/users.md](references/users.md) — service/human accounts, sudo, PAM, SSSD, and access auditing.
