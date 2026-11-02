#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Search or print the official C3 documentation (c3-lang.org sources, cached
    locally) and print a release's change list from the compiler's release
    notes. The website tracks the compiler's master branch and lags or leads
    the installed version in places: confirm API details with std-find.sh.

Usage:
    ${0##*/} [-h] [-u] [-B] -s <regex>
    ${0##*/} [-h] [-u] -p <page-substring>
    ${0##*/} [-h] [-u] -l
    ${0##*/} [-h] -r <version>

Arguments:
    -h                  Show this usage documentation.
    -u                  Refresh the cached docs/release notes before acting.
    -s <regex>          Case-insensitive search of doc pages; prints page:line: text.
    -B                  Include blog posts (release announcements, design notes) in -s.
    -p <substring>      Print the doc page whose path contains <substring>
                        (e.g. optionals-essential, project-config, c-to-c3).
    -l                  List doc pages.
    -r <version>        Print the release notes section for <version> (e.g. 0.8.5, 0.7.0).

Environment:
    C3_DOCS_CACHE=<dir>   Cache directory (default: \${XDG_CACHE_HOME:-~/.cache}/c3-docs).
    DEBUG=1               Trace execution.

Exit Codes:
    0   output printed
    1   nothing found or download failed
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

CACHE="${C3_DOCS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/c3-docs}"
DOCS_REPO='https://github.com/c3lang/c3-web.git'
NOTES_URL='https://raw.githubusercontent.com/c3lang/c3c/master/releasenotes.md'
REFRESH=0
WITH_BLOG=0
MODE=''
ARG=''

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

ensure_docs() {
    command -v git >/dev/null 2>&1 || die "git is required"
    if [[ ! -d "$CACHE/c3-web/.git" ]]; then
        mkdir -p -- "$CACHE"
        git clone --quiet --depth 1 "$DOCS_REPO" "$CACHE/c3-web" || die "clone failed: $DOCS_REPO"
    elif ((REFRESH)); then
        git -C "$CACHE/c3-web" pull --quiet --ff-only || printf '[warn] docs refresh failed; using cache\n' >&2
    fi
    printf '[info] docs at %s (commit %s) track c3c master\n' "$CACHE/c3-web/docs" \
        "$(git -C "$CACHE/c3-web" log -1 --format='%h %cs')" >&2
}

ensure_notes() {
    local dest="$CACHE/releasenotes.md"
    if [[ ! -s "$dest" ]] || ((REFRESH)) || [[ -n "$(find "$dest" -mmin +1440 -print 2>/dev/null)" ]]; then
        mkdir -p -- "$CACHE"
        curl -fsSL --proto '=https' --max-time 60 "$NOTES_URL" -o "$dest.tmp" || die "download failed: $NOTES_URL"
        mv -f -- "$dest.tmp" "$dest"
    fi
    printf '%s\n' "$dest"
}

search_docs() {
    local docs="$CACHE/c3-web/docs"
    local -a excl=(--exclude-dir=blog)
    ((WITH_BLOG)) && excl=()
    grep -rniE "${excl[@]}" --include='*.md' -- "$ARG" "$docs" | sed "s#^$docs/##" | cut -c1-240 ||
        die "no match for /$ARG/"
}

print_page() {
    local docs="$CACHE/c3-web/docs" f
    local -a hits=()
    while IFS= read -r f; do hits+=("$f"); done < <(find "$docs" -name '*.md' -path "*$ARG*" | sort)
    ((${#hits[@]} > 0)) || die "no page matching '$ARG' (use -l)"
    if ((${#hits[@]} > 1)); then
        printf '[info] %d pages match; showing the first. Others:\n' "${#hits[@]}" >&2
        printf '  %s\n' "${hits[@]:1}" >&2
    fi
    printf '# %s\n' "${hits[0]#"$docs"/}"
    # Drop YAML front matter.
    awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { fm = 0; next } !fm' "${hits[0]}"
}

list_pages() {
    local docs="$CACHE/c3-web/docs"
    find "$docs" -name '*.md' -not -path '*/blog/*' | sed "s#^$docs/##" | sort
}

release_notes() {
    [[ "$ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "-r expects a version like 0.8.5" 2
    local notes
    notes="$(ensure_notes)"
    awk -v want="## $ARG Change list" '
        $0 == want { on = 1; print; next }
        on && /^## [0-9]+\.[0-9]+\.[0-9]+ Change list/ { exit }
        on { print }
    ' "$notes" | grep . || die "no section for $ARG"
}

main() {
    local opt
    while getopts ':huBs:p:lr:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            u) REFRESH=1 ;;
            B) WITH_BLOG=1 ;;
            s) MODE=search; ARG="$OPTARG" ;;
            p) MODE=page; ARG="$OPTARG" ;;
            l) MODE=list ;;
            r) MODE=notes; ARG="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# == 0)) || die "unexpected argument: $1" 2
    [[ -n "$MODE" ]] || { usage >&2; exit 2; }
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    case "$MODE" in
        notes) release_notes ;;
        *)
            ensure_docs
            case "$MODE" in
                search) search_docs ;;
                page) print_page ;;
                list) list_pages ;;
            esac
            ;;
    esac
}

main "$@"
