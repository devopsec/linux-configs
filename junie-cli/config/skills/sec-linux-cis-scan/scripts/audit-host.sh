#!/usr/bin/env bash
# shellcheck disable=SC1091
# Read-only Linux host security audit (RHEL-family and Debian).
# Derived from BagelHole/DevOps-Security-Agent-Skills linux-hardening/scripts/audit-system.sh (MIT), rewritten.

usage() {
  cat <<'EOF'
Usage: audit-host.sh [-h]

Read-only quick audit of a Linux host against a CIS-style baseline.
Never changes system state. Run as root for full coverage; checks that
need root are reported as SKIP otherwise.

Output: one line per check (PASS|WARN|FAIL|SKIP) on stdout, summary at end.
Exit:   0 = no FAIL, 1 = at least one FAIL, 2 = usage error.
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob
[[ "${DEBUG:-0}" == "1" ]] && set -x

PASS=0
WARN=0
FAIL=0
SKIP=0
IS_ROOT=0
OS_FAMILY="unknown"

check() {
  local status="$1"
  local message="$2"
  printf '[%s] %s\n' "$status" "$message"
  case "$status" in
    PASS) PASS=$((PASS + 1)) ;;
    WARN) WARN=$((WARN + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
    SKIP) SKIP=$((SKIP + 1)) ;;
  esac
}

section() {
  printf '\n== %s ==\n' "$1"
}

# verdict <ok:0|1> <status-if-not-ok> <message-if-ok> <message-if-not-ok>
verdict() {
  if [[ "$1" == "1" ]]; then
    check PASS "$3"
  else
    check "$2" "$4"
  fi
}

# truth <command...> -> prints 1 if the command succeeds, else 0
truth() {
  if "$@"; then printf '1'; else printf '0'; fi
}

detect_os() {
  local id_like=""
  local id=""
  if [[ -r /etc/os-release ]]; then
    id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    id_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
  fi
  case " $id $id_like " in
    *" rhel "* | *" fedora "* | *" centos "*) OS_FAMILY="rhel" ;;
    *" debian "* | *" ubuntu "*) OS_FAMILY="debian" ;;
  esac
  printf 'OS: %s (family: %s), root: %s\n' "${id:-unknown}" "$OS_FAMILY" "$IS_ROOT"
}

check_updates() {
  local rc=0
  local count=0
  local apt_output=""
  section "Updates"
  case "$OS_FAMILY" in
    rhel)
      if command -v dnf &>/dev/null; then
        dnf -q --cacheonly check-update &>/dev/null || rc=$?
        case "$rc" in
          0) check PASS "no pending dnf updates in cached metadata" ;;
          100) check FAIL "dnf updates pending (dnf updateinfo list --security)" ;;
          *) check SKIP "dnf cache-only check-update failed (rc=$rc)" ;;
        esac
      else
        check SKIP "dnf not found"
      fi
      ;;
    debian)
      if ! apt_output="$(LC_ALL=C apt-get -s upgrade 2>/dev/null)"; then
        check SKIP "apt-get simulation failed (cache or package state unavailable)"
      else
        count="$(printf '%s\n' "$apt_output" | awk '/^Inst/ {n++} END {print n+0}')"
        if [[ "$count" == "0" ]]; then
          check PASS "no pending apt upgrades (cache may be stale)"
        else
          check FAIL "$count apt packages pending upgrade"
        fi
      fi
      ;;
    *) check SKIP "unknown OS family" ;;
  esac
}

sshd_value() {
  local key="$1"
  sshd -T 2>/dev/null | awk -v k="$key" 'tolower($1) == k {print tolower($2); exit}'
}

check_sshd() {
  local root_login=""
  local pw_auth=""
  local tries=""
  section "SSH"
  if ! command -v sshd &>/dev/null; then
    check SKIP "sshd not installed"
    return 0
  fi
  if (( IS_ROOT == 0 )); then
    check SKIP "effective sshd config needs root (sshd -T)"
    return 0
  fi
  root_login="$(sshd_value permitrootlogin)"
  pw_auth="$(sshd_value passwordauthentication)"
  tries="$(sshd_value maxauthtries)"
  verdict "$(truth test "$root_login" = no)" FAIL "PermitRootLogin no" "PermitRootLogin is '${root_login:-unknown}'"
  verdict "$(truth test "$pw_auth" = no)" WARN "PasswordAuthentication no" "PasswordAuthentication is '${pw_auth:-unknown}'"
  if [[ "$tries" =~ ^[0-9]+$ ]] && (( tries <= 4 )); then
    check PASS "MaxAuthTries $tries"
  else
    check WARN "MaxAuthTries is '${tries:-unknown}' (want <= 4)"
  fi
}

check_accounts() {
  local uid0=""
  local empty=""
  section "Accounts"
  uid0="$(awk -F: '$3 == 0 {print $1}' /etc/passwd | paste -sd, -)"
  verdict "$(truth test "$uid0" = root)" FAIL "only root has UID 0" "UID 0 accounts: $uid0"
  if [[ -r /etc/shadow ]]; then
    empty="$(awk -F: '$2 == "" {print $1}' /etc/shadow | paste -sd, -)"
    verdict "$(truth test -z "$empty")" FAIL "no accounts with empty hash" "empty hash: $empty"
  else
    check SKIP "/etc/shadow not readable"
  fi
}

