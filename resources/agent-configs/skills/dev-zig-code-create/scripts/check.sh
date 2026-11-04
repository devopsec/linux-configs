#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Verification gate for Zig work: zig fmt --check, then compile, then tests.
    Uses 'zig build' when the target is a project with build.zig, otherwise
    'zig test' / 'zig build-exe' on a single .zig file. Writes only to the
    project's .zig-cache/ and zig-out/ (or the global Zig cache).

Usage:
    ${0##*/} [-h] [-F] [-T] [-r <mode>] [-t <seconds>] [<project-dir|file.zig>] [-- <zig build args>]

Arguments:
    -h              Show this usage documentation.
    -F              Skip the 'zig fmt --check' stage.
    -T              Skip tests (compile only).
    -r <mode>       Optimize mode passed as -Doptimize / -O (e.g. ReleaseSafe).
    -t <seconds>    Kill any stage that runs longer than this (default: 600).
    <target>        Project root or single .zig file (default: .).
    -- <args>       Extra arguments appended to every 'zig build' call
                    (e.g. -Dtarget=x86_64-linux-musl).

Environment:
    ZIG=<path>      Zig binary to use (default: zig on PATH).
    DEBUG=1         Trace execution.

Exit Codes:
    0   all stages passed
    1   a stage failed (output shown above the summary)
    2   usage error
    124 a stage timed out
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

ZIG_BIN="${ZIG:-zig}"
SKIP_FMT=0
SKIP_TEST=0
OPTIMIZE=''
TIMEOUT_S=600
declare -a EXTRA=()
declare -a RESULTS=()

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Runs a named stage; records pass/fail; returns the stage's exit code.
stage() {
    local name="$1" rc=0
    shift
    printf '\n== %s ==\n$ %s\n' "$name" "${*/#"$ZIG_BIN"/zig}"
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

summary() {
    printf '\n== summary ==\n'
    printf '%s\n' "${RESULTS[@]}"
}

# Succeeds when build.zig in the current directory declares step $1 ('zig build -l').
has_build_step() {
    local step="$1"
    "$ZIG_BIN" build -l "${EXTRA[@]}" 2>/dev/null |
        awk '{ print $1 }' | grep -qx -- "$step"
}

check_project() {
    local dir="$1" rc=0
    # Script-local cd: zig build resolves build.zig from the working directory.
    cd -- "$dir"
    local -a opt_args=()
    [[ -n "$OPTIMIZE" ]] && opt_args=("-Doptimize=$OPTIMIZE")

    if ((!SKIP_FMT)); then
        local -a fmt_paths=()
        local p
        for p in build.zig build.zig.zon src lib test tests; do
            [[ -e "$p" ]] && fmt_paths+=("$p")
        done
        stage 'fmt' "$ZIG_BIN" fmt --check "${fmt_paths[@]}" || rc=1
    fi
    stage 'build' "$ZIG_BIN" build --summary failures "${opt_args[@]}" "${EXTRA[@]}" || return "$?"
    if ((!SKIP_TEST)); then
        if has_build_step test; then
            stage 'test' "$ZIG_BIN" build test --summary failures "${opt_args[@]}" "${EXTRA[@]}" || return "$?"
        else
            RESULTS+=("SKIP  test (build.zig declares no 'test' step)")
        fi
    fi
    return "$rc"
}

check_file() {
    local file="$1" rc=0
    local -a opt_args=()
    [[ -n "$OPTIMIZE" ]] && opt_args=(-O "$OPTIMIZE")
    ((SKIP_FMT)) || stage 'fmt' "$ZIG_BIN" fmt --check "$file" || rc=1
    if ((SKIP_TEST)); then
        # build-obj type-checks everything reachable without needing a main.
        stage 'compile' "$ZIG_BIN" build-obj "${opt_args[@]}" -fno-emit-bin "$file" || return "$?"
    else
        stage 'test' "$ZIG_BIN" test "${opt_args[@]}" "$file" || return "$?"
    fi
    return "$rc"
}

main() {
    local opt
    while getopts ':hFTr:t:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            F) SKIP_FMT=1 ;;
            T) SKIP_TEST=1 ;;
            r) OPTIMIZE="$OPTARG" ;;
            t) [[ "$OPTARG" =~ ^[1-9][0-9]*$ ]] || die "-t needs a positive integer" 2
               TIMEOUT_S="$OPTARG" ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    local target='.'
    if (($# > 0)) && [[ "$1" != '--' ]]; then
        target="$1"
        shift
    fi
    if (($# > 0)); then
        [[ "$1" == '--' ]] || die "unexpected argument: $1" 2
        shift
        EXTRA=("$@")
    fi
    [[ "${DEBUG:-0}" == 1 ]] && set -x
    command -v -- "$ZIG_BIN" >/dev/null 2>&1 || die "zig not found (set ZIG=/path/to/zig)"

    local rc=0
    if [[ -d "$target" ]]; then
        [[ -f "$target/build.zig" ]] || die "no build.zig in $target; pass a .zig file instead" 2
        check_project "$target" || rc=$?
    elif [[ -f "$target" && "$target" == *.zig ]]; then
        ((${#EXTRA[@]} == 0)) || die "'-- <args>' only applies to build.zig projects" 2
        check_file "$target" || rc=$?
    else
        die "not a project directory or .zig file: $target" 2
    fi
    summary
    ((rc == 124)) && exit 124
    ((rc == 0)) || exit 1
}

main "$@"
