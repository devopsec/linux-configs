#!/usr/bin/env bash
# Volatile + log evidence collection for a Linux host (RHEL-family or Debian).
# Ported and reviewed from BagelHole/DevOps-Security-Agent-Skills (MIT); see LICENSE.txt.

usage() {
  cat >&2 <<'EOF'
Usage: collect-evidence.sh [-h] [-o OUTDIR] [-s SINCE] [-u UNIT]... INCIDENT_ID

Collects volatile state and logs into OUTDIR/<INCIDENT_ID>-<host>-<utc>/ (mode 0700),
writes a SHA-256 manifest and a .tar.gz with its own .sha256. Prints the archive path on stdout.
It does not kill, block, or change services; it writes an archive to the chosen output directory.
Run as root (via your privileged IR access) for complete output; non-root runs are partial.

  -o OUTDIR   Required output parent directory; use a separate evidence disk/mount.
  -s SINCE    journalctl --since value (default: "48 hours ago").
  -u UNIT     Extra systemd unit whose journal is collected (repeatable).
              Defaults always included: sshd ssh.
  -h          Show this help.
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob
[[ "${DEBUG:-0}" == "1" ]] && set -x

OUTDIR="${EVIDENCE_OUTDIR:-}"
SINCE="48 hours ago"
UNITS=(sshd ssh)
INCIDENT_ID=""
HOST=""
STAMP=""
DEST=""

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

# run <outfile> <cmd...>: capture stdout+stderr of a command; never abort collection.
run() {
  local out="$1"
  shift
  command -v "$1" &>/dev/null || { printf 'not available: %s\n' "$1" >"$DEST/$out"; return 0; }
  "$@" >"$DEST/$out" 2>&1 || true
}

copy_if() {
  local src="$1" out="$2"
  [[ -r "$src" ]] && cp --preserve=timestamps "$src" "$DEST/$out" 2>/dev/null || true
}

collect_system() {
  log "system"
  mkdir -p "$DEST/system"
  run system/uname.txt uname -a
  copy_if /etc/os-release system/os-release.txt
  run system/uptime.txt uptime
  run system/timedatectl.txt timedatectl
  run system/lsmod.txt lsmod
  run system/getenforce.txt getenforce
  run system/rpm-va.txt rpm -Va --nomtime
  run system/debsums.txt debsums -s
}

collect_processes() {
  log "processes"
  mkdir -p "$DEST/processes"
  run processes/ps-by-cpu.txt ps -eo pid,ppid,user,lstart,comm --sort=-pcpu
  run processes/pstree.txt pstree -lp
  run processes/lsof-net.txt lsof -nP -i
  # Processes whose executable was deleted after start (common for droppers).
  local exe="" target=""
  for exe in /proc/[0-9]*/exe; do
    target="$(readlink "$exe" 2>/dev/null || true)"
    [[ "$target" == *" (deleted)" ]] && printf '%s -> %s\n' "$exe" "$target"
  done >"$DEST/processes/deleted-exe.txt" || true
}

collect_network() {
  log "network"
  mkdir -p "$DEST/network"
  run network/ss-listen.txt ss -tulpen
  run network/ss-all.txt ss -tanpu
  run network/ip-addr.txt ip -d addr show
  run network/ip-route.txt ip route show table all
  run network/ip-neigh.txt ip neigh show
  run network/nft-ruleset.txt nft list ruleset
  run network/firewalld.txt firewall-cmd --list-all-zones
  run network/iptables-save.txt iptables-save
  copy_if /etc/hosts network/hosts.txt
  copy_if /etc/resolv.conf network/resolv.conf.txt
}

collect_users() {
  log "users"
  mkdir -p "$DEST/users"
  copy_if /etc/passwd users/passwd.txt
  copy_if /etc/group users/group.txt
  copy_if /etc/sudoers users/sudoers.txt
  run users/who.txt who -a
  run users/w.txt w
  run users/last.txt last -aiF -n 500
  run users/lastb.txt lastb -aiF -n 500
  run users/lastlog.txt lastlog
  # Metadata only (owner, mtime, size) — key contents are not copied.
  find /root /home -maxdepth 3 -name authorized_keys -ls >"$DEST/users/authorized-keys-meta.txt" 2>/dev/null || true
}

collect_persistence() {
  log "persistence"
  mkdir -p "$DEST/persistence"
  run persistence/units.txt systemctl list-units --all --no-pager
  run persistence/unit-files.txt systemctl list-unit-files --no-pager
  run persistence/timers.txt systemctl list-timers --all --no-pager
  find /etc/systemd/system /usr/lib/systemd/system /lib/systemd/system -newermt "7 days ago" -ls \
    >"$DEST/persistence/units-changed-7d.txt" 2>/dev/null || true
  copy_if /etc/crontab persistence/etc-crontab.txt
  ls -la /etc/cron.* /var/spool/cron /var/spool/cron/crontabs >"$DEST/persistence/cron-dirs.txt" 2>&1 || true
  find /tmp /var/tmp /dev/shm -xdev -type f -ls >"$DEST/persistence/tmp-files.txt" 2>/dev/null || true
  find / -xdev \( -perm -4000 -o -perm -2000 \) -type f -ls >"$DEST/persistence/suid-sgid.txt" 2>/dev/null || true
  find /etc /usr/bin /usr/sbin /usr/local -xdev -newermt "3 days ago" -type f -ls \
    >"$DEST/persistence/changed-3d.txt" 2>/dev/null || true
}

collect_logs() {
  local unit=""
  log "logs (since: $SINCE)"
  mkdir -p "$DEST/logs"
  run logs/journal-auth.txt journalctl --no-pager --since "$SINCE" --facility=auth,authpriv
  run logs/journal-errors.txt journalctl --no-pager --since "$SINCE" -p warning
  for unit in "${UNITS[@]}"; do
    run "logs/unit-${unit}.txt" journalctl --no-pager --since "$SINCE" -u "$unit"
  done
  copy_if /var/log/secure logs/secure.txt
  copy_if /var/log/auth.log logs/auth.log.txt
  copy_if /var/log/audit/audit.log logs/audit.log.txt
  copy_if /var/log/messages logs/messages.txt
  copy_if /var/log/syslog logs/syslog.txt
}

finalize() {
  local archive="$DEST.tar.gz"
  log "hashing"
  (cd "$DEST" && find . -type f -print0 | sort -z | xargs -0 sha256sum >"$DEST.manifest.tmp")
  mv "$DEST.manifest.tmp" "$DEST/MANIFEST.sha256"
  tar -czf "$archive" -C "$(dirname "$DEST")" "$(basename "$DEST")"
  sha256sum "$archive" >"$archive.sha256"
  log "done: $archive ($(du -h "$archive" | cut -f1))"
  printf '%s\n' "$archive"
}

main() {
  local opt="" dep=""
  while getopts ':ho:s:u:' opt; do
    case "$opt" in
      h) usage; exit 0 ;;
      o) OUTDIR="$OPTARG" ;;
      s) SINCE="$OPTARG" ;;
      u)
        [[ "$OPTARG" =~ ^[A-Za-z0-9_.@:-]+$ ]] || { printf 'invalid systemd unit name: %s\n' "$OPTARG" >&2; exit 2; }
        UNITS+=("$OPTARG")
        ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  (( $# == 1 )) || { usage; exit 2; }
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || { printf 'INCIDENT_ID must match [A-Za-z0-9._-]+\n' >&2; exit 2; }
  INCIDENT_ID="$1"
  for dep in sha256sum tar find; do
    command -v "$dep" &>/dev/null || { printf 'missing dependency: %s\n' "$dep" >&2; exit 1; }
  done
  [[ -n "$OUTDIR" ]] || { printf 'specify -o OUTDIR or EVIDENCE_OUTDIR on a separate evidence mount\n' >&2; exit 2; }
  [[ "$OUTDIR" != "/" ]] || { printf 'refusing to use the filesystem root as OUTDIR\n' >&2; exit 2; }
  (( EUID == 0 )) || log "WARNING: not root — output will be partial"

  HOST="$(hostname -s)"
  STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  umask 077
  mkdir -p "$OUTDIR"
  DEST="$OUTDIR/${INCIDENT_ID}-${HOST}-${STAMP}"
  mkdir "$DEST"
  {
    printf 'incident_id: %s\nhost: %s\ncollected_utc: %s\ncollector: %s\nsince: %s\n' \
      "$INCIDENT_ID" "$HOST" "$STAMP" "$(id -un)" "$SINCE"
  } >"$DEST/metadata.txt"

  collect_system
  collect_processes
  collect_network
  collect_users
  collect_persistence
  collect_logs
  finalize
}

main "$@"
