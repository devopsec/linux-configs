#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Maintain a local cache of upstream COSMIC sources (pop-os GitHub org) and
    inspect them so code is written against the libcosmic revision a project
    actually builds with.

Usage:
    ${0##*/} [-h] sync [--apps] [--all] [<repo>...]
    ${0##*/} [-h] status
    ${0##*/} [-h] rev [<project-dir>]
    ${0##*/} [-h] pin [<project-dir>]
    ${0##*/} [-h] grep [-l <max-lines>] <regex> [<repo>...]

Commands:
    sync      Shallow-clone or fast-forward repos into the cache.
              Default set: ${CORE_REPOS[*]}
              --apps  also: ${APP_REPOS[*]}
              --all   also: ${EXTRA_REPOS[*]}
              Explicit <repo> names (pop-os/<repo>) may be given instead.
    status    Show cached repos with commit, date, and branch/detached state.
    rev       Print libcosmic commit + features + toolchain for a project
              (reads Cargo.lock, Cargo.toml, rust-toolchain.toml). Default dir: .
    pin       Check out the project's locked libcosmic commit in the cache
              (detached HEAD). 'sync libcosmic' returns it to the default branch.
    grep      Extended-regex search (git grep) over cached repos' *.rs, *.toml,
              *.md, *.desktop, *.xml, *.json, justfile. Default: all cached repos.

Arguments:
    -h                Show this usage documentation.
    -l <max-lines>    grep: maximum output lines (default 200, max 5000).

Environment:
    COSMIC_SRC_CACHE  Cache dir (default: \${XDG_CACHE_HOME:-\$HOME/.cache}/cosmic-dev-src).
    DEBUG=1           Trace execution.

Examples:
    ${0##*/} sync --apps
    ${0##*/} rev ~/src/cosmic-ext-foo && ${0##*/} pin ~/src/cosmic-ext-foo
    ${0##*/} grep 'fn context_drawer' libcosmic cosmic-edit
    ${0##*/} grep -l 50 'file_chooser::open::Dialog'

Exit Codes:
    0   ok
    1   failure (network, git, missing data)
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

CORE_REPOS=(libcosmic cosmic-app-template cosmic-applet-template libcosmic-book cosmic-epoch)
APP_REPOS=(cosmic-edit cosmic-files cosmic-term cosmic-store cosmic-settings cosmic-applets cosmic-panel)
EXTRA_REPOS=(cosmic-flatpak xdg-desktop-portal-cosmic cosmic-protocols cosmic-text cosmic-workspaces-epoch)
GITHUB_ORG_URL='https://github.com/pop-os'
CACHE_DIR="${COSMIC_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cosmic-dev-src}"
REPO_NAME_RE='^(libcosmic|libcosmic-book|cosmic-[a-z0-9-]+|xdg-desktop-portal-cosmic|launcher)$'

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "error: $1"; exit "${2:-1}"; }

require() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || die "missing dependency: $cmd"
    done
}

valid_repo() {
    [[ "$1" =~ $REPO_NAME_RE ]] || die "invalid repo name '$1' (pop-os repos only: libcosmic*, cosmic-*, xdg-desktop-portal-cosmic)" 2
}

cached_repos() {
    local d
    for d in "$CACHE_DIR"/*/; do
        [[ -d "$d/.git" ]] && basename "$d"
    done
}

sync_repo() {
    local name="$1" dir="$CACHE_DIR/$1" default_branch
    valid_repo "$name"
    if [[ -d "$dir/.git" ]]; then
        default_branch="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo 'origin/master')"
        default_branch="${default_branch#origin/}"
        log "updating $name ($default_branch)"
        git -C "$dir" fetch --quiet --depth 1 origin "$default_branch"
        git -C "$dir" checkout --quiet --force -B "$default_branch" FETCH_HEAD
    else
        log "cloning $name"
        git clone --quiet --depth 1 "$GITHUB_ORG_URL/$name.git" "$dir"
    fi
    printf '%-28s %s\n' "$name" "$(git -C "$dir" log -1 --format='%h %cs')"
}

cmd_sync() {
    local -a repos=() unique=()
    local arg name failed=0 explicit=0
    for arg in "$@"; do
        case "$arg" in
            --apps) repos+=("${APP_REPOS[@]}") ;;
            --all) repos+=("${APP_REPOS[@]}" "${EXTRA_REPOS[@]}") ;;
            -*) die "unknown sync option: $arg" 2 ;;
            *) valid_repo "$arg"; repos+=("$arg"); explicit=1 ;;
        esac
    done
    # Explicit repo names replace the core set; flags only add to it.
    if (( explicit == 0 )); then
        repos=("${CORE_REPOS[@]}" "${repos[@]}")
    fi
    mapfile -t unique < <(printf '%s\n' "${repos[@]}" | awk '!seen[$0]++')
    mkdir -p "$CACHE_DIR"
    for name in "${unique[@]}"; do
        sync_repo "$name" || { log "failed: $name"; failed=1; }
    done
    return "$failed"
}

cmd_status() {
    local name dir head
    [[ -d "$CACHE_DIR" ]] || die "cache empty: $CACHE_DIR (run: ${0##*/} sync)"
    printf 'cache: %s\n' "$CACHE_DIR"
    while read -r name; do
        dir="$CACHE_DIR/$name"
        head="$(git -C "$dir" symbolic-ref --short -q HEAD || echo 'detached')"
        printf '%-28s %s  [%s]\n' "$name" "$(git -C "$dir" log -1 --format='%h %cs %s' | cut -c1-80)" "$head"
    done < <(cached_repos)
}

# Prints the locked libcosmic commit for project dir $1 (empty if none).
locked_rev() {
    local lock="$1/Cargo.lock"
    [[ -f "$lock" ]] || die "no Cargo.lock in $1 (run: cargo generate-lockfile)"
    awk '
        /^\[\[package\]\]/ { inpkg = 0 }
        /^name = "libcosmic"$/ { inpkg = 1 }
        inpkg && /^source = "git\+https:\/\/github.com\/pop-os\/libcosmic/ {
            n = split($0, parts, "#"); sub(/"$/, "", parts[n]); print parts[n]; exit
        }
    ' "$lock"
}

cmd_rev() {
    local dir="${1:-.}" rev toml
    [[ -d "$dir" ]] || die "not a directory: $dir" 2
    dir="$(realpath "$dir")"
    rev="$(locked_rev "$dir")"
    [[ -n "$rev" ]] || die "libcosmic (git) not found in $dir/Cargo.lock"
    printf 'project:          %s\n' "$dir"
    printf 'libcosmic commit: %s\n' "$rev"
    printf 'browse:           https://github.com/pop-os/libcosmic/tree/%s\n' "$rev"
    if [[ -d "$CACHE_DIR/libcosmic/.git" ]]; then
        printf 'cache HEAD:       %s\n' "$(git -C "$CACHE_DIR/libcosmic" rev-parse HEAD)"
    fi
    for toml in "$dir/Cargo.toml" "$dir"/*/Cargo.toml; do
        grep -q 'libcosmic' "$toml" 2>/dev/null || continue
        printf '\n# libcosmic dependency in %s\n' "${toml#"$dir"/}"
        awk '
            /^\[(workspace\.)?dependencies\.libcosmic\]/ { show = 1; print; next }
            /^\[/ { show = 0 }
            show { print }
            /^libcosmic[.[:space:]=]/ { print }
        ' "$toml"
    done
    if [[ -f "$dir/rust-toolchain.toml" ]]; then
        printf '\n# rust-toolchain.toml\n'
        cat "$dir/rust-toolchain.toml"
    elif [[ -f "$dir/rust-toolchain" ]]; then
        printf '\n# rust-toolchain: %s\n' "$(<"$dir/rust-toolchain")"
    else
        printf '\n# no rust-toolchain pin; rustc %s\n' "$(rustc --version 2>/dev/null | awk '{print $2}')"
    fi
}

cmd_pin() {
    local dir="${1:-.}" rev lc="$CACHE_DIR/libcosmic" msrv
    [[ -d "$dir" ]] || die "not a directory: $dir" 2
    rev="$(locked_rev "$(realpath "$dir")")"
    [[ "$rev" =~ ^[0-9a-f]{7,40}$ ]] || die "could not resolve libcosmic commit from Cargo.lock"
    [[ -d "$lc/.git" ]] || sync_repo libcosmic >/dev/null
    log "fetching libcosmic $rev"
    git -C "$lc" fetch --quiet --depth 1 origin "$rev"
    git -C "$lc" checkout --quiet --detach FETCH_HEAD
    msrv="$(awk -F'"' '/^rust-version/ {print $2; exit}' "$lc/Cargo.toml")"
    printf 'libcosmic cache pinned to %s (rust-version %s)\n' "$(git -C "$lc" log -1 --format='%h %cs')" "${msrv:-unknown}"
    printf 'examples: %s/examples\n' "$lc"
}

cmd_grep() {
    local max=200 pattern name
    local -a repos=()
    local OPTIND=1 opt
    while getopts ':l:' opt; do
        case "$opt" in
            l) max="$OPTARG" ;;
            *) die "usage: grep [-l N] <regex> [repo...]" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    if ! [[ "$max" =~ ^[1-9][0-9]{0,3}$ ]] || (( max > 5000 )); then
        die "-l must be 1..5000" 2
    fi
    (( $# >= 1 )) || die "missing <regex>" 2
    pattern="$1"; shift
    if (( $# > 0 )); then
        for name in "$@"; do valid_repo "$name"; repos+=("$name"); done
    else
        mapfile -t repos < <(cached_repos)
    fi
    (( ${#repos[@]} > 0 )) || die "cache empty: run '${0##*/} sync' first"
    for name in "${repos[@]}"; do
        [[ -d "$CACHE_DIR/$name/.git" ]] || { log "not cached: $name (skipping)"; continue; }
        git -C "$CACHE_DIR/$name" grep --line-number --extended-regexp -e "$pattern" -- \
            '*.rs' '*.toml' '*.md' '*.desktop' '*.xml' '*.json' '*justfile' '*.just' \
            | sed "s|^|$name/|" || true
    done | head -n "$max"
}

main() {
    local cmd
    if [[ "${1:-}" == '-h' || "${1:-}" == '--help' || $# -eq 0 ]]; then
        usage
        [[ $# -eq 0 ]] && exit 2
        exit 0
    fi
    if [[ "${DEBUG:-0}" == 1 ]]; then set -x; fi
    require git awk
    cmd="$1"; shift
    case "$cmd" in
        sync) cmd_sync "$@" ;;
        status) cmd_status "$@" ;;
        rev) cmd_rev "$@" ;;
        pin) cmd_pin "$@" ;;
        grep) cmd_grep "$@" ;;
        *) die "unknown command: $cmd" 2 ;;
    esac
}

main "$@"
