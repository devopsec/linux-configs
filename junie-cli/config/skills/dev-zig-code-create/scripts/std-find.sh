#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Search the INSTALLED Zig standard library for public declarations so API
    claims are checked against the compiler actually in use, not memory.
    Prints file:line and the declaration (with its doc comment when -d).

Usage:
    ${0##*/} [-h] [-d] [-a] [-b] [-s <std-dir>] <name-regex> [<path-filter>]

Arguments:
    -h              Show this usage documentation.
    -d              Also print the doc comment block above each match.
    -a              Match any line containing the regex, not just pub decls.
    -b              Print the whole body (struct fields, fn body) up to its
                    closing brace, capped at 80 lines, instead of the signature.
    -s <std-dir>    std directory to search (default: from zig-env.sh).
    <name-regex>    Extended regex for the declaration name, e.g. 'readFileAlloc',
                    'Mutex', 'take(Delimiter|Sentinel)'.
    <path-filter>   Optional substring a file path must contain, e.g. 'Io/',
                    'Build', 'array_list'.

Environment:
    ZIG=<path>      Zig binary used to locate std (see zig-env.sh).
    DEBUG=1         Trace execution.

Exit Codes:
    0   at least one match
    1   no match, or std could not be located
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STD_DIR=''
WITH_DOCS=0
ANY_LINE=0
WITH_BODY=0

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Prints the declaration starting at line $2 of file $1 up to its opening brace or
# semicolon (max 20 lines), dropping /// comment lines inside parameter lists.
signature() {
    local file="$1" line="$2"
    awk -v start="$line" '
        NR < start { next }
        NR >= start + 20 { exit }
        NR > start && /^[[:space:]]*\/\/\// { next }
        { sub(/^[[:space:]]+/, "    "); print }
        /[{;][[:space:]]*$/ || /=[[:space:]]*[^=]*;?[[:space:]]*$/ && NR == start { exit }
    ' "$file"
}

# Prints the declaration at line $2 of file $1 through its matching closing brace
# (naive brace count; braces in strings/chars may skew it), max 80 lines.
body() {
    local file="$1" line="$2"
    awk -v start="$line" '
        NR < start { next }
        {
            print
            n = split($0, ch, "")
            for (i = 1; i <= n; i++) {
                if (ch[i] == "/" && ch[i + 1] == "/") break
                if (ch[i] == "{") { depth++; opened = 1 }
                if (ch[i] == "}") depth--
            }
            if ((opened && depth <= 0) || (!opened && /;[[:space:]]*$/)) exit
            if (NR >= start + 79) { print "    ... (truncated)"; exit }
        }
    ' "$file"
}

# Prints the contiguous /// or //! comment block ending just above line $2 of file $1.
doc_block() {
    local file="$1" line="$2"
    awk -v stop="$line" '
        NR < stop && /^[[:space:]]*\/\/[\/!]/ { buf = buf $0 "\n"; next }
        NR < stop { buf = ""; next }
        NR == stop { printf "%s", buf; exit }
    ' "$file"
}

main() {
    local opt
    while getopts ':hdabs:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            d) WITH_DOCS=1 ;;
            a) ANY_LINE=1 ;;
            b) WITH_BODY=1 ;;
            s) STD_DIR="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# >= 1 && $# <= 2)) || { usage >&2; exit 2; }
    local name="$1" filter="${2:-}"
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    if [[ -z "$STD_DIR" ]]; then
        STD_DIR="$("$SCRIPT_DIR/zig-env.sh" -f std_dir)" || die "could not locate std (pass -s)"
    fi
    [[ -d "$STD_DIR" ]] || die "not a directory: $STD_DIR"

    local pattern
    if ((ANY_LINE)); then
        pattern="$name"
    else
        # pub fn/const/var at any nesting depth; also `pub inline fn`.
        pattern="^[[:space:]]*pub[[:space:]]+((inline|extern|export)[[:space:]]+)?(fn|const|var)[[:space:]]+(${name})\\b"
    fi

    local found=0 file lineno text
    while IFS=: read -r file lineno text; do
        [[ -z "$filter" || "$file" == *"$filter"* ]] || continue
        found=1
        if ((WITH_DOCS)); then
            printf '\n%s:%s\n' "${file#"$STD_DIR"/}" "$lineno"
            doc_block "$file" "$lineno"
        else
            printf '%s:%s:\n' "${file#"$STD_DIR"/}" "$lineno"
        fi
        if ((WITH_BODY)); then
            body "$file" "$lineno"
        elif ((ANY_LINE)); then
            printf '    %s\n' "${text#"${text%%[![:space:]]*}"}"
        else
            signature "$file" "$lineno"
        fi
    done < <(grep -rnE --include='*.zig' -- "$pattern" "$STD_DIR" | sort -t: -k1,1 -k2,2n)

    ((found)) || { printf 'no match for /%s/ in %s\n' "$name" "$STD_DIR" >&2; exit 1; }
}

main "$@"
