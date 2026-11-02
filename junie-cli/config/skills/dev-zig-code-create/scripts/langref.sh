#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Print one section of the Zig language reference as plain text, or list
    section titles. Uses the langref shipped with the installed compiler, or
    downloads a specific version's langref into a cache when -u is given.

Usage:
    ${0##*/} [-h] [-l] [-u <version>] [<section-title>]

Arguments:
    -h              Show this usage documentation.
    -l              List section titles instead of printing a section.
    -u <version>    Use https://ziglang.org/documentation/<version>/ (e.g. 0.16.0,
                    master) instead of the local file. Cached for 1 day.
    <section-title> Case-insensitive title prefix, e.g. '@splat', 'Slices',
                    'Result Location Semantics'. All matching sections print.

Environment:
    ZIG=<path>                Zig binary used to find the local langref.
    ZIG_LANGREF_CACHE=<dir>   Download cache (default: \${XDG_CACHE_HOME:-~/.cache}/zig-langref).
    DEBUG=1                   Trace execution.

Exit Codes:
    0   section(s) printed / list printed
    1   no langref available or no matching section
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${ZIG_LANGREF_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/zig-langref}"
LIST=0
REMOTE=''

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

fetch_remote() {
    local version="$1" dest
    [[ "$version" =~ ^(master|[0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "bad version: $version" 2
    dest="$CACHE_DIR/langref-$version.html"
    if [[ ! -s "$dest" || -n "$(find "$dest" -mmin +1440 -print 2>/dev/null)" ]]; then
        mkdir -p -- "$CACHE_DIR"
        curl -fsSL --proto '=https' --max-time 60 \
            "https://ziglang.org/documentation/$version/" -o "$dest.tmp" ||
            die "download failed for $version"
        mv -f -- "$dest.tmp" "$dest"
    fi
    printf '%s\n' "$dest"
}

# Converts langref HTML to text with '## Title' headings (stdin: none; $1 html, $2 mode, $3 query).
render() {
    python3 -I - "$@" <<'PY'
import html, re, sys

src, mode, query = sys.argv[1], sys.argv[2], sys.argv[3].lower()
text = open(src, encoding="utf-8").read()
text = re.sub(r"(?s)<(script|style)[^>]*>.*?</\1>", "", text)
text = re.sub(r"<h([1-4])[^>]*>", lambda m: "\n" + "#" * int(m.group(1)) + " ", text)
text = re.sub(r"<br\s*/?>|</(p|div|li|tr|pre)>", "\n", text)
text = html.unescape(re.sub(r"<[^>]+>", "", text))
text = re.sub(r" §", "", text)
text = re.sub(r"(?m)^ {6}(?=\S)", "", text)  # HTML source indentation, not code
text = re.sub(r"(?m)[ \t]+$", "", text)
text = re.sub(r"\n{3,}", "\n\n", text)
lines = text.splitlines()
heads = [(i, l) for i, l in enumerate(lines) if re.match(r"#{1,4} \S", l)]
if mode == "list":
    for _, l in heads:
        print(l)
    sys.exit(0)
hits = 0
for n, (i, l) in enumerate(heads):
    title = l.lstrip("#").strip().lower()
    if not title.startswith(query):
        continue
    level = len(l) - len(l.lstrip("#"))
    end = len(lines)
    for j, l2 in heads[n + 1:]:
        if len(l2) - len(l2.lstrip("#")) <= level:
            end = j
            break
    print("\n".join(lines[i:end]).strip() + "\n")
    hits += 1
sys.exit(0 if hits else 1)
PY
}

main() {
    local opt
    while getopts ':hlu:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            l) LIST=1 ;;
            u) REMOTE="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    local query="${1:-}"
    ((LIST)) || [[ -n "$query" ]] || { usage >&2; exit 2; }
    [[ "${DEBUG:-0}" == 1 ]] && set -x
    command -v python3 >/dev/null 2>&1 || die "python3 is required"

    local html
    if [[ -n "$REMOTE" ]]; then
        html="$(fetch_remote "$REMOTE")"
    else
        html="$("$SCRIPT_DIR/zig-env.sh" -f langref)" ||
            die "no local langref; retry with -u <version> (see zig-env.sh)"
    fi
    if ((LIST)); then
        render "$html" list ''
    else
        render "$html" section "$query" || die "no section titled '$query*'"
    fi
}

main "$@"
