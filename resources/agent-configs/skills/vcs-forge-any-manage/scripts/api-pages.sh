#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    GET every page of a list endpoint through 'forge api' (which has no
    --paginate) and print one merged JSON array. Works with page/per_page
    (GitHub, GitLab) and page/limit (Gitea/Forgejo) APIs; both parameters are
    sent. {owner} and {repo} in the endpoint are substituted by forge. GET
    only — never use it for writes.

Usage:
    ${0##*/} [-h] [-p <per-page>] [-m <max-pages>] [-R <owner/repo>] [--] <endpoint>

Arguments:
    -h              Show this usage documentation.
    -p <per-page>   Items per page (default: 100; Gitea caps at its MAX_RESPONSE_ITEMS, often 50).
    -m <max-pages>  Stop after this many pages (default: 50).
    -R <owner/repo> Repository for forge (default: from the git remote).
    <endpoint>      e.g. 'repos/{owner}/{repo}/pulls/42/comments'
                    (an existing query string is kept). Pagination stops at the first
                    empty page, so short pages from capped servers are safe.

Environment:
    FORGE_HOST      Passed through to forge (host for -R).
    DEBUG=1         Trace execution.

Exit Codes:
    0   success (prints a JSON array, possibly empty)
    1   forge or jq missing, an API call failed, or a page was not a JSON array
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

PER_PAGE=100
MAX_PAGES=50
REPO=''
TMP_FILE=''

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

main() {
    local opt
    while getopts ':hp:m:R:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            p) [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]] || die "-p needs a positive integer" 2
               PER_PAGE="$OPTARG" ;;
            m) [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]] || die "-m needs a positive integer" 2
               MAX_PAGES="$OPTARG" ;;
            R) REPO="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    [[ "${1:-}" == -- ]] && shift
    (($# == 1)) || { usage >&2; exit 2; }
    local endpoint="$1"
    [[ "${DEBUG:-0}" == 1 ]] && set -x
    command -v forge >/dev/null 2>&1 || die "forge not found"
    command -v jq >/dev/null 2>&1 || die "jq not found"

    local -a repo_args=()
    [[ -n "$REPO" ]] && repo_args=(-R "$REPO")
    local sep='?'
    [[ "$endpoint" == *\?* ]] && sep='&'

    local page=1 body count
    TMP_FILE="$(mktemp)"
    trap 'rm -f -- "$TMP_FILE"' EXIT
    while ((page <= MAX_PAGES)); do
        body="$(forge "${repo_args[@]}" api "${endpoint}${sep}per_page=${PER_PAGE}&limit=${PER_PAGE}&page=${page}")" ||
            die "forge api failed on page $page"
        count="$(jq 'if type == "array" then length else error("not an array") end' <<<"$body" 2>/dev/null)" ||
            die "page $page is not a JSON array (object endpoint? error response?): $(head -c 200 <<<"$body")"
        # Stop on an empty page, not a short one: servers may cap page size below -p.
        ((count > 0)) || break
        printf '%s\n' "$body" >>"$TMP_FILE"
        ((page += 1))
    done
    ((page <= MAX_PAGES)) || printf '[warn] stopped at %d pages (-m to raise)\n' "$MAX_PAGES" >&2
    jq -s 'add // []' "$TMP_FILE"
}

main "$@"
