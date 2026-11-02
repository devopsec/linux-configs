---
name: docs-rhel-terminology-translate
description: Translates general Linux concepts, commands, and terminology to Red Hat Enterprise Linux (RHEL) equivalents. Use when users mention non-RHEL terms like apt, dpkg, yum, snap, PPA, Docker, Dockerfile, docker-compose, Docker Hub, ufw, iptables, nftables, AppArmor, Tripwire, OSSEC, syslog, /var/log/auth.log, /etc/init.d/, chkconfig, update-rc.d, ifconfig, netstat, netplan, /etc/network/interfaces, route, Webmin, apache2, a2ensite, a2dissite, Xorg, X11, VNC, vncserver, tigervnc, VirtualBox, VMware, Vagrant, ZFS, btrfs, mdadm, LDAP, Active Directory, NIS, ntpd, ntpdate, timesyncd, Packer, preseed, cloud-init, do-release-upgrade, dist-upgrade, system-upgrade, convert2rhel, migrate, sysctl, performance tuning, sysstat, sar, iostat, Nagios, Prometheus, shell scripts for system configuration, nvidia-driver, ubuntu-drivers, FIPS, lsb_release, sources.list, CentOS, or Ubuntu/Debian-specific commands and file paths, even if they don't explicitly ask about RHEL.
license: Apache-2.0
metadata:
  author: Red Hat
  version: "0.1.0"
---

# RHEL Translator

Translate a user's Linux question into concepts specific to Red Hat Enterprise Linux (RHEL), then answer using RHEL-native tools, paths, and terminology — grounded in the user's actual system when the MCP server for RHEL is available. Use the lookup tables in `references/translation-tables.md` and `references/file-paths-and-terminology.md` as the authoritative source for RHEL equivalents — they contain domain knowledge the agent does not already have (e.g., Red Hat's preference for "web console" over "Cockpit", `authselect` replacing `authconfig`, RHEL file path differences).

## Workflow

### Step 1: Translate and answer

Check the user's message against the translation tables in `references/translation-tables.md` (package management, containers, firewall, security, init system, logging, networking, web/system management, display server, GPU drivers, virtualization, storage, identity, time sync, image building, performance tuning, automation, system identity/updates, crypto/FIPS, upgrades/migration, monitoring) and the path/terminology mappings in `references/file-paths-and-terminology.md`. For each non-RHEL term, explain the RHEL equivalent and why it differs.

Frame translations as "on RHEL, the equivalent is..." with a technical rationale. Do not silently substitute. Do not forbid the non-RHEL term. Do not position RHEL tools as superior. If the user has explicitly stated they are using a non-RHEL tool intentionally (e.g., "I installed Packer because our pipeline requires it"), help them with that tool — do not redirect to the RHEL equivalent. Only translate when the user appears unaware of the RHEL-specific option.

**Example:**

> **User:** "How do I check /var/log/syslog for recent errors?"
>
> On RHEL, the system log is at **/var/log/messages** rather than `/var/log/syslog`. You can also use **journalctl** for richer filtering:
>
> ```
> journalctl -p err --since "1 hour ago"
> ```

**Adapt to the user.** Read expertise and urgency from their language. An experienced sysadmin asking a specific question wants a concise answer, not a tutorial. A user exploring RHEL for the first time benefits from more context. When someone is troubleshooting an outage, lead with the fix.

### Using the MCP server for RHEL

If the **MCP server for RHEL** is connected, use it when it would make the answer more specific — not for every question.

Detection: Identify the MCP server for RHEL by its tools — `get_system_information`, `get_journal_logs`, `list_services`, `get_disk_usage`, and similar RHEL system diagnostic tools. The server name in the client config is user-chosen and may vary.

**Use MCP when:**
- The answer depends on the RHEL version and the version is unknown (call `get_system_information`)
- Knowing actual system state would change the answer — a package is already installed, a service is already running, disk is full
- The user is asking about their specific system, not a general concept

**Skip MCP when:**
- The translation is the same across all supported RHEL versions
- The user is asking a conceptual question ("what's the RHEL equivalent of AppArmor?")

When MCP data is relevant, weave it in naturally: "I can see the httpd service has failed — let me check the logs..."

| User is asking about... | MCP tool |
|------------------------|----------|
| OS version or release | `get_system_information` |
| Services failing or not running | `list_services` or `get_service_status` |
| Errors or logs | `get_journal_logs`, `get_service_logs`, or `read_log_file` |
| Disk space | `get_disk_usage` |
| Slow system or runaway processes | `list_processes` or `get_process_info` |
| Network issues or connectivity | `get_network_interfaces`, `get_listening_ports`, `get_network_connections` |
| CPU or memory pressure | `get_cpu_information`, `get_memory_information` |
| Hardware details | `get_hardware_information` |
| Disk layout or partitions | `list_block_devices` |
| File or directory contents | `list_files` or `list_directories` |

**If MCP is not available** and the answer is version-sensitive, resolve the RHEL version:

1. **Contextual clues:** `yum`, `authconfig`, `ntpd`, or Python 2 references suggest RHEL 7. `dnf module` or standalone `vdo` management suggests RHEL 8. `bootc` or `pasta` suggest RHEL 10.
2. **Ask only when it matters:** If the version is still unknown AND the answer materially differs between versions, ask the user once.
3. **Default + qualify:** If still unknown, assume RHEL 9 and note where the answer would differ for RHEL 8 or 10.

## Response Guidelines

Before returning the response:
- Note RHEL version-specific differences where relevant (RHEL 7 vs 8 vs 9 vs 10).
- Red Hat conscious language guidelines are followed: "allowlist/blocklist" (not whitelist/blacklist), "main" (not master for default branches), "promoted/unpromoted" (not master/slave), gender-neutral "they", "validation" (not "sanity check").
- Product names follow Red Hat conventions — see `references/file-paths-and-terminology.md` for the full Terminology Notes list (e.g., "web console" not "Cockpit", "Apache HTTP Server" not "apache2", "CentOS Linux" not "CentOS").

## Reference Files

- `references/translation-tables.md` — full lookup tables per topic area (package management, containers, firewall, security, networking, etc.), each with key commands and version-specific caveats.
- `references/file-paths-and-terminology.md` — non-RHEL-to-RHEL file path mappings and a glossary of terms the agent is unlikely to get right without this reference.

Load these files as needed rather than memorizing them; they are the authoritative source, not the agent's general Linux knowledge.
