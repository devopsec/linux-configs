#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only pre-flight report for forge(1) (git-pkgs/forge) in a git
    checkout: forge version, the remote forge will use and its host/owner/
    repo, repo-local .forge settings, whether a token is available for that
    host (never printed), the repository as the forge API sees it, the PR for
    the current branch, and the API rate limit. Run before any write.

Usage:
    ${0##*/} [-h] [-n] [-r <remote>] [-C <dir>]

Arguments:
    -h            Show this usage documentation.
    -n            Offline: skip API calls (repo, PR, rate limit).
    -r <remote>   Git remote to inspect (default: .forge [default] remote,
                  else origin).
    -C <dir>      Repository to inspect (default: .).

Environment:
    FORGE_HOST, FORGE_TOKEN, GITHUB_TOKEN, GH_TOKEN, GITLAB_TOKEN,
    GITEA_TOKEN, FORGEJO_TOKEN, BITBUCKET_TOKEN, TANGLED_TOKEN
                  Reported as set/unset only; values are never printed.
    DEBUG=1       Trace execution.

Exit Codes:
    0   ready: forge found, remote resolved, token available
    1   forge not found, not a git repository, or remote missing
    2   usage error
    3   no token for the host: reads may work (rate-limited), writes will fail
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

OFFLINE=0
REMOTE=''
DIR='.'

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }
warn() { printf '[warn] %s\n' "$1" >&2; }

# Prints "host<TAB>owner/repo" for https://, ssh://, and scp-style remote URLs.
parse_remote() {
    local url="$1" host path
    if [[ "$url" =~ ^[a-z+]+://([^@/]+@)?([^/:]+)(:[0-9]+)?/(.+)$ ]]; then
        host="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        path="${BASH_REMATCH[4]}"
    elif [[ "$url" =~ ^([^@]+@)?([^:/]+):(.+)$ ]]; then
        host="${BASH_REMATCH[2]}"
        path="${BASH_REMATCH[3]}"
    else
        return 1
    fi
    path="${path%/}"
    path="${path%.git}"
    printf '%s\t%s\n' "$host" "$path"
}

main() {
    local opt
    while getopts ':hnr:C:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            n) OFFLINE=1 ;;
            r) REMOTE="$OPTARG" ;;
            C) DIR="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# == 0)) || die "unexpected argument: $1" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    command -v forge >/dev/null 2>&1 || die "forge not found (https://github.com/git-pkgs/forge)"
    local top
    top="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $DIR"

    printf 'forge     %s (%s)\n' "$(forge version 2>/dev/null | head -n 1)" "$(command -v forge)"
    printf 'repo dir  %s\n' "$top"
    if [[ -f "$top/.forge" ]]; then
        printf '.forge    %s\n' "$(grep -vE '^[[:space:]]*(#|;|$)' "$top/.forge" | grep -viE 'token' | paste -sd' ' -)"
        [[ -z "$REMOTE" ]] && REMOTE="$(awk -F'=' '/^\[/{ s = $0 } s == "[default]" && $1 ~ /^[[:space:]]*remote[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$top/.forge")"
    fi
    REMOTE="${REMOTE:-origin}"
    local url
    url="$(git -C "$top" remote get-url "$REMOTE" 2>/dev/null)" || die "git remote '$REMOTE' not found (git remote -v)"
    local parsed host='' slug=''
    if parsed="$(parse_remote "$url")"; then
        host="${parsed%%$'\t'*}"
        slug="${parsed#*$'\t'}"
    else
        warn "could not parse remote URL: $url"
    fi
    printf 'remote    %s -> %s\n' "$REMOTE" "$url"
    printf 'host      %s%s\n' "${FORGE_HOST:-$host}" "${FORGE_HOST:+ (FORGE_HOST; overrides only -R/non-repo commands)}"
    printf 'slug      %s\n' "${slug:-<unknown>}"
    printf 'branch    %s\n' "$(git -C "$top" branch --show-current 2>/dev/null || printf '<detached>')"

    local -a envs=()
    local v
    for v in FORGE_TOKEN GITHUB_TOKEN GH_TOKEN GITLAB_TOKEN GITEA_TOKEN FORGEJO_TOKEN BITBUCKET_TOKEN TANGLED_TOKEN; do
        [[ -n "${!v:-}" ]] && envs+=("$v")
    done
    printf 'env       %s\n' "${envs[*]:-<no token variables set>}"

    local auth='' rc=0
    # Strip "(cmd: …)": a token-cmd line may itself embed a secret.
    auth="$(forge auth status 2>/dev/null | sed -E 's/[[:space:]]*\(cmd:.*\)$/ (token-cmd)/' |
        awk -F': ' -v h="$host" '$1 == h { print $2; exit }')"
    if [[ -z "$auth" ]]; then
        auth="$( ((${#envs[@]})) && printf 'env token may apply' || printf 'no token (host not configured)')"
    fi
    printf 'auth      %s\n' "$auth"
    if [[ "$auth" == 'no token'* ]] && ((${#envs[@]} == 0)); then
        warn "no token for $host: writes will fail; ask the user to run 'forge auth login --domain $host --token-cmd …'"
        rc=3
    fi

    if ((!OFFLINE)); then
        local repo_json pr_json
        if repo_json="$( (cd -- "$top" && forge repo view -o json) 2>/dev/null)"; then
            printf 'api repo  %s\n' "$(jq -r '"\(.full_name) default=\(.default_branch) private=\(.private // "?") \(.html_url)"' <<<"$repo_json" 2>/dev/null)"
        else
            warn "forge repo view failed (auth, network, or unsupported host)"
        fi
        if pr_json="$( (cd -- "$top" && forge pr view -o json) 2>/dev/null)"; then
            printf 'pr        %s\n' "$(jq -r '"#\(.number) \(.state) draft=\(.draft) \(.head.ref) -> \(.base.ref) \(.html_url)"' <<<"$pr_json" 2>/dev/null)"
        else
            printf 'pr        <none for this branch>\n'
        fi
        (cd -- "$top" && forge rate-limit 2>/dev/null) | sed 's/^/ratelimit /' || true
    fi
    exit "$rc"
}

main "$@"
