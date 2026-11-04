# Linux host baseline

## SSH access

Use an early-sorting drop-in and validate effective configuration before reload. Preserve a known working session and a console path for remote hosts.

```text
# /etc/ssh/sshd_config.d/01-hardening.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
LogLevel VERBOSE
```

```bash
sshd -t
sshd -T | grep -Ei 'permitrootlogin|passwordauthentication|maxauthtries'
```

Reload only after validation and explicit approval; unit names can differ by distro. Prefer the platform's managed identity/OS-login solution over hand-maintained user keys where available.

## Kernel and network settings

Place sysctl settings in a dedicated drop-in, review host routing needs first, then validate and apply with the platform owner's approval.

```text
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.sysrq = 0
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
```

Do not disable IPv6 or forwarding where the host role requires it. Loose reverse-path filtering may be necessary on asymmetric or multi-interface routes; document and test the exception. Keep performance tuning separate from security defaults.

Disable unused filesystem modules only after checking image/application dependencies; do not disable `squashfs` when the host depends on it. Make module configuration idempotent.

## Accounts and file permissions

- Use distro-native PAM/profile tooling. Set local-account password quality and lockout policy without changing identity-provider policy blindly.
- Lock unused accounts and ensure service identities use a non-login shell, have only their required data paths, and do not share credentials.
- Keep `/etc/passwd` and `/etc/group` non-world-writable; keep shadow databases readable only by the required privileged group/user.
- Review world-writable files/directories, orphaned files, and SUID/SGID inventory before remediation; do not bulk-delete or chmod results automatically.
- Manage sudo policy through validated drop-ins and `visudo`; never append to the main sudoers file directly.

## Audit and service sandboxing

Use focused audit rules for identity, sudo policy, SSH, privileged module changes, service configuration, and approved application configuration. `-e 2` makes audit rules immutable until reboot; add it only after successful staging validation.

Apply systemd sandbox directives incrementally in the unit source or a reviewed drop-in: `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `ProtectKernelTunables=yes`, and narrowly scoped `ReadWritePaths=`. Test service behavior after each change; `MemoryDenyWriteExecute=yes` can break JIT workloads.