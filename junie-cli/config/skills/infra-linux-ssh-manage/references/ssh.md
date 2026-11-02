# OpenSSH server and client operations

## Safe server changes

Before changing access, identify distro/version, effective config, authentication source, network path, and recovery console. Keep the current administrative connection open and test a second new login before closing it.

```bash
sshd -T
sshd -t
systemctl status sshd --no-pager
```

Use an included drop-in when supported by the host; inspect include order because OpenSSH applies the first obtained value for many settings. Validate syntax and effective values, then reload the correct distro service only after a new-session test plan is ready. A listener-port change may also require SELinux port labeling and firewall changes.

## Authentication policy

Set policy according to approved identity and recovery requirements rather than copying a generic hardening block. Common controls include disabling root login, limiting allowed groups, disabling unused forwarding, using public-key authentication where centrally managed, and limiting authentication attempts.

Do not paste a fixed cipher/KEX/MAC list into a host without checking its crypto policy and supported algorithms. On RHEL-family systems, system-wide crypto policies may override or conflict with per-daemon lists. Use `ssh -Q kex`, `ssh -Q cipher`, `ssh -Q mac`, and effective `sshd -T` output for diagnostics.

## Key handling and rotation

Use a supported user key type and a strong passphrase; hardware-backed keys may be preferred for privileged operators. Publish only the public key. Keep private keys in the approved agent or secret manager and never read or print their contents.

For rotation, add the replacement key, verify login in a separate session, then remove the old authorization. Restrict automation keys with a forced command, source restriction, and no forwarding when those controls fit the workflow. Use SSH certificates or centrally managed keys at fleet scale when supported.

## Bastions and client configuration

Prefer `ProxyJump` through a controlled bastion over agent forwarding. Configure identity files, host aliases, `IdentitiesOnly`, and keepalive values in the operator's client config according to local policy. Scope port forwarding with `PermitOpen` and disable it on accounts that do not need it.

```text
Host <managed-host-pattern>
    User <approved-user>
    ProxyJump <approved-bastion-alias>
    IdentitiesOnly yes
    IdentityFile ~/.ssh/<approved-private-key-path>
```

For restricted SFTP, use `internal-sftp` where appropriate and ensure chroot directories are root-owned and not writable by the user. Do not expose a bastion or tunnel endpoint beyond the approved network scope.

## GCP access boundary

For Compute Engine, prefer OS Login and IAP SSH when enabled by the organization. Confirm IAM roles, VM metadata policy, and the approved IAP ingress rule. Do not hard-code source ranges or VM targets; obtain them from current provider documentation and the project network policy.

## Troubleshooting

| Symptom | Check |
|---|---|
| Public-key login denied | key fingerprint, account state, authorized-key ownership/mode, effective allow rules, server journal |
| Change ignored | included files, lexical order, first-value behavior, `sshd -T` |
| Too many authentication failures | agent-loaded identities; use `IdentitiesOnly` and the intended key |
| Host key changed | verify through an independent trusted channel before updating known-hosts |
| RHEL port change denied | SELinux audit messages and SSH port type, not a global SELinux disable |