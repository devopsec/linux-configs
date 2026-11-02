#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Find public declarations (fn, struct, enum, trait, type, const, static,
    mod, union, macro; plus trait/impl methods) by name in the Rust standard library source (rust-src
    of the active toolchain) or in a dependency at the exact version resolved
    in the project's Cargo.lock. Prints file:line, the enclosing impl/trait,
    attributes (std shows #[stable(since = "1.xx")] -> MSRV), and optionally
    doc comments and the body. Read-only; never downloads crates.

Usage:
    ${0##*/} [-h] [-c <crate>] [-p <project-dir>] [-d] [-b] [-a] [-n <max>] <regex> [<path-filter>]

Arguments:
    -h              Show this usage documentation.
    -c <crate>      Search this dependency (Cargo package name, e.g. tokio,
                    serde_json) instead of std/core/alloc. Use 'std' for std.
    -p <dir>        Project whose Cargo.lock selects the crate version (default: .).
    -d              Include preceding /// doc comments.
    -b              Include the declaration body (up to 30 lines).
    -a              Match <regex> anywhere on a line (e.g. 'deprecated',
                    'since = "1.9[0-9]') instead of only declaration names.
    -n <max>        Stop after this many matches (default: 25).
    <regex>         Extended regex for the item name (anchored as a word).
    <path-filter>   Only files whose path contains this substring (e.g. sync/, net).

Environment:
    RUSTUP_TOOLCHAIN=<name>  Toolchain whose rust-src is searched (e.g. nightly).
    DEBUG=1                  Trace execution.

Exit Codes:
    0   at least one match
    1   no match, or the source could not be located
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

# Never let rustup download a toolchain as a side effect of this report.
export RUSTUP_AUTO_INSTALL=0

CRATE='std'
PROJECT='.'
DOCS=0
BODY=0
ANYWHERE=0
MAX=25

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Prints "<label>\t<dir>" lines for every source root to search.
source_roots() {
    if [[ "$CRATE" == std || "$CRATE" == core || "$CRATE" == alloc ]]; then
        local lib
        lib="$(rustc --print sysroot)/lib/rustlib/src/rust/library"
        [[ -d "$lib" ]] || die "rust-src not installed for $(rustc -V); ask before 'rustup component add rust-src', or retry with RUSTUP_TOOLCHAIN=nightly if that has it"
        local c
        for c in std core alloc; do printf '%s@%s\t%s\n' "$c" "$(rustc -V | awk '{ print $2 }')" "$lib/$c"; done
        return 0
    fi
    [[ -f "$PROJECT/Cargo.toml" ]] || die "no Cargo.toml in $PROJECT (use -p)" 2
    command -v jq >/dev/null 2>&1 || die "jq is required to read cargo metadata"
    local meta
    meta="$(cargo metadata --format-version 1 --offline --manifest-path "$PROJECT/Cargo.toml" 2>/dev/null)" ||
        die "cargo metadata failed offline; run 'cargo fetch' (network) first or check Cargo.lock"
    jq -r --arg n "$CRATE" '.packages[] | select(.name == $n or (.name | gsub("-"; "_")) == $n)
        | "\(.name)@\(.version)\t\(.manifest_path | sub("/Cargo.toml$"; ""))"' <<<"$meta"
}

# Prints context for one hit: enclosing impl/trait, attributes, docs, declaration, body.
show_hit() {
    local file="$1" line="$2"
    awk -v L="$line" -v docs="$DOCS" -v body="$BODY" '
        function indent(s) { match(s, /^[[:space:]]*/); return RLENGTH }
        NR < L { buf[NR] = $0; next }
        NR == L {
            d = indent($0); start = L
            for (i = L - 1; i >= 1 && i > L - 80; i--) {
                t = buf[i]; sub(/^[[:space:]]+/, "", t)
                if (t ~ /^(#\[|#!\[|\/\/\/|\)\]|\]$)/ || t ~ /(feature|since|reason|issue|note) *=/) { start = i; continue }
                break
            }
            if (d > 0) {
                for (i = L - 1; i >= 1; i--) {
                    if (indent(buf[i]) < d && buf[i] ~ /^[[:space:]]*(pub[^ ]* )?(unsafe )?(impl|trait)[ <]/) {
                        t = buf[i]; sub(/^[[:space:]]+/, "", t); printf "    in: %s\n", t; break
                    }
                    if (indent(buf[i]) == 0 && buf[i] ~ /^[}a-z]/ && buf[i] !~ /^where/) break
                }
            }
            for (i = start; i < L; i++) {
                t = buf[i]; sub(/^[[:space:]]+/, "", t)
                if (t ~ /^\/\/\// && !docs) continue
                printf "    %s\n", t
            }
            t = $0; sub(/^[[:space:]]+/, "", t); printf "    %s\n", t
            depth = gsub(/\{/, "{") - gsub(/\}/, "}")
            if (!body || depth <= 0 || $0 ~ /;[[:space:]]*$/) exit
            n = 0; next
        }
        NR > L {
            t = $0; sub(/^[[:space:]]{0,4}/, "", t); printf "    %s\n", t
            depth += gsub(/\{/, "{") - gsub(/\}/, "}")
            if (depth <= 0 || ++n >= 30) exit
        }
    ' "$file"
}

main() {
    local opt
    while getopts ':hc:p:dban:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            c) CRATE="$OPTARG" ;;
            p) PROJECT="$OPTARG" ;;
            d) DOCS=1 ;;
            b) BODY=1 ;;
            a) ANYWHERE=1 ;;
            n) [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]] || die "-n needs a positive integer" 2
               MAX="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# >= 1 && $# <= 2)) || { usage >&2; exit 2; }
    local name="$1" filter="${2:-}"
    [[ -d "$PROJECT" ]] || die "not a directory: $PROJECT" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x
    command -v rustc >/dev/null 2>&1 || die "rustc not found"

    local pattern
    if ((ANYWHERE)); then
        pattern="$name"
    else
        pattern="^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)((const|async|unsafe|safe|default|extern[[:space:]]+\"[^\"]*\")[[:space:]]+)*(fn|struct|enum|trait|type|const|static|mod|union|macro)[[:space:]]+($name)([^[:alnum:]_]|$)|^[[:space:]]+((const|async|unsafe|default|extern[[:space:]]+\"[^\"]*\")[[:space:]]+)*fn[[:space:]]+($name)([^[:alnum:]_]|$)|macro_rules![[:space:]]*($name)([^[:alnum:]_]|$)"
    fi

    local roots_out
    roots_out="$(source_roots)" || exit "$?"
    [[ -n "$roots_out" ]] || die "package '$CRATE' is not in the dependency graph of $PROJECT"
    local -a roots=()
    mapfile -t roots <<<"$roots_out"

    local root label dir hits=0 file line
    for root in "${roots[@]}"; do
        label="${root%%$'\t'*}"
        dir="${root#*$'\t'}"
        while IFS=: read -r file line _; do
            [[ -z "$filter" || "$file" == *"$filter"* ]] || continue
            ((hits < MAX)) || break 2
            ((hits += 1))
            printf '%s  %s:%s\n' "$label" "${file#"$dir"/}" "$line"
            if ((ANYWHERE)); then
                sed -n "${line},$((line + 2))s/^[[:space:]]*/    /p" "$file"
            else
                show_hit "$file" "$line"
            fi
        done < <(grep -rnE --include='*.rs' -- "$pattern" "$dir" 2>/dev/null |
            grep -vE '/(tests|benches|examples)/|/library/[a-z]+/src/sys/' || true)
    done
    if ((hits == 0)); then
        printf 'no match for /%s/ in %s\n' "$name" "$CRATE" >&2
        exit 1
    fi
    ((hits < MAX)) || printf '... stopped at %d matches (-n to raise, or add a path filter)\n' "$MAX"
}

main "$@"
