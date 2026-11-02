#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only report of the C3 toolchain an agent must target: c3c path and
    version, the standard library directory it compiles against, and the
    nearest project.json (targets, dependencies) plus any c3c version pinned
    in CI files. Warns when the installed and pinned versions differ.

Usage:
    ${0##*/} [-h] [-f <field>] [<project-dir>]

Arguments:
    -h            Show this usage documentation.
    -f <field>    Print one value and exit: c3c, version, series, stdlib, project,
                  pinned.
    <project-dir> Directory to start the upward project.json search (default: .).

Environment:
    C3C=<path>      c3c binary to inspect (default: first 'c3c' on PATH).
    C3C_LIB=<dir>   Overrides the stdlib location, exactly as c3c itself does.
    DEBUG=1         Trace execution.

Exit Codes:
    0   toolchain found (warnings may remain)
    1   c3c not found or its stdlib could not be located
    2   usage error
    3   installed version differs from a version pinned by the project
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

C3C_BIN="${C3C:-c3c}"
FIELD=''
C3C_PATH=''
VERSION=''
STDLIB=''
PROJECT_FILE=''
PINNED=''
PINNED_FROM=''

warn() { printf '[warn] %s\n' "$*" >&2; }
die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# "0.8" for "0.8.5", "0.8.5_1", "0.8.6 (Pre-release ...)".
series_of() {
    [[ "$1" =~ ^([0-9]+)\.([0-9]+) ]] || return 1
    printf '%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

# "0.8.5" for "0.8.5_1" (C3 breaks APIs in patch releases, so compare x.y.z).
release_of() {
    [[ "$1" =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

# Mirrors find_lib_dir() in c3c's src/utils/file_utils.c (0.8.5).
resolve_stdlib() {
    if [[ -n "${C3C_LIB:-}" ]]; then
        STDLIB="${C3C_LIB%/}/std"
        [[ -d "$STDLIB" ]] || STDLIB="${C3C_LIB%/}"
        return 0
    fi
    local exe_dir rel
    exe_dir="$(dirname -- "$(readlink -f -- "$C3C_PATH")")"
    for rel in ../lib/c3 ../lib lib/c3 lib c3 . ../c3 .. ../../lib/c3 ../../lib; do
        if [[ -d "$exe_dir/$rel/std" ]]; then
            STDLIB="$(readlink -f -- "$exe_dir/$rel/std")"
            return 0
        fi
    done
    return 1
}

resolve_toolchain() {
    local out
    C3C_PATH="$(command -v -- "$C3C_BIN" || true)"
    [[ -n "$C3C_PATH" ]] || die "c3c not found (set C3C=/path/to/c3c or add it to PATH)"
    out="$("$C3C_PATH" --version 2>/dev/null || true)"
    VERSION="$(sed -nE 's/^C3 Compiler Version:[[:space:]]*(.*)$/\1/p' <<<"$out" | head -n 1)"
    [[ -n "$VERSION" ]] || die "'$C3C_PATH --version' did not report a version"
    resolve_stdlib || die "stdlib not found next to $C3C_PATH (set C3C_LIB)"
}

# Upward search, like 'c3c build'.
resolve_project() {
    local dir
    dir="$(readlink -f -- "$1")"
    while :; do
        local f
        for f in "$dir/project.json" "$dir/project.json5"; do
            [[ -f "$f" ]] && { PROJECT_FILE="$f"; return 0; }
        done
        [[ "$dir" == / ]] && return 1
        dir="$(dirname -- "$dir")"
    done
}

# C3 has no standard version pin; look for c3c versions in CI and tool files.
resolve_pin() {
    local root="$1" f value
    for f in "$root"/.github/workflows/*.y*ml "$root"/.gitlab-ci.yml "$root"/.woodpecker/*.y*ml \
        "$root"/.forgejo/workflows/*.y*ml "$root"/mise.toml "$root"/.tool-versions; do
        [[ -f "$f" ]] || continue
        # Heuristic: first 0.x.y version within 6 lines after a line mentioning c3/c3c.
        value="$(grep -i -A6 -E '(^|[^[:alnum:]])c3c?([^[:alnum:]]|$)' "$f" |
            grep -oE '(^|[^0-9.])v?0\.[0-9]+\.[0-9]+(_[0-9]+)?' |
            grep -oE '0\.[0-9]+\.[0-9]+(_[0-9]+)?' | head -n 1 || true)"
        [[ -n "$value" ]] && { PINNED="$value"; PINNED_FROM="${f#"$root"/}"; return 0; }
    done
    return 1
}

print_project() {
    printf 'project   %s\n' "$PROJECT_FILE"
    command -v python3 >/dev/null 2>&1 || return 0
    # project.json may contain JSON5 comments; strip // and /* */ before parsing.
    python3 -I - "$PROJECT_FILE" <<'PY' || true
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r'(?m)^((?:[^"\n]|"(?:\\.|[^"\\])*")*?)//.*$', r"\1", text)
text = re.sub(r",(\s*[}\]])", r"\1", text)
try:
    p = json.loads(text)
except ValueError as e:
    print(f"          <could not parse: {e}>")
    sys.exit(0)
targets = p.get("targets", {})
print("targets   " + (", ".join(f"{k} ({v.get('type', '?')})" for k, v in targets.items()) or "<none>"))
for key in ("langrev", "dependencies", "dependency-search-paths", "sources", "test-sources", "features", "opt", "safe"):
    if key in p:
        print(f"{key:<9} {p[key]}")
PY
}

main() {
    local opt
    while getopts ':hf:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            f) FIELD="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (($# <= 1)) || die "expected at most one directory" 2
    local start="${1:-.}"
    [[ -d "$start" ]] || die "not a directory: $start" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    resolve_toolchain
    local root="$start"
    if resolve_project "$start"; then root="$(dirname -- "$PROJECT_FILE")"; fi
    resolve_pin "$root" || true

    case "$FIELD" in
        '') ;;
        c3c) printf '%s\n' "$C3C_PATH"; exit 0 ;;
        version) printf '%s\n' "$VERSION"; exit 0 ;;
        series) series_of "$VERSION"; exit 0 ;;
        stdlib) printf '%s\n' "$STDLIB"; exit 0 ;;
        project) [[ -n "$PROJECT_FILE" ]] || exit 1; printf '%s\n' "$PROJECT_FILE"; exit 0 ;;
        pinned) [[ -n "$PINNED" ]] || exit 1; printf '%s\n' "$PINNED"; exit 0 ;;
        *) die "unknown field: $FIELD" 2 ;;
    esac

    printf 'c3c       %s\n' "$C3C_PATH"
    printf 'version   %s (series %s)\n' "$VERSION" "$(series_of "$VERSION" || printf '?')"
    [[ "$VERSION" == *Pre-release* ]] && warn "pre-release (nightly) compiler: stdlib/APIs track master"
    printf 'stdlib    %s\n' "$STDLIB"
    if [[ -n "$PROJECT_FILE" ]]; then
        print_project
    else
        printf 'project   <no project.json above %s; single-file mode>\n' "$start"
    fi
    if [[ -z "$PINNED" ]]; then
        printf 'pinned    <none found (C3 has no standard pin; check README/CI)>\n'
        return 0
    fi
    printf 'pinned    %s (%s)\n' "$PINNED" "$PINNED_FROM"
    local have want
    have="$(release_of "$VERSION" || true)"
    want="$(release_of "$PINNED" || true)"
    if [[ -n "$have" && -n "$want" && "$have" != "$want" ]]; then
        warn "project pins c3c $want but installed is $have; C3 changes APIs even in patch releases"
        exit 3
    fi
}

main "$@"
