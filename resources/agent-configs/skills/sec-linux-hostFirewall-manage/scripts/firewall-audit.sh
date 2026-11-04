#!/usr/bin/env bash
# Read-only host firewall and exposure audit (firewalld, nftables, ufw, iptables).
# Derived from BagelHole/DevOps-Security-Agent-Skills firewall-config/scripts/firewall-audit.sh (MIT), rewritten.

usage() {
  cat <<'EOF'
Usage: firewall-audit.sh [-h] [-q]

Read-only. Prints the active host firewall configuration, listening sockets,
and exposure findings (sensitive ports bound to all interfaces, SIP conntrack
helper loaded, conntrack table pressure). Run as root for full rule output.

  -q   findings only (skip full rule dump)
  -h   help

Exit: 0 = no FAIL findings, 1 = at least one FAIL, 2 = usage error.
Env:  SENSITIVE_PORTS (default "22 2223 3306 5000 5432 6379 8080 9090")
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob
[[ "${DEBUG:-0}" == "1" ]] && set -x

QUIET=0
FAILS=0
SENSITIVE_PORTS="${SENSITIVE_PORTS:-22 2223 3306 5000 5432 6379 8080 9090}"

log() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

finding() {
  local level="$1"
  local message="$2"
  printf '[%s] %s\n' "$level" "$message"
  if [[ "$level" == "FAIL" ]]; then
    FAILS=$((FAILS + 1))
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

detect_firewall() {
  if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
    printf 'firewalld'
  elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
    printf 'ufw'
  elif command -v nft &>/dev/null && [[ -n "$(nft list tables 2>/dev/null || true)" ]]; then
    printf 'nftables'
  elif command -v iptables &>/dev/null; then
    printf 'iptables'
  else
    printf 'none'
  fi
}

dump_firewalld() {
  local zone=""
  local -a zones=()
  firewall-cmd --state || true
  printf 'Default zone: %s\n' "$(firewall-cmd --get-default-zone 2>/dev/null || echo '?')"
  firewall-cmd --get-active-zones || true
  mapfile -t zones < <(firewall-cmd --get-active-zones 2>/dev/null | awk '/^[^ ]/ {print $1}')
  for zone in "${zones[@]}"; do
    printf -- '--- zone: %s ---\n' "$zone"
    firewall-cmd --zone="$zone" --list-all 2>/dev/null || true
  done
}

dump_rules() {
  local fw="$1"
  section "Rules ($fw)"
  case "$fw" in
    firewalld) dump_firewalld ;;
    ufw) ufw status verbose || true ;;
    nftables) nft list ruleset 2>/dev/null || log "nft list ruleset failed (root required?)" ;;
    iptables)
      iptables -S 2>/dev/null || log "iptables -S failed (root required?)"
      ip6tables -S 2>/dev/null || true
      ;;
    none) printf 'no firewall tooling found\n' ;;
  esac
}

check_default_policy() {
  local fw="$1"
  local target=""
  local policy=""
  section "Default inbound policy"
  case "$fw" in
    firewalld)
      target="$(firewall-cmd --get-default-zone 2>/dev/null || true)"
      if [[ -z "$target" ]]; then
        finding SKIP "firewalld active zone unavailable"
        return
      fi
      policy="$(firewall-cmd --zone="$target" --get-target 2>/dev/null || true)"
      if [[ -z "$policy" ]]; then
        finding SKIP "firewalld target for active zone '$target' unavailable"
      elif [[ "$policy" == "ACCEPT" ]]; then
        finding FAIL "firewalld active zone '$target' target is ACCEPT"
      else
        finding PASS "firewalld active zone '$target' target: $policy"
      fi
      ;;
    ufw)
      if ufw status verbose 2>/dev/null | grep -q 'Default: deny (incoming)\|Default: reject (incoming)'; then
        finding PASS "ufw default incoming deny/reject"
      else
        finding FAIL "ufw default incoming is not deny"
      fi
      ;;
    nftables)
      if nft list ruleset 2>/dev/null | grep -Eq 'hook input .*policy drop'; then
        finding PASS "nftables input chain policy drop"
      elif (( EUID != 0 )); then
        finding SKIP "nftables ruleset needs root"
      else
        finding FAIL "no nftables input chain with policy drop"
      fi
      ;;
    iptables)
      policy="$(iptables -S INPUT 2>/dev/null | awk '$1 == "-P" {print $3}')"
      case "$policy" in
        DROP | REJECT) finding PASS "iptables INPUT policy $policy" ;;
        "") finding SKIP "iptables INPUT policy unreadable (root required?)" ;;
        *) finding FAIL "iptables INPUT policy $policy" ;;
      esac
      ;;
    none) finding FAIL "no active host firewall" ;;
  esac
}

