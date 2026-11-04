# Linux package and repository administration

## Identify the host and package source

```bash
cat /etc/os-release
apt-cache policy <package>
dnf info <package>
rpm -qf <path>
dpkg -S <path>
```

Use `apt-get` for scripts and automation; use `dnf` on supported RHEL-family hosts. Package names and plugin availability differ by distribution release; inspect the configured repositories rather than assuming a package version or stream.

| Task | Debian-family | RHEL-family |
|---|---|---|
| Refresh metadata | `apt-get update` | `dnf makecache` |
| Install package | `apt-get install <package>` | `dnf install <package>` |
| Query versions | `apt-cache policy <package>` | `dnf list --showduplicates <package>` |
| Package file list | `dpkg -L <package>` | `rpm -ql <package>` |
| Package history | `/var/log/apt/history.log` | `dnf history` |

## Third-party repositories

Prefer distro repositories. If a vendor repository is required:

1. Confirm the publisher and supported distribution/release.
2. Obtain the signing key from the publisher's official channel and verify its fingerprint independently.
3. Configure the repository with scoped key trust (`Signed-By` on APT, GPG checking on RPM repositories).
4. Preview the package candidate and dependencies before installing.
5. Record the repository owner and removal/rollback steps.

Never pipe a downloaded installer or key into a shell or trust store. If installing a standalone binary is unavoidable, pin the release and verify the publisher's checksum or signature before installation.

## Updates, holds, and removals

Apply security updates through the host's supported patch workflow. For production services, stage one host, drain it where necessary, verify service health, then continue the rollout.

Use exact package versions from the approved repository when a pin is required. Record the reason, owner, and review date; keep security updates in scope. Preview `apt-get` removal/purge or `dnf remove` dependency impact first. Purging package configuration and removing dependencies are destructive to local state.

Automatic updates should match the system's restart and maintenance policy. Confirm whether kernel or library updates require a reboot/service restart and review package-generated config files such as `.dpkg-dist` or `.rpmnew`.

## Troubleshooting

| Symptom | First checks |
|---|---|
| Missing key/signature error | key fingerprint, scoped keyring path, repo metadata signature settings |
| Dependency conflict | held packages, enabled repositories, solver plan; preview repair commands |
| Package file changed unexpectedly | package verification and local config-file deltas |
| Service still runs old code | installed package version, restart requirement, active executable path |
| Disk full during update | filesystem/inode use and package cache; preserve logs and local config |

Do not repair package conflicts by disabling signature checks or enabling arbitrary repositories.