check_perms() {
  local mode=""
  local f=""
  local ww=0
  local find_output=""
  section "File permissions"
  for f in /etc/shadow /etc/gshadow; do
    [[ -e "$f" ]] || continue
    mode="$(stat -c %a "$f")"
    case "$mode" in
      0 | 400 | 600 | 640) check PASS "$f mode $mode" ;;
      *) check FAIL "$f mode $mode (want 0000/0600/0640)" ;;
    esac
  done
  for f in /etc/passwd /etc/group; do
    mode="$(stat -c %a "$f")"
    verdict "$(truth test "$mode" = 644)" WARN "$f mode $mode" "$f mode $mode (want 0644)"
  done
  if (( IS_ROOT == 0 )); then
    check SKIP "world-writable file scan in /etc needs root for complete coverage"
  elif find_output="$(find /etc -xdev -type f -perm -0002 2>/dev/null)"; then
    ww="$(printf '%s\n' "$find_output" | awk 'NF {n++} END {print n+0}')"
    verdict "$(truth test "$ww" = 0)" FAIL "no world-writable files in /etc" "$ww world-writable files in /etc"
  else
    check SKIP "world-writable file scan in /etc was incomplete"
  fi
}

check_sysctl() {
  local entry=""
  local key=""
  local want=""
  local have=""
  local -a wanted=(
    "net.ipv4.tcp_syncookies=1"
    "net.ipv4.conf.all.accept_redirects=0"
    "net.ipv4.conf.all.send_redirects=0"
    "net.ipv4.conf.all.accept_source_route=0"
    "net.ipv4.conf.all.log_martians=1"
    "kernel.randomize_va_space=2"
    "kernel.kptr_restrict=2"
    "kernel.dmesg_restrict=1"
    "fs.suid_dumpable=0"
    "fs.protected_symlinks=1"
    "fs.protected_hardlinks=1"
  )
  section "Kernel (sysctl)"
  for entry in "${wanted[@]}"; do
    key="${entry%%=*}"
    want="${entry#*=}"
    have="$(sysctl -n "$key" 2>/dev/null || true)"
    if [[ -z "$have" ]]; then
      check SKIP "$key not available"
    elif [[ "$have" == "$want" ]]; then
      check PASS "$key = $have"
    else
      check WARN "$key = $have (want $want)"
    fi
  done
  have="$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || true)"
  case "$have" in
    1) check PASS "rp_filter strict" ;;
    2) check WARN "rp_filter loose (acceptable on multi-NIC SIP hosts if documented)" ;;
    *) check WARN "rp_filter = ${have:-unknown}" ;;
  esac
}

check_firewall() {
  section "Firewall"
  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    check PASS "firewalld active (default zone: $(firewall-cmd --get-default-zone 2>/dev/null || echo '?'))"
  elif command -v ufw &>/dev/null && (( IS_ROOT == 1 )) && ufw status 2>/dev/null | grep -q '^Status: active'; then
    check PASS "ufw active"
  elif systemctl is-active --quiet nftables 2>/dev/null; then
    check PASS "nftables service active"
  elif (( IS_ROOT == 0 )); then
    check SKIP "firewall state needs root (or firewalld not running)"
  else
    check FAIL "no active host firewall detected (firewalld/ufw/nftables)"
  fi
}

check_mac() {
  local mode=""
  section "Mandatory access control"
  if command -v getenforce &>/dev/null; then
    mode="$(getenforce)"
    verdict "$(truth test "$mode" = Enforcing)" FAIL "SELinux Enforcing" "SELinux $mode"
  elif [[ -d /sys/kernel/security/apparmor ]]; then
    if command -v aa-enabled &>/dev/null && aa-enabled --quiet 2>/dev/null; then
      check PASS "AppArmor enabled"
    else
      check WARN "AppArmor present but not confirmed enabled"
    fi
  else
    check WARN "no SELinux/AppArmor detected"
  fi
}

check_services() {
  local svc=""
  local -a listeners=()
  section "Services"
  verdict "$(truth systemctl is-active --quiet auditd)" WARN "auditd active" "auditd not active"
  for svc in telnet.socket rsh.socket tftp.socket avahi-daemon.service cups.service; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      check WARN "$svc active"
    fi
  done
  mapfile -t listeners < <({ ss -H -tuln 2>/dev/null || true; } | awk '{print $1" "$5}' | sort -u)
  check WARN "${#listeners[@]} listening sockets (review: ss -tulpn)"
  printf '    %s\n' "${listeners[@]}"
}

main() {
  case "${1:-}" in
    -h | --help) usage; exit 0 ;;
    "") ;;
    *) usage >&2; exit 2 ;;
  esac
  [[ "$(id -u)" == "0" ]] && IS_ROOT=1
  detect_os
  check_updates
  check_sshd
  check_accounts
  check_perms
  check_sysctl
  check_firewall
  check_mac
  check_services
  printf '\nSummary: PASS=%d WARN=%d FAIL=%d SKIP=%d\n' "$PASS" "$WARN" "$FAIL" "$SKIP"
  (( FAIL == 0 )) || exit 1
}

main "$@"
