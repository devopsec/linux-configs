#!/usr/bin/env bash
# Read-only Prometheus health summary: health/readiness, TSDB head stats,
# target health counts, unhealthy targets and firing alerts.

usage() {
  cat <<'EOF'
Usage: prom-health-check.sh [-h] [PROMETHEUS_URL]

Read-only summary of a Prometheus server (GET requests only).

Arguments:
  PROMETHEUS_URL   Base URL (default: $PROMETHEUS_URL or http://localhost:9090)

Environment:
  PROMETHEUS_URL        Base URL if no argument is given
  PROMETHEUS_AUTH_FILE  Optional private file containing one "user:password" line
  CURL_CA_BUNDLE        Optional CA bundle for TLS endpoints

Requires: curl, jq, base64, stat (GNU coreutils)
Exit codes: 0 healthy, 1 unhealthy/unreachable, 2 usage or dependency error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob
DEBUG_TRACE=0
if [[ "${DEBUG:-0}" == "1" ]]; then DEBUG_TRACE=1; fi

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

prom_get() {
  local path="$1"
  local had_xtrace=0 rc auth_pair auth_header
  local -a cmd
  if [[ $- == *x* ]]; then had_xtrace=1; fi
  set +x
  cmd=(curl --fail --silent --show-error --max-time 10)
  if [[ -n "${PROMETHEUS_AUTH_FILE:-}" ]]; then
    auth_pair="$(<"$PROMETHEUS_AUTH_FILE")"
    auth_pair="${auth_pair%$'\r'}"
    if [[ "$auth_pair" != *:* || "$auth_pair" == *$'\n'* ]]; then
      log "auth file must contain one user:password line"
      unset auth_pair
      if (( had_xtrace )); then set -x; fi
      return 2
    fi
    if ! auth_header="$(printf '%s' "$auth_pair" | base64 --wrap=0)"; then
      log "could not encode basic-auth header"
      unset auth_pair auth_header
      if (( had_xtrace )); then set -x; fi
      return 2
    fi
    if "${cmd[@]}" --header @<(printf 'Authorization: Basic %s\n' "$auth_header") \
      "${BASE_URL}${path}"; then
      rc=0
    else
      rc=$?
    fi
    unset auth_pair auth_header
  else
    if "${cmd[@]}" "${BASE_URL}${path}"; then
      rc=0
    else
      rc=$?
    fi
  fi
  if (( had_xtrace )); then set -x; fi
  return "$rc"
}

main() {
  local status=0 head_json targets_json alerts_json authority file_mode scheme auth_pair

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
  if (( $# > 1 )); then usage >&2; exit 2; fi

  local dep
  for dep in curl jq base64 stat; do
    command -v "$dep" &>/dev/null || { log "missing dependency: $dep"; exit 2; }
  done

  BASE_URL="${1:-${PROMETHEUS_URL:-http://localhost:9090}}"
  BASE_URL="${BASE_URL%/}"
  case "$BASE_URL" in
    http://*|https://*) ;;
    *) log "invalid URL: base URL must start with http:// or https://"; exit 2 ;;
  esac
  if [[ "$BASE_URL" == *\?* || "$BASE_URL" == *\#* ]]; then
    log "base URL must not contain a query or fragment"; exit 2
  fi
  authority="${BASE_URL#*://}"
  authority="${authority%%/*}"
  if [[ -z "$authority" || "$authority" == *[[:space:]]* ]]; then
    log "invalid URL: host is missing or contains whitespace"; exit 2
  fi
  if [[ "$authority" == *@* ]]; then log "URL userinfo is not allowed"; exit 2; fi
  if [[ "$BASE_URL" == http://* ]]; then
    case "$authority" in
      localhost|localhost:*|127.0.0.1|127.0.0.1:*|'[::1]'|'[::1]:'*) ;;
      *) log "remote Prometheus endpoints require HTTPS (HTTP is allowed only on loopback)"; exit 2 ;;
    esac
  fi
  if [[ -n "${PROMETHEUS_AUTH_FILE:-}" ]]; then
    if [[ ! -f "$PROMETHEUS_AUTH_FILE" || -L "$PROMETHEUS_AUTH_FILE" || ! -r "$PROMETHEUS_AUTH_FILE" ]]; then
      log "auth file must be a readable, regular, non-symlink file"; exit 2
    fi
    if ! file_mode="$(stat -c '%a' -- "$PROMETHEUS_AUTH_FILE")"; then
      log "could not inspect auth file permissions"; exit 2
    fi
    if [[ ! "$file_mode" =~ ^[0-7]{3,4}$ ]]; then
      log "could not parse auth file permissions"; exit 2
    fi
    if (( (8#$file_mode & 077) != 0 )); then
      log "auth file must not be accessible by group or other users"; exit 2
    fi
    auth_pair="$(<"$PROMETHEUS_AUTH_FILE")"
    auth_pair="${auth_pair%$'\r'}"
    if [[ "$auth_pair" != *:* || "$auth_pair" == *$'\n'* ]]; then
      log "auth file must contain one user:password line"; exit 2
    fi
    unset auth_pair
  fi

  if (( DEBUG_TRACE )); then set -x; fi
  scheme="${BASE_URL%%://*}"
  echo "Prometheus: ${scheme}://${authority}"

  if prom_get /-/healthy >/dev/null; then echo "healthy: yes"; else echo "healthy: NO"; status=1; fi
  if prom_get /-/ready >/dev/null; then echo "ready:   yes"; else echo "ready:   NO"; status=1; fi
  if (( status != 0 )); then exit "$status"; fi

  if head_json="$(prom_get /api/v1/status/tsdb)"; then
    jq -r '.data.headStats | "head series: \(.numSeries)  chunks: \(.chunkCount)"' <<<"$head_json"
  else
    log "TSDB statistics endpoint unavailable"
    status=1
  fi

  echo
  echo "Targets by health:"
  targets_json="$(prom_get '/api/v1/targets?state=active')"
  jq -r '.data.activeTargets | group_by(.health)[] | "  \(.[0].health): \(length)"' <<<"$targets_json"

  echo "Unhealthy targets:"
  jq -r '.data.activeTargets[] | select(.health != "up")
         | "  - \(.labels.job)/\(.labels.instance): \(.lastError)"' <<<"$targets_json"
  if jq -e '[.data.activeTargets[] | select(.health != "up")] | length > 0' <<<"$targets_json" >/dev/null; then
    status=1
  fi

  echo
  echo "Firing alerts:"
  alerts_json="$(prom_get /api/v1/alerts)"
  jq -r '.data.alerts[] | select(.state == "firing")
         | "  - [\(.labels.severity // "none")] \(.labels.alertname): \(.annotations.summary // "")"' <<<"$alerts_json"

  exit "$status"
}

main "$@"
