#!/usr/bin/env bash
# Export Grafana dashboards, folders and datasource metadata to JSON files; protect the output.
# Read-only against Grafana (GET requests). Token is read from the environment only.

usage() {
  cat <<'EOF'
Usage: grafana-backup.sh [-h] [-u GRAFANA_URL] [-o OUTPUT_DIR]

Exports dashboards (one JSON per dashboard UID), folders and datasources from Grafana.

Options:
  -u URL   Grafana base URL (default: $GRAFANA_URL or http://localhost:3000)
  -o DIR   Output directory (default: ./grafana-backup-<UTC timestamp>); must not exist
  -h       Show this help

Environment:
  GRAFANA_TOKEN   Service-account token with Viewer role (required; never pass on the CLI)
  CURL_CA_BUNDLE  Optional CA bundle for TLS endpoints

Notes:
  Treat exports as sensitive: datasource metadata may include URLs and usernames even
  though Grafana masks secret fields. Re-enter masked secrets on restore.
  Restore: POST dashboards to /api/dashboards/db with {"dashboard": ..., "folderUid": ..., "overwrite": false}.

Requires: curl, jq
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob
DEBUG_TRACE=0
if [[ "${DEBUG:-0}" == "1" ]]; then DEBUG_TRACE=1; fi

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }

grafana_get() {
  local path="$1"
  local had_xtrace=0 rc
  if [[ $- == *x* ]]; then had_xtrace=1; fi
  set +x
  if curl --fail --silent --show-error --max-time 30 \
    --header @<(printf 'Authorization: Bearer %s\n' "$GRAFANA_TOKEN") \
    "${BASE_URL}${path}"; then
    rc=0
  else
    rc=$?
  fi
  if (( had_xtrace )); then set -x; fi
  return "$rc"
}

main() {
  local opt out_dir="" uid safe_title count=0 authority scheme search_json uid_lines page=1
  local -a uids=() page_uids=()
  BASE_URL="${GRAFANA_URL:-http://localhost:3000}"

  while getopts ':u:o:h' opt; do
    case "$opt" in
      u) BASE_URL="$OPTARG" ;;
      o) out_dir="$OPTARG" ;;
      h) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  if (( $# > 0 )); then usage >&2; exit 2; fi

  local dep
  for dep in curl jq; do
    command -v "$dep" &>/dev/null || { log "missing dependency: $dep"; exit 2; }
  done
  if [[ -z "${GRAFANA_TOKEN:-}" ]]; then
    log "missing GRAFANA_TOKEN (service-account token)"; exit 2
  fi

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
  if [[ -z "$authority" ]]; then log "invalid URL: host is missing"; exit 2; fi
  if [[ "$authority" == *@* ]]; then log "URL userinfo is not allowed"; exit 2; fi
  if [[ "$BASE_URL" == http://* ]]; then
    case "$authority" in
      localhost|localhost:*|127.0.0.1|127.0.0.1:*|'[::1]'|'[::1]:'*) ;;
      *) log "authenticated remote Grafana requires HTTPS (HTTP is allowed only on loopback)"; exit 2 ;;
    esac
  fi
  scheme="${BASE_URL%%://*}"
  if (( DEBUG_TRACE )); then set -x; fi

  out_dir="${out_dir:-./grafana-backup-$(date -u +%Y%m%dT%H%M%SZ)}"
  if [[ -e "$out_dir" || -L "$out_dir" ]]; then log "output directory exists: $out_dir"; exit 2; fi
  umask 077
  mkdir -p -- "$out_dir/dashboards"

  log "exporting from ${scheme}://${authority} to $out_dir"
  grafana_get /api/folders >"$out_dir/folders.json"
  grafana_get /api/datasources >"$out_dir/datasources.json"

  while :; do
    search_json="$(grafana_get "/api/search?type=dash-db&limit=500&page=${page}")"
    uid_lines="$(jq -r '.[].uid' <<<"$search_json")"
    [[ -n "$uid_lines" ]] || break
    mapfile -t page_uids <<<"$uid_lines"
    uids+=("${page_uids[@]}")
    (( ${#page_uids[@]} < 500 )) && break
    page=$((page + 1))
  done
  for uid in "${uids[@]}"; do
    [[ "$uid" =~ ^[A-Za-z0-9_-]+$ ]] || { log "skipping unexpected uid: $uid"; continue; }
    grafana_get "/api/dashboards/uid/${uid}" >"$out_dir/dashboards/${uid}.json"
    safe_title="$(jq -j '.dashboard.title' "$out_dir/dashboards/${uid}.json" | tr -c 'A-Za-z0-9._-' '_')"
    printf '%s\t%s\n' "$uid" "$safe_title" >>"$out_dir/index.tsv"
    count=$((count + 1))
  done

  log "exported $count dashboards, $(jq length "$out_dir/folders.json") folders, $(jq length "$out_dir/datasources.json") datasources"
  echo "$out_dir"
}

main "$@"
