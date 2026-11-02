## Translation Tables

### Package Management

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| apt, apt-get, dpkg | **dnf** | `dnf install`, `dnf search`, `dnf update` |
| yum | **dnf** | yum symlinks to dnf on RHEL 8+; always prefer dnf |
| PPA, third-party repo | **RHEL Extensions repo** or **dnf config-manager --add-repo** | `subscription-manager repos --enable` for Red Hat content; `dnf config-manager` for repos outside `redhat.repo` |
| dpkg -l | **rpm -qa** or **dnf list installed** | |
| apt-cache search | **dnf search** | |
| "security patch" or "update" | **errata** (RHSA/RHBA/RHEA) | RHSA = security advisory, RHBA = bugfix, RHEA = enhancement |
| Flatpak / snap (desktop apps) | **Flatpak** or **RPM** | Flatpak is available on RHEL; snap is not |

Key commands: `dnf install`, `dnf search`, `dnf info`, `dnf update`, `dnf remove`, `rpm -qa`, `rpm -qi`, `subscription-manager repos --list`, `dnf updateinfo list --updates --security`

Package manager by version: RHEL 7 uses **yum**. RHEL 8–10 use **dnf** (yum symlinks to dnf on RHEL 8+). Even when yum directories appear in the filesystem, standardize to dnf.

**Application Streams:** RHEL delivers multiple versions of user-space software (Python, PHP, Node.js, Ruby, PostgreSQL, etc.) through Application Streams. On RHEL 8–9, additional versions are available as **modules** — use `dnf module list` to see available streams, `dnf module enable <name>:<stream>` to activate a version, and `dnf module reset <name>` to return to the default. Only one stream per module can be active at a time. To switch to a later stream: `dnf module switch-to <name>:<stream>`. On RHEL 10, modularity is deprecated and no modular content is shipped; all Application Stream versions are delivered as standard RPMs installable via `dnf install`. When a user asks "how do I install PHP 8.2?" or "how do I get a newer version of Node.js?", Application Streams are the answer on RHEL — not PPAs or third-party repos.

### Containers

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| Docker, docker run | **Podman** | Daemonless, rootless by default, CLI-compatible |
| Dockerfile | **Containerfile** | Podman reads both; Containerfile is the preferred name |
| docker build | **podman build** or **Buildah** | Buildah for advanced image building |
| docker push/pull | **podman push/pull** or **Skopeo** | Skopeo for inspection and copying without a full pull |
| Docker Hub | **registry.redhat.io** | Red Hat container catalog for certified images |
| Docker Desktop | **Podman Desktop** | Available on macOS, Windows, Linux |

Explain to users: "On RHEL, Podman is the standard container engine. It's command-compatible with Docker — you can generally replace `docker` with `podman` in your commands. It runs without a daemon and supports rootless containers out of the box."

RHEL 7 included Docker via extras; RHEL 8+ does not ship Docker — Podman, Buildah, and Skopeo are the standard tools.

**No docker-compose equivalent on RHEL.** `podman-compose` is not shipped or supported by Red Hat. For multi-container workloads, RHEL offers `podman play kube` (Kubernetes YAML) and Quadlet (systemd `.container` files), but neither uses docker-compose syntax.

Container runtime changes across versions: On RHEL 9 (GA), `crun` became the default runtime and `cgroups v2` became the default cgroup version. On RHEL 9.5 (Podman 5.0), `runc`, `cgroups v1` (rootless), and `slirp4netns` were formally deprecated. On RHEL 10, `runc` removed (use `crun`); CNI network stack removed (use `netavark`); `cgroups v1` removed (`cgroups v2` only); `slirp4netns` deprecated (use `pasta`, which is the default for rootless networking).

| Feature | Docker | Podman |
|---------|--------|--------|
| Daemon | Requires dockerd | Daemonless |
| Root | Runs as root by default | Rootless by default |
| Socket | /var/run/docker.sock | `/var/run/podman/podman.sock` (root) or `/run/user/$ID/podman/podman.sock` (rootless) via `podman.socket` |
| Pods | Not native (Swarm/K8s) | Native pod support (Kubernetes-style) |
| Systemd integration | Requires config | Quadlet |
| Auto-update | Not built-in | `podman auto-update` with systemd |

