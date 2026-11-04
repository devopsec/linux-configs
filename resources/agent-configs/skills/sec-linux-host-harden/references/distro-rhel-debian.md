# RHEL-family and Debian-family host differences

| Concern | RHEL-family | Debian-family |
|---|---|---|
| Package manager | `dnf` | `apt-get` |
| Security updates | `dnf-automatic` | `unattended-upgrades` |
| Mandatory access control | SELinux | AppArmor |
| Common host firewall | firewalld | nftables or ufw |
| Crypto defaults | `update-crypto-policies` | application/OpenSSL configuration |
| PAM profile tool | `authselect` | `pam-auth-update` |
| Authentication logs | `/var/log/secure` or journald | `/var/log/auth.log` or journald |

Use repositories signed by the distribution or vendor. Pin exact package builds in the deployment's package policy and record their versions; do not pipe remote scripts into a shell.

## RHEL-family

- Enable security-only updates according to the fleet's maintenance policy; query pending advisories before installing.
- Keep SELinux enforcing. Diagnose AVC denials and fix file contexts, service labels, or custom ports; do not use permissive/disabled mode as a routine workaround.
- Let system crypto policy manage system-wide algorithms. Test client compatibility before tightening policy because older TLS peers may fail.
- Remove unused packages/services only after checking the host role and dependencies.

For a custom service port, use an approved runtime port value and the proper SELinux port type. Review generated policy modules line by line before loading; do not ship unreviewed `audit2allow` output.

## Debian-family

- Configure `unattended-upgrades` using managed files and review its dry-run output before enabling unattended installation.
- Keep AppArmor enabled; use complain mode only for short, controlled profile development, then test and return to enforce mode.
- Choose a single host firewall manager; see `sec-linux-hostFirewall-manage` for rule selection and rollback.
- Use the distro's SCAP content/profile where available; benchmark support varies across releases and requires explicit profile discovery.