check_listeners() {
  local line=""
  local proto=""
  local addr=""
  local port=""
  local p=""
  local -a sensitive_ports=()
  local -a lines=()
  read -r -a sensitive_ports <<< "$SENSITIVE_PORTS"
  section "Listening sockets"
  mapfile -t lines < <({ ss -H -tuln 2>/dev/null || true; } | awk '{print $1" "$5}' | sort -u)
  printf '  %s\n' "${lines[@]}"
  section "Exposure findings"
  for line in "${lines[@]}"; do
    proto="${line%% *}"
    addr="${line#* }"
    port="${addr##*:}"
    addr="${addr%:*}"
    case "$addr" in
      0.0.0.0 | "[::]" | "*")
        for p in "${sensitive_ports[@]}"; do
          if [[ ! "$p" =~ ^[0-9]{1,5}$ ]] || (( 10#$p < 1 || 10#$p > 65535 )); then
            log "ignoring invalid SENSITIVE_PORTS entry"
            continue
          fi
          p="$((10#$p))"
          if [[ "$port" == "$p" ]]; then
            finding WARN "$proto/$port bound to all interfaces ($addr) — ensure firewall restricts source"
          fi
        done
        ;;
    esac
    if [[ "$port" == "5060" || "$port" == "5061" ]]; then
      finding INFO "SIP listener $proto $addr:$port"
    fi
  done
}

check_sip_helper() {
  local max=0
  local count=0
  section "SIP / conntrack"
  if [[ ! -r /proc/modules ]]; then
    finding SKIP "/proc/modules is not readable"
  elif grep -Eq '^nf_(conntrack|nat)_sip ' /proc/modules 2>/dev/null; then
    finding FAIL "kernel SIP helper (nf_conntrack_sip/nf_nat_sip) loaded — disable on SIP servers"
  else
    finding PASS "kernel SIP helper not loaded"
  fi
  if [[ -r /proc/sys/net/netfilter/nf_conntrack_count && -r /proc/sys/net/netfilter/nf_conntrack_max ]]; then
    count="$(cat /proc/sys/net/netfilter/nf_conntrack_count)"
    max="$(cat /proc/sys/net/netfilter/nf_conntrack_max)"
    if (( max > 0 && count * 100 / max >= 80 )); then
      finding WARN "conntrack table ${count}/${max} (>= 80%)"
    else
      finding PASS "conntrack table ${count}/${max}"
    fi
  else
    finding SKIP "conntrack counters not available"
  fi
}

main() {
  local fw=""
  local opt=""
  while getopts ':hq' opt; do
    case "$opt" in
      h) usage; exit 0 ;;
      q) QUIET=1 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  (( EUID == 0 )) || log "not root: some rule output will be missing"
  printf 'Host: %s  Date: %s\n' "$(hostname)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fw="$(detect_firewall)"
  printf 'Detected firewall: %s\n' "$fw"
  (( QUIET == 1 )) || dump_rules "$fw"
  check_default_policy "$fw"
  check_listeners
  check_sip_helper
  printf '\nFAIL findings: %d\n' "$FAILS"
  (( FAILS == 0 )) || exit 1
}

main "$@"
