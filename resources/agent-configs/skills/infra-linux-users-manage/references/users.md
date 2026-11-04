# Linux users, service identities, and sudo

## Identity and distribution notes

Check the active NSS/PAM configuration before assuming local files are authoritative. Debian-family systems commonly grant administrator access through `sudo`; RHEL-family systems commonly use `wheel`. Use the host's existing centralized identity provider when one is configured.

```bash
getent passwd <user>
id <user>
getent group <group>
sudo -l -U <user>
```

## Service accounts

Prefer package-managed identities or systemd-managed dynamic identities when appropriate. For a persistent local identity, create a non-login account with only the required data directory and group membership; do not create a human password for a daemon account.

```bash
useradd --system --no-create-home --home-dir /var/lib/<service> \
  --shell /usr/sbin/nologin --user-group --comment '<service> service' <service>
```

Use systemd `StateDirectory=`, `RuntimeDirectory=`, or `LogsDirectory=` when suitable. Do not change an existing package-created user or stable UID without checking data ownership and service expectations.

## Human accounts and groups

Before creating or changing a user, confirm the approved identity source, purpose, expiry, groups, and login method. Use `usermod -aG <group> <user>` to append supplementary membership; omitting `-a` replaces the existing group list. Check changes in a new session.

Locking a password does not necessarily disable SSH key access. For a full access revocation, coordinate account lock/expiry, centralized identity, SSH keys/certificates, active sessions, scheduled tasks, and owned data.

## Least-privilege sudo

Edit with `visudo -f /etc/sudoers.d/<name>` or validate a staged file with `visudo -cf <file>` before installing it with restrictive owner/mode. Use full command paths and constrain arguments to the specific operation.

```text
Cmnd_Alias SERVICE_READ = /usr/bin/systemctl status <unit>.service, \
                          /usr/bin/journalctl -u <unit>.service
%<approved-group> ALL=(root) SERVICE_READ
```

Avoid `NOPASSWD: ALL`, shells, interpreters, editors, wildcard write commands, and permission to modify arbitrary systemd units. Confirm effective access with `sudo -l -U <user>`.

## PAM, faillock, and SSSD

- On RHEL-family systems, use the supported `authselect` profile and features; do not hand-edit generated PAM files.
- On Debian-family systems, use the distribution's PAM profile tooling and maintain a console/recovery path while testing authentication changes.
- Check `faillock --user <user>` before resetting a lock; review policy and audit requirements.
- For SSSD/AD, verify domain discovery, join authorization, DNS/time prerequisites, and permitted groups before enrolling a host. Never pass a join password on the command line.

## Access review and offboarding

Review human UID ranges, privileged groups, sudo rules, inactive accounts, SSH keys, service owners, and centralized access policy. For offboarding, first inventory processes, cron/systemd timers, credentials, owned files, and retention obligations. Disable access and preserve data until its owner approves deletion; `userdel -r` is destructive.

Do not dump `/etc/shadow`, private keys, or password material into output. Report usernames, group memberships, file modes, and relevant policy paths only.