RHEL-specific workflow — running containers as systemd services:

- Use **Quadlet** — place a `.container` file in `/etc/containers/systemd/` (root) or `~/.config/containers/systemd/` (rootless), then `systemctl --user daemon-reload && systemctl --user start <name>`. (`podman generate systemd` is deprecated and should not be used.)

### Firewall

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| iptables (direct rules) | **firewalld** / **firewall-cmd** | Default since RHEL 7 |
| ufw | **firewall-cmd** | |
| nftables (direct) | **firewalld** | Uses nftables backend on RHEL 9+ |

Key commands: `firewall-cmd --list-all`, `firewall-cmd --add-service=http --permanent`, `firewall-cmd --add-port=8080/tcp --permanent`, `firewall-cmd --reload`

Backend: iptables on RHEL 7–8, nftables on RHEL 9+. Users interact with `firewall-cmd` regardless; the backend is transparent. `iptables` is deprecated in RHEL 9; on RHEL 10, the iptables kernel modules moved to `kernel-modules-extra` (not loaded by default).

### Security

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| AppArmor | **SELinux** | RHEL's mandatory access control system |
| aa-status | **sestatus** or **getenforce** | |
| Security scanning / CIS benchmarks / STIG / compliance / hardening | **OpenSCAP** (`oscap`) | SCAP is the standard; OpenSCAP is the tool |
| Tripwire, OSSEC | **AIDE** | File integrity monitoring; `aide --check` |
| Application allowlisting | **fapolicyd** | Controls which binaries can execute |
| System auditing | **auditd** | `ausearch`, `aureport`; audit rules in `/etc/audit/` |
| Automated disk unlock | **Clevis/Tang (NBDE)** | Network-Bound Disk Encryption for LUKS volumes |
| Attestation | **Keylime** | TPM-based system integrity verification (RHEL 9+) |

Key commands: `getenforce`, `sestatus`, `semanage`, `restorecon`, `audit2why`, `audit2allow`, `oscap xccdf eval`, `aide --check`, `fapolicyd-cli`

SELinux modes: enforcing, permissive, disabled (lowercase in general text). Note: `policycoreutils-python` (RHEL 7) was renamed to `policycoreutils-python-utils` on RHEL 8+ — a common source of "package not found" errors during migration.

### Init System & Services

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| service start/stop | **systemctl start/stop** | RHEL uses systemd exclusively |
| /etc/init.d/ scripts | **systemctl** / **systemd unit files** | |
| chkconfig, update-rc.d | **systemctl enable/disable** | |

Key commands: `systemctl status <svc>`, `systemctl start/stop/restart <svc>`, `systemctl enable --now <svc>`, `systemctl list-units --type=service`, `journalctl -u <svc>`

Terminology: lowercase "systemd" in general text. `systemd-journald` is the service name, journald is the common usage name, the journal is the log store.

### Logging

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| /var/log/syslog | **/var/log/messages** or **journalctl** | RHEL uses `/var/log/messages`, not syslog |
| /var/log/auth.log | **/var/log/secure** | Authentication log |
| tail -f /var/log/... | **journalctl -f** | For systemd-managed services |
| dmesg | **dmesg** or **journalctl -k** | Both work |

Key commands: `journalctl -xe`, `journalctl -u <service> --since "1 hour ago"`, `journalctl -p err`, `journalctl -b`

### Networking

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| ifconfig | **ip addr** or **nmcli** | ifconfig is deprecated |
| /etc/network/interfaces | **nmcli** / **nmstatectl** / keyfiles in `/etc/NetworkManager/system-connections/` | |
| netplan | **nmstatectl** (declarative YAML, closest match) or **nmcli** (imperative) | |
| netstat | **ss** | `ss -tulnp` replaces `netstat -tulnp` |
| route | **ip route** | |

Key commands: `nmcli device status`, `nmcli connection show`, `nmcli connection modify`, `nmstatectl show`, `nmstatectl apply`, `ip addr show`, `ss -tulnp`

