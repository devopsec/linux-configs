#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Verification gate for C3 work. In a project (project.json in or above the
    target directory): 'c3c build [target]' then 'c3c test [target]'. For
    loose files: 'c3c compile-only --no-obj' (type-check, no artifacts) then
    'c3c compile-test' (runs @test functions with leak tracking).
    C3 has no official formatter, so no fmt stage runs.

Usage:
    ${0##*/} [-h] [-T] [-S] [-O <level>] [-n <target>] [-t <seconds>] [<project-dir> | <file.c3>...] [-- <c3c args>]

Arguments:
    -h              Show this usage documentation.
    -T              Skip tests (build / type-check only).
    -S              Strict: make deprecation warnings errors (--warn-deprecation=error).
    -O <level>      Optimization flag passed through, e.g. O0 (safe, default) or O2 (unsafe).
    -n <target>     Project target name for build/test (default: c3c picks the first).
    -t <seconds>    Kill any stage running longer than this (default: 900).
    <path>          Project directory (default: .) or one or more .c3 files.
    -- <args>       Extra arguments appended to every c3c call (e.g. --target linux-x64,
                    -D FEATURE, --test-filter name).

Environment:
    C3C=<path>      c3c binary to use (default: c3c on PATH).
    DEBUG=1         Trace execution.

Exit Codes:
    0   all stages passed
    1   a stage failed (compiler/test output is shown above the summary)
    2   usage error
    124 a stage timed out
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

C3C_BIN="${C3C:-c3c}"
SKIP_TEST=0
STRICT=0
OPT=''
TARGET_NAME=''
TIMEOUT_S=900
declare -a EXTRA=()
declare -a COMMON=()
declare -a RESULTS=()

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

stage() {
    local name="$1" rc=0
    shift
    printf '\n== %s ==\n$ %s\n' "$name" "${*/#"$C3C_BIN"/c3c}"
    timeout --foreground "$TIMEOUT_S" "$@" || rc=$?
    if ((rc == 0)); then
        RESULTS+=("PASS  $name")
    elif ((rc == 124)); then
        RESULTS+=("TIME  $name (>${TIMEOUT_S}s)")
    else
        RESULTS+=("FAIL  $name (exit $rc)")
    fi
    return "$rc"
}

has_project() {
    local dir
    dir="$(readlink -f -- "$1")"
    while :; do
        [[ -f "$dir/project.json" || -f "$dir/project.json5" ]] && return 0
        [[ "$dir" == / ]] && return 1
        dir="$(dirname -- "$dir")"
    done
}

check_project() {
    local dir="$1"
    local -a target=()
    [[ -n "$TARGET_NAME" ]] && target=("$TARGET_NAME")
    # Script-local cd: c3c finds project.json by searching upward from the working directory.
    cd -- "$dir"
    stage 'build' "$C3C_BIN" build "${target[@]}" "${COMMON[@]}" "${EXTRA[@]}" || return "$?"
    if ((!SKIP_TEST)); then
        stage 'test' "$C3C_BIN" test "${target[@]}" "${COMMON[@]}" "${EXTRA[@]}" || return "$?"
    fi
}

check_files() {
    stage 'type-check' "$C3C_BIN" compile-only --no-obj "$@" "${COMMON[@]}" "${EXTRA[@]}" || return "$?"
    if ((!SKIP_TEST)); then
        stage 'test' "$C3C_BIN" compile-test "$@" "${COMMON[@]}" "${EXTRA[@]}" || return "$?"
    fi
}

main() {
    local opt
    while getopts ':hTSO:n:t:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            T) SKIP_TEST=1 ;;
            S) STRICT=1 ;;
            O) [[ "$OPTARG" =~ ^O[0-5sz]$ ]] || die "-O expects O0..O5, Os or Oz" 2
               OPT="-$OPTARG" ;;
            n) TARGET_NAME="$OPTARG" ;;
            t) [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]] || die "-t needs a positive integer" 2
               TIMEOUT_S="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    local -a paths=()
    while (($# > 0)) && [[ "$1" != '--' ]]; do paths+=("$1"); shift; done
    if (($# > 0)); then shift; EXTRA=("$@"); fi
    ((${#paths[@]} > 0)) || paths=('.')
    [[ "${DEBUG:-0}" == 1 ]] && set -x
    command -v -- "$C3C_BIN" >/dev/null 2>&1 || die "c3c not found (set C3C=/path/to/c3c)"
    [[ -n "$OPT" ]] && COMMON+=("$OPT")
    ((STRICT)) && COMMON+=('--warn-deprecation=error')

    local rc=0
    if ((${#paths[@]} == 1)) && [[ -d "${paths[0]}" ]]; then
        has_project "${paths[0]}" || die "no project.json in or above ${paths[0]}; pass .c3 files instead" 2
        [[ -z "$TARGET_NAME" || "$TARGET_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || die "bad target name" 2
        check_project "${paths[0]}" || rc=$?
    else
        local p
        for p in "${paths[@]}"; do
            [[ -f "$p" && ( "$p" == *.c3 || "$p" == *.c3i ) ]] || die "not a .c3 file: $p" 2
        done
        [[ -z "$TARGET_NAME" ]] || die "-n only applies to projects" 2
        check_files "${paths[@]}" || rc=$?
    fi
    printf '\n== summary ==\n'
    printf '%s\n' "${RESULTS[@]}"
    ((rc == 124)) && exit 124
    ((rc == 0)) || exit 1
}

main "$@"
