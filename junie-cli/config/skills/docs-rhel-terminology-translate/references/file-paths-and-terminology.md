## File Path Translations

| Non-RHEL path | RHEL path | Purpose |
|--------------|-----------|---------|
| /etc/apache2/ | /etc/httpd/ | Apache HTTP Server configuration |
| /etc/apache2/sites-available/ | /etc/httpd/conf.d/ | Virtual host configs |
| /var/log/syslog | /var/log/messages | System log |
| /var/log/auth.log | /var/log/secure | Authentication log |
| /etc/network/interfaces | /etc/NetworkManager/system-connections/*.nmconnection | Per-connection network configuration (keyfile format) |
| /etc/apt/sources.list | /etc/yum.repos.d/ | Repository configuration |
| /etc/default/ | /etc/sysconfig/ | Service defaults/environment |
| /etc/apparmor.d/ | /etc/selinux/ | MAC policy configuration |
| /etc/ntp.conf | /etc/chrony.conf | Time synchronization |
| a2ensite / a2dissite | Add .conf to /etc/httpd/conf.d/ | Enable/disable Apache sites |
| /etc/sysconfig/network-scripts/ | /etc/NetworkManager/system-connections/ | RHEL 10: ifcfg removed; keyfile format only |
| /etc/pki/tls/certs/ca-bundle.crt | /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem | RHEL 10: consumers should use the ca-trust path; the old tls/certs location is no longer recommended |
| /etc/containers/storage.conf | /usr/share/containers/storage.conf | RHEL 10: container storage config moved |

---

## Terminology Notes

These are terms the agent is unlikely to get right without this reference:

- **MCP server for RHEL** — the marketing-approved product name. The upstream package and binary are `linux-mcp-server`.
- **web console** — preferred over "Cockpit" in user-facing text. "Cockpit" is the upstream project name and appears in package names (`cockpit`, `cockpit.socket`), but Red Hat docs use "the web console."
- **Apache HTTP Server** — the proper branded name. Package/service is `httpd`.
- **Kickstart** — always uppercase (proper name).
- **TuneD** — capitalized as shown; a TuneD profile is a directory containing `tuned.conf` and optional support files (e.g., helper scripts).
- **NetworkManager** — CamelCase, no spaces.
- **CentOS Linux** — not "CentOS" alone. Distinguish from CentOS Stream.
- **Hybrid Cloud Console** — correct name for console.redhat.com.
- **SCAP / OpenSCAP** — SCAP is the standard; OpenSCAP is the tool.
- **cgroups** — lowercase; standard abbreviation for control groups.
- **huge pages** — two words, lowercase.
- `sudo` — use code font for the command.
- **systemd** — lowercase in general text. `systemd-journald` = service; journald = common name; journal = log store.
- **SELinux modes** — enforcing, permissive, disabled (lowercase in running text).
- **Python** — use `python3` explicitly on RHEL. `python` is not in PATH by default on RHEL 8.
- **Java** — RHEL uses the naming pattern `java-VERSION-openjdk-devel` (e.g., `java-17-openjdk-devel`, `java-21-openjdk-devel`), not `openjdk-VERSION-jdk` or `default-jdk`. Multiple versions may be available via Application Streams.
- **nano** — not installed by default; `dnf install nano`.
- **Scheduled tasks** — `cron` works but systemd timers are the modern RHEL approach.
- **Ansible Playbook / Role** — capitalize when preceded by "Ansible" (e.g., "Ansible Playbook"); lowercase otherwise ("a playbook").
- **errata** — Red Hat term for update advisories. RHSA = security, RHBA = bugfix, RHEA = enhancement. Preferred over "patch" or "update" when referring to a specific advisory.
- **PCP** — Performance Co-Pilot. Preferred over generic "monitoring tools" on RHEL.
- **Network-Bound Disk Encryption (NBDE)** — hyphenate "Network-Bound"; uppercase.
- **Relax-and-Recover (ReaR)** — disaster recovery tool; `rear mkrescue`, `rear mkbackup`, `rear recover`.
- **Red Hat Lightspeed** — the current name for the proactive monitoring and AI service platform, formerly known as Red Hat Insights. The client package is still `insights-client`.
- **EEVDF scheduler** — replaces CFS in RHEL 10 kernel. Docs refer to the class as "fair scheduler" but the implementation as CFS (RHEL 9) or EEVDF (RHEL 10).
- **XCCDF** — eXtensible Configuration Checklist Description Format. The format used by OpenSCAP profiles.
- **data stream file** — the `-ds.xml` file containing SCAP content (e.g., `ssg-rhel9-ds.xml`). SCAP Security Guide ships these in `/usr/share/xml/scap/ssg/content/`.
