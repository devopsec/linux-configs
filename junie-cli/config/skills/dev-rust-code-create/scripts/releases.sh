#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Print Rust release notes from the active toolchain's local releases.md
    (rust-docs component) for one version or a version range, optionally only
    some sections, or grep them for an item ("when was X stabilized?").
    Markdown link targets are stripped for compact output.

Usage:
    ${0##*/} [-h] [-l] [-u] [-s <section-regex>] [-g <regex>] [<version> | <from>..<to>]

Arguments:
    -h                 Show this usage documentation.
    -l                 List versions with release dates and exit.
    -u                 Keep link URLs (PR/issue links).
    -s <regex>         Only sections whose heading matches, case-insensitive
                       (e.g. 'language|stabilized', cargo, compat).
    -g <regex>         Only bullet lines matching (ERE, case-insensitive);
                       each hit is prefixed with its version and section.
    <version>          1.95 (all 1.95.x) or 1.95.1. Default: the active rustc
                       (all versions when -g is given).
    <from>..<to>       Inclusive range, e.g. 1.85..1.99 or 1.88.. (to latest).

Environment:
    RUSTUP_TOOLCHAIN=<name>  Toolchain whose releases.md is read.
    RELEASES_MD=<path>       Read this file instead.
    DEBUG=1                  Trace execution.

Exit Codes:
    0   output produced
    1   releases.md not found or nothing matched
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

LIST=0
KEEP_URLS=0
SECTION=''
GREP=''

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Normalizes "1.95" -> "1.95.0" for range comparisons.
full_version() {
    local v="$1"
    [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]] && v="$v.0"
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    printf '%s\n' "$v"
}

main() {
    local opt
    while getopts ':hlus:g:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            l) LIST=1 ;;
            u) KEEP_URLS=1 ;;
            s) SECTION="$OPTARG" ;;
            g) GREP="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# <= 1)) || die "expected one version or range" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    local md="${RELEASES_MD:-}"
    if [[ -z "$md" ]]; then
        command -v rustc >/dev/null 2>&1 || die "rustc not found; set RELEASES_MD=<path>"
        md="$(rustc --print sysroot)/share/doc/rust/html/releases.md"
    fi
    [[ -f "$md" ]] || die "releases.md not found at $md (rust-docs component missing?); online: https://doc.rust-lang.org/stable/releases.html"

    if ((LIST)); then
        sed -nE 's/^Version ([0-9.]+) \(([0-9-]+)\).*/\1  \2/p' "$md"
        exit 0
    fi

    local spec="${1:-}" from='' to='' prefix=''
    if [[ -z "$spec" && -n "$GREP" ]]; then
        spec='1.0..'
    elif [[ -z "$spec" ]]; then
        spec="$(rustc -V | awk '{ print $2 }')"
        spec="${spec%%-*}"
    fi
    if [[ "$spec" == *..* ]]; then
        from="$(full_version "${spec%%..*}")" || die "bad range start: $spec" 2
        to="${spec#*..}"
        if [[ -n "$to" ]]; then
            [[ "$to" =~ ^[0-9]+\.[0-9]+$ ]] && to="$to.99"
            [[ "$to" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad range end: $spec" 2
        else
            to='999.0.0'
        fi
    elif [[ "$spec" =~ ^[0-9]+\.[0-9]+$ ]]; then
        prefix="$spec."
    elif [[ "$spec" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        from="$spec"
        to="$spec"
    else
        die "bad version: $spec (expected 1.95, 1.95.1 or 1.85..1.99)" 2
    fi

    awk -v prefix="$prefix" -v from="$from" -v to="$to" -v sect="$SECTION" -v pat="$GREP" -v urls="$KEEP_URLS" '
        function vnum(v,   a) { split(v, a, "."); return a[1] * 1000000 + a[2] * 1000 + a[3] }
        function wanted(v) {
            if (prefix != "") return index(v ".", prefix) == 1 || index(v, prefix) == 1
            return vnum(v) >= vnum(from) && vnum(v) <= vnum(to)
        }
        /^Version [0-9]+\.[0-9]+\.[0-9]+/ {
            ver = $2; inv = wanted(ver); cur = ""; insect = (sect == "")
            if (inv && pat == "") { print ""; print $0; print "==========================" }
            next
        }
        !inv { next }
        /^[A-Z][A-Za-z -]+$/ {
            cur = $0; insect = (sect == "" || tolower(cur) ~ tolower(sect))
            if (insect && pat == "") { print ""; print cur; print "--------" }
            next
        }
        /^-+$|^=+$|^<a id=/ { next }
        !insect { next }
        /^\[[^]]+\]: / { next }
        {
            line = $0
            if (!urls) { gsub(/\]\([^)]*\)/, "]", line); gsub(/\]\[[^]]*\]/, "]", line) }
            if (pat != "") {
                if (line !~ /^[[:space:]]*[-*] / || tolower(line) !~ tolower(pat)) next
                printf "%s %s: %s\n", ver, cur, line; found = 1; next
            }
            print line; found = 1
        }
        END { exit !found }
    ' "$md" || die "nothing matched for '$spec'${GREP:+ /$GREP/}${SECTION:+ section /$SECTION/}"
}

main "$@"