`ifconfig`, `netstat`, `route`, `arp` are in the `net-tools` package — not installed by default on RHEL 8+.

Networking changes across versions: On RHEL 9, `teamd`/`libteam` (network teaming) were deprecated and keyfile became the default NetworkManager connection format (ifcfg deprecated but still functional). On RHEL 10, these deprecations became removals: `teamd`/`libteam` removed (use bonding instead); ifcfg format removed (keyfile only, in `/etc/NetworkManager/system-connections/`); `dhclient` removed (NetworkManager internal DHCP is the default).

### Web & System Management

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| Webmin | **the RHEL web console** | Based on Cockpit; prefer "web console" in user-facing text |
| apache2 | **httpd** | Package and service name is `httpd`; proper name is "Apache HTTP Server" |
| /etc/apache2/ | **/etc/httpd/** | |

Web console setup:
```bash
sudo dnf install cockpit
sudo systemctl enable --now cockpit.socket
sudo firewall-cmd --add-service=cockpit --permanent
sudo firewall-cmd --reload
```
Access at `https://<hostname>:9090`. "Cockpit" appears in package/service names, but use "the web console" when describing the feature to users.

### Display Server

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| Xorg / X11 (as default) | **Wayland** (RHEL 9+) | Wayland is the default GNOME session on RHEL 9 |
| "X11 forwarding over SSH" | **X11 forwarding, XWayland, or waypipe** | All versions; RHEL 10 also adds `waypipe` for Wayland-native apps |
| VNC / vncserver / tigervnc | **GNOME Remote Desktop (RDP)** | RHEL 10 removes TigerVNC; use `gnome-remote-desktop` (RDP) |

RHEL 8 uses X11 as the default GNOME session. RHEL 9 switched to **Wayland** as the default; X11 is still available as "GNOME on Xorg" on the GDM login screen. RHEL 10 removes the Xorg server entirely — X11 applications still work through **XWayland** (an X server running on top of Wayland), and X11 forwarding over SSH still works (the Xorg server is not required for forwarding). Users can check the active session with `echo $XDG_SESSION_TYPE`. To force X11 system-wide on RHEL 9, set `WaylandEnable=false` in `/etc/gdm/custom.conf`.

**Remote desktop:** RHEL 9 and earlier used `tigervnc-server` for remote graphical access. RHEL 10 removes all TigerVNC packages and replaces VNC with **RDP** via the `gnome-remote-desktop` package. Desktop sharing is configured through GNOME Settings (System > Remote Desktop). Headless sessions require TLS certificate setup and use the `grdctl` CLI — see "Remotely Accessing the Desktop" in the RHEL 10 "Administering RHEL by using the GNOME desktop environment" guide. The RHEL installer also switched from `inst.vnc` to `inst.rdp`. `gnome-connections` remains available as a VNC client for connecting to older systems.

### GPU and AI Accelerator Drivers

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| `ubuntu-drivers`, `apt install nvidia-driver` | **rhel-drivers** (RHEL 10.1+), **RHEL repos** (RHEL 9.8+), or manual vendor repo setup (RHEL 9.0–9.7) | RHEL has its own driver delivery mechanism |

**RHEL 10.1+:** The `rhel-drivers` command provides single-command installation for NVIDIA and AMD data center AI accelerator drivers, built and signed by Red Hat from the Extensions and Supplementary repositories:
```bash
sudo dnf install rhel-drivers
sudo rhel-drivers install nvidia    # NVIDIA kernel + user mode drivers
sudo rhel-drivers install amdgpu    # AMD kernel mode driver
sudo reboot
```
For AMD user-mode drivers (ROCm), install separately: `sudo dnf install rocm rocm-devel`. Intel NPU device drivers are included in the BaseOS kernel; install the firmware package from BaseOS repos.

**RHEL 9.8+:** No `rhel-drivers` command. GPU drivers are available from RHEL repositories.

**RHEL 9.0–9.7:** No `rhel-drivers` command. GPU driver installation requires manual configuration of vendor repositories.

### Virtualization

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| VirtualBox | **KVM + libvirt** | RHEL's native hypervisor stack |
| VMware (as default hypervisor) | **KVM + QEMU + libvirt** | Managed via `virsh`, `virt-install`, or the web console |
| virt-manager (GUI) | **web console** or **virsh** | RHEL 9+ deprecates virt-manager; use the web console |
| Vagrant | **virt-install** or **Image Builder** | For VM provisioning |

Key commands: `virsh list --all`, `virsh start <vm>`, `virt-install`, `virsh console <vm>`

RHEL ships `qemu-kvm` (a subset of upstream QEMU) plus libvirt. The web console provides graphical VM management.

### Storage

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| ZFS | **XFS** + (**LVM** or **Stratis**) | ZFS is not available on RHEL; XFS is the default filesystem, with LVM or Stratis for volume management |
| btrfs | **XFS** + (**LVM** or **Stratis**) | btrfs is not supported on RHEL; XFS is the default filesystem, with LVM or Stratis for volume management |
| mdadm (software RAID) | **LVM** or **mdadm** | LVM supports mirroring/striping natively |
| Simple volume management | **Stratis** | Modern, simplified storage management on RHEL |
| Deduplication/compression | **VDO** (via LVM) | LVM-integrated dedup and compression |
| Disk encryption | **LUKS** | `cryptsetup` for setup; Clevis/Tang (NBDE) for automated network-bound decryption |

Key commands: `lsblk`, `df -h`, `vgdisplay`, `lvdisplay`, `stratis pool list`, `stratis filesystem list`

XFS is the default filesystem. Stratis provides pool-based management (similar in concept to ZFS/btrfs). VDO provides dedup/compression via LVM (`lvcreate --type vdo`). LVM-VDO is available on RHEL 8+; on RHEL 9, the standalone Python-based VDO management tools were removed — LVM-VDO is the only supported interface.

### Identity & Authentication

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| LDAP server setup | **IdM** (Identity Management) | Based on FreeIPA; bundles LDAP, Kerberos, DNS, CA |
| Active Directory integration | **SSSD** + **realm join** | `realm join` for AD enrollment; SSSD handles auth |
| PAM configuration | **authselect** | Replaces authconfig on RHEL 8+ |
| NIS/NIS+ | **IdM** or **SSSD** | NIS is deprecated; migrate to IdM/SSSD |

Key commands: `realm join <domain>`, `realm list`, `authselect current`, `authselect select sssd`, `ipa user-find`

### Time Synchronization

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| ntp, ntpd, ntp.conf | **chrony** / **chronyd** / **chrony.conf** | Default NTP implementation on RHEL 7+ |
| ntpdate | **chronyd -q** / **chronyd -Q** | ntpdate is missing on RHEL 8+ |
| timesyncd | **chronyd** | systemd-timesyncd is not available on RHEL |

Key commands: `chronyc sources`, `chronyc tracking`, `chronyd -q`, `timedatectl`

Config: `/etc/chrony.conf` (not `/etc/ntp.conf`)

### Image Building & Provisioning

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| Packer | **Image Builder** | Build custom RHEL images for cloud, VM, edge, ISO |
| preseed (Debian) | **Kickstart** | RHEL's automated installation system |
| Custom ISO | **Anaconda** + **Kickstart** | Anaconda is RHEL's installer |
| cloud-init (for install) | **Kickstart** (install) + **cloud-init** (post-boot) | cloud-init works on RHEL for post-boot config |
| Immutable OS / image-based | **Image Mode (bootc)** | RHEL 9.4 (Technology Preview), RHEL 10 (GA): container-native OS updates |

Image Builder is available on the Hybrid Cloud Console and as a local CLI (`composer-cli` on RHEL 8–9, or the `image-builder` tool on RHEL 10).

### Performance Tuning

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| sysctl tuning, performance tuning | **TuneD** | Predefined profiles for throughput, latency, virtual-host, etc. Plugins tune CPU, disk, network, sysfs, sysctl, kernel boot command line, kernel module parameters, video, audio, and more |

Key commands: `tuned-adm active`, `tuned-adm list`, `tuned-adm profile <profile>`, `tuned-adm recommend`

### Automation & Configuration Management

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| Shell scripts for system config | **RHEL System Roles** (Ansible) | Supported roles for networking, storage, timesync, etc. |

Install with `dnf install rhel-system-roles`. Roles are installed to `/usr/share/ansible/roles/`. Common roles: `rhel-system-roles.network`, `.storage`, `.timesync`, `.selinux`, `.firewall`, `.logging`, `.certificate`, `.sshd`, `.nbde_client`, `.postfix`.

### System Identity & Updates

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| "How do I get updates?" | **subscription-manager** + **dnf update** | RHEL requires subscription registration |
| "Add a repository" | **subscription-manager repos --enable** or **dnf config-manager --add-repo** | Depends on repo type; see task table below |
| "What version am I running?" | **cat /etc/redhat-release** | Or `hostnamectl` |
| lsb_release | **cat /etc/redhat-release** | lsb_release not installed by default |
| console.redhat.com | **Hybrid Cloud Console** | Correct name: "Red Hat Hybrid Cloud Console" |
| CentOS | **CentOS Linux** or **CentOS Stream** | Use "CentOS Linux" (not "CentOS" alone) |

| Task | Other distros | RHEL |
|------|--------------|------|
| Register system | N/A | `subscription-manager register` |
| List available repos | `apt-cache policy` | `subscription-manager repos --list` |
| Enable a Red Hat repo | Edit sources.list | `subscription-manager repos --enable <repo-id>` (manages `redhat.repo`, generated from entitlement certs) |
| Add third-party repo | Add PPA / edit sources | `dnf config-manager --add-repo <url>` (for repos outside `redhat.repo`; do not edit `redhat.repo` directly — it is regenerated by subscription-manager) |
| Check registration | N/A | `subscription-manager status` |

### Crypto Policies & FIPS

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| Manual cipher/TLS config | **crypto-policies** | System-wide: `update-crypto-policies --set <POLICY>` |
| FIPS compliance mode | **FIPS mode** | RHEL 8–9: `fips-mode-setup --enable`; RHEL 10: must enable at install via `fips=1` kernel param |

Policies: **DEFAULT**, **LEGACY** (weaker, for compat), **FUTURE** (stricter), **FIPS**. Sub-policies can be appended, e.g. `DEFAULT:AD-SUPPORT`, `FUTURE:ECDHE-ONLY`.

Key commands: `update-crypto-policies --show`, `update-crypto-policies --set FUTURE`, `cat /proc/sys/crypto/fips_enabled`

RHEL 10: `fips-mode-setup` is removed. FIPS must be enabled at install time. DEFAULT policy now rejects RSA key exchange in TLS; LEGACY no longer allows SHA-1 HMAC in TLS.

### Upgrades & Migration

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| dnf system-upgrade, do-release-upgrade, dist-upgrade | **Leapp** | In-place upgrade: RHEL 7→8, 8→9, 9→10 |
| Migrate from CentOS/Oracle Linux/Rocky Linux/Alma Linux/Amazon Linux 2 | **Convert2RHEL** | `convert2rhel` converts to RHEL in place |

RHEL 6→7 upgrades use the **Red Hat Upgrade Tool** (`redhat-upgrade-tool`), not Leapp.

Key commands: `leapp preupgrade` (assessment), `leapp upgrade` (execute), `convert2rhel`

Always run `leapp preupgrade` first and resolve all inhibitors before upgrading. Back up the system (ReaR, LVM snapshot, or VM snapshot) before any upgrade.

### Monitoring & Observability

| User says | RHEL equivalent | Notes |
|-----------|----------------|-------|
| sysstat, sar, iostat | **PCP** (Performance Co-Pilot) | RHEL's standard performance analysis toolkit |
| Nagios, Prometheus node-exporter | **PCP + Grafana** | PCP collectors feed Grafana dashboards |
| top (persistent monitoring) | **PCP** (`pmstat`, `pminfo`, `pmrep`) | For historical/persistent data collection |

Key commands: `dnf install pcp-zeroconf`, `systemctl enable --now pmcd`, `pmstat`, `pminfo`, `pmrep`

`pcp-zeroconf` installs PCP with a sensible default configuration including log archiving.
