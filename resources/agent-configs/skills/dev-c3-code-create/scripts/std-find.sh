#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Search the INSTALLED C3 standard library for declarations so API claims
    are checked against the compiler actually in use, not memory or the
    website. Prints file:line, the module, and the declaration (optionally
    its <* *> doc contract or its full body).

Usage:
    ${0##*/} [-h] [-d] [-b] [-a] [-k <kind>] [-s <stdlib-dir>] <name-regex> [<path-filter>]

Arguments:
    -h              Show this usage documentation.
    -d              Also print the <* ... *> doc/contract block above each match.
    -b              Print the whole body up to the closing brace (max 80 lines).
    -a              Match any line containing the regex (e.g. fault names, usages).
    -k <kind>       Restrict to: fn (functions, macros, methods), type, const. Default: all.
    -s <dir>        stdlib directory (default: from c3-env.sh).
    <name-regex>    Extended regex for the name. Methods: 'List\.push', 'push'.
                    Types: 'DString', 'Allocator'. Macros: '@pool', 'tmalloc'.
    <path-filter>   Optional substring the file path must contain, e.g. 'io/', 'net', 'collections'.

Environment:
    C3C=<path>      c3c binary used to locate the stdlib (see c3-env.sh).
    C3C_LIB=<dir>   stdlib override, as for c3c.
    DEBUG=1         Trace execution.

Exit Codes:
    0   at least one match
    1   no match, or stdlib could not be located
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STDLIB=''
WITH_DOCS=0
WITH_BODY=0
ANY_LINE=0
KIND='all'

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Prints the <* ... *> block that ends on the line before $2 (blank lines between allowed).
doc_block() {
    awk -v stop="$2" '
        NR < stop { lines[NR] = $0; next }
        NR == stop {
            end = stop - 1
            while (end > 0 && lines[end] ~ /^[[:space:]]*$/) end--
            if (end < 1 || lines[end] !~ /\*>[[:space:]]*$/) exit
            start = end
            while (start > 0 && lines[start] !~ /<\*/) start--
            if (start < 1) exit
            for (i = start; i <= end; i++) print lines[i]
            exit
        }
    ' "$1"
}

# Prints the declaration through its opening '{', '=>' expression end, or ';' (max 20 lines).
signature() {
    awk -v start="$2" '
        NR < start { next }
        NR >= start + 20 { exit }
        { print }
        /\{[[:space:]]*(\/\/.*)?$/ || /;[[:space:]]*(\/\/.*)?$/ { exit }
    ' "$1"
}

# Prints the declaration through the matching closing brace (naive count), max 80 lines.
body() {
    awk -v start="$2" '
        NR < start { next }
        {
            print
            line = $0
            sub(/\/\/.*/, "", line)
            n = split(line, ch, "")
            for (i = 1; i <= n; i++) {
                if (ch[i] == "{") { depth++; opened = 1 }
                if (ch[i] == "}") depth--
            }
            if ((opened && depth <= 0) || (!opened && line ~ /;[[:space:]]*$/)) exit
            if (NR >= start + 79) { print "    ... (truncated)"; exit }
        }
    ' "$1"
}

module_of() {
    awk '/^[[:space:]]*module[[:space:]]/ { sub(/^[[:space:]]*module[[:space:]]+/, ""); sub(/;.*/, ""); print; exit }' "$1"
}

build_pattern() {
    local name="$1"
    local fn_re="^[[:space:]]*(extern[[:space:]]+)?(fn|macro)[[:space:]]+([^(=]*[[:space:].])?(${name})[[:space:]]*(\\(|<)"
    local type_re="^[[:space:]]*(struct|union|enum|bitstruct|typedef|alias|interface|constset|constdef|attrmacro|attrdef)[[:space:]]+(${name})([^[:alnum:]_]|$)"
    local const_re="^[[:space:]]*const[[:space:]]+([^=]*[[:space:]])?(${name})[[:space:]]*="
    case "$KIND" in
        fn) printf '%s' "$fn_re" ;;
        type) printf '%s' "$type_re" ;;
        const) printf '%s' "$const_re" ;;
        all) printf '(%s)|(%s)|(%s)' "$fn_re" "$type_re" "$const_re" ;;
        *) die "unknown kind: $KIND (fn, type, const)" 2 ;;
    esac
}

main() {
    local opt
    while getopts ':hdbak:s:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            d) WITH_DOCS=1 ;;
            b) WITH_BODY=1 ;;
            a) ANY_LINE=1 ;;
            k) KIND="$OPTARG" ;;
            s) STDLIB="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# >= 1 && $# <= 2)) || { usage >&2; exit 2; }
    local name="$1" filter="${2:-}"
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    if [[ -z "$STDLIB" ]]; then
        STDLIB="$("$SCRIPT_DIR/c3-env.sh" -f stdlib)" || die "could not locate the stdlib (pass -s)"
    fi
    [[ -d "$STDLIB" ]] || die "not a directory: $STDLIB"

    local pattern
    if ((ANY_LINE)); then pattern="$name"; else pattern="$(build_pattern "$name")"; fi

    local found=0 file lineno text
    while IFS=: read -r file lineno text; do
        [[ -z "$filter" || "$file" == *"$filter"* ]] || continue
        found=1
        printf '\n%s:%s  [module %s]\n' "${file#"$STDLIB"/}" "$lineno" "$(module_of "$file")"
        ((WITH_DOCS)) && doc_block "$file" "$lineno"
        if ((ANY_LINE)); then
            printf '%s\n' "$text"
        elif ((WITH_BODY)); then
            body "$file" "$lineno"
        else
            signature "$file" "$lineno"
        fi
    done < <(grep -rnE --include='*.c3' --include='*.c3i' -- "$pattern" "$STDLIB" | sort -t: -k1,1 -k2,2n)

    ((found)) || { printf 'no match for /%s/ in %s\n' "$name" "$STDLIB" >&2; exit 1; }
}

main "$@"
