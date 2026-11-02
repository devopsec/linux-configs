#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Verification gate for Rust work: cargo fmt --check, cargo clippy (or
    cargo check) on all targets, tests (cargo-nextest when installed, plus
    doctests), and optionally rustdoc, Miri, and an MSRV build. A single .rs
    file is checked with rustfmt + rustc --test instead. Uses --manifest-path
    (no cd); writes only to the project's target/ dir (or a temp dir for a
    single file). Never installs toolchains or components.

Usage:
    ${0##*/} [-h] [-F] [-C] [-T] [-W] [-D] [-m] [-M] [-N] [-r] [-t <seconds>] [<project-dir|file.rs>] [-- <cargo args>]

Arguments:
    -h              Show this usage documentation.
    -F              Skip the format stage.
    -C              Use 'cargo check' instead of clippy.
    -T              Skip tests (compile/lint only).
    -W              Treat warnings as errors (clippy -D warnings, RUSTDOCFLAGS).
    -D              Also build docs (cargo doc --no-deps) and fail on doc warnings.
    -m              Also run tests under Miri (needs a nightly with the miri
                    component; slow; add '-- <test filter>' via cargo args).
    -M              Also 'cargo check' with the project's rust-version toolchain,
                    if that toolchain is already installed.
    -N              Use 'cargo test' even when cargo-nextest is installed.
    -r              Build and test in release mode.
    -t <seconds>    Kill any stage that runs longer than this (default: 900).
    <target>        Project root (has Cargo.toml) or a single .rs file (default: .).
    -- <args>       Extra args appended to clippy/check/test/doc/miri, e.g.
                    --all-features, -p mycrate, --features tokio.

Environment:
    RUSTUP_TOOLCHAIN=<name>  Toolchain for the main stages.
    EDITION=<year>           Edition for single-file mode (default: 2024).
    DEBUG=1                  Trace execution.

Exit Codes:
    0   all stages passed
    1   a stage failed (output shown above the summary)
    2   usage error
    124 a stage timed out
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

# Never let rustup download a toolchain as a side effect of a check.
export RUSTUP_AUTO_INSTALL=0

SKIP_FMT=0
USE_CHECK=0
SKIP_TEST=0
STRICT=0
WITH_DOC=0
WITH_MIRI=0
WITH_MSRV=0
NO_NEXTEST=0
RELEASE=0
TIMEOUT_S=900
EDITION="${EDITION:-2024}"
WORK_DIR=''
declare -a EXTRA=()
declare -a RESULTS=()

die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Runs a named stage; records pass/fail; returns the stage's exit code.
stage() {
    local name="$1" rc=0
    shift
    printf '\n== %s ==\n$ %s\n' "$name" "$*"
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

# Prints the newest installed toolchain matching $1 (1.85 -> 1.85.1-<host>); fails if none.
installed_toolchain() {
    local want="$1"
    command -v rustup >/dev/null 2>&1 || return 1
    rustup toolchain list 2>/dev/null | awk '{ print $1 }' |
        grep -E "^${want//./\\.}(\\.[0-9]+)?-" | sort -V | tail -n 1 | grep .
}

check_project() {
    local manifest="$1/Cargo.toml" rc=0
    local -a mp=(--manifest-path "$manifest") scope=() rel=()
    grep -qE '^[[:space:]]*\[workspace\]' "$manifest" && scope=(--workspace)
    ((RELEASE)) && rel=(--release)

    if ((!SKIP_FMT)); then
        if cargo fmt --version >/dev/null 2>&1; then
            stage 'fmt' cargo fmt "${mp[@]}" --all -- --check || rc=1
        else
            RESULTS+=("SKIP  fmt (rustfmt component not installed)")
        fi
    fi

    if ((!USE_CHECK)) && cargo clippy --version >/dev/null 2>&1; then
        local -a deny=()
        ((STRICT)) && deny=(-- -D warnings)
        stage 'clippy' cargo clippy "${mp[@]}" "${scope[@]}" --all-targets "${rel[@]}" "${EXTRA[@]}" "${deny[@]}" ||
            return "$?"
    else
        ((USE_CHECK)) || RESULTS+=("NOTE  clippy not installed; using cargo check")
        if ((STRICT)); then
            stage 'check' env "RUSTFLAGS=${RUSTFLAGS:-} -D warnings" cargo check "${mp[@]}" "${scope[@]}" --all-targets "${rel[@]}" "${EXTRA[@]}" ||
                return "$?"
        else
            stage 'check' cargo check "${mp[@]}" "${scope[@]}" --all-targets "${rel[@]}" "${EXTRA[@]}" || return "$?"
        fi
    fi

    if ((!SKIP_TEST)); then
        if ((!NO_NEXTEST)) && command -v cargo-nextest >/dev/null 2>&1; then
            # --no-tests=warn: a crate without tests is not a failure.
            stage 'test (nextest)' cargo nextest run "${mp[@]}" "${scope[@]}" "${rel[@]}" --no-tests=warn "${EXTRA[@]}" || return "$?"
            # nextest does not run doctests.
            stage 'doctest' cargo test "${mp[@]}" "${scope[@]}" "${rel[@]}" --doc "${EXTRA[@]}" || rc=1
        else
            stage 'test' cargo test "${mp[@]}" "${scope[@]}" "${rel[@]}" "${EXTRA[@]}" || return "$?"
        fi
    fi

    if ((WITH_DOC)); then
        local docflags="${RUSTDOCFLAGS:-}"
        ((STRICT)) && docflags="$docflags -D warnings"
        stage 'doc' env "RUSTDOCFLAGS=$docflags" cargo doc "${mp[@]}" "${scope[@]}" --no-deps "${EXTRA[@]}" || rc=1
    fi

    if ((WITH_MIRI)); then
        if cargo +nightly miri --version >/dev/null 2>&1; then
            stage 'miri' cargo +nightly miri test "${mp[@]}" "${scope[@]}" "${EXTRA[@]}" || rc=1
        else
            RESULTS+=("SKIP  miri (nightly toolchain with the miri component not installed)")
        fi
    fi

    if ((WITH_MSRV)); then
        local msrv='' tc=''
        msrv="$("$(dirname -- "$(readlink -f -- "$0")")/rust-env.sh" -f msrv "$1" 2>/dev/null || true)"
        if [[ -z "$msrv" ]]; then
            RESULTS+=("SKIP  msrv (no rust-version in Cargo.toml)")
        elif tc="$(installed_toolchain "$msrv")"; then
            stage "msrv ($tc)" cargo "+$tc" check "${mp[@]}" "${scope[@]}" --all-targets "${EXTRA[@]}" || rc=1
        else
            RESULTS+=("SKIP  msrv (toolchain $msrv not installed; ask before 'rustup toolchain install $msrv')")
        fi
    fi
    return "$rc"
}

check_file() {
    local file="$1" rc=0 out
    out="$(mktemp -d)"
    WORK_DIR="$out"
    trap 'rm -rf -- "$WORK_DIR"' EXIT
    local -a opt=()
    ((RELEASE)) && opt=(-O)
    if ((!SKIP_FMT)); then
        stage 'fmt' rustfmt --check --edition "$EDITION" "$file" || rc=1
    fi
    if ((SKIP_TEST)); then
        stage 'compile' rustc --edition "$EDITION" "${opt[@]}" --crate-type lib --emit=metadata \
            --out-dir "$out" "$file" || return "$?"
    else
        stage 'compile (test)' rustc --edition "$EDITION" "${opt[@]}" --test -o "$out/t" "$file" || return "$?"
        stage 'test' "$out/t" || return "$?"
    fi
    return "$rc"
}

main() {
    local opt
    while getopts ':hFCTWDmMNrt:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            F) SKIP_FMT=1 ;;
            C) USE_CHECK=1 ;;
            T) SKIP_TEST=1 ;;
            W) STRICT=1 ;;
            D) WITH_DOC=1 ;;
            m) WITH_MIRI=1 ;;
            M) WITH_MSRV=1 ;;
            N) NO_NEXTEST=1 ;;
            r) RELEASE=1 ;;
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

    local rc=0
    if [[ -d "$target" ]]; then
        command -v cargo >/dev/null 2>&1 || die "cargo not found (install via rustup)"
        [[ -f "$target/Cargo.toml" ]] || die "no Cargo.toml in $target; pass a .rs file instead" 2
        check_project "$target" || rc=$?
    elif [[ -f "$target" && "$target" == *.rs ]]; then
        command -v rustc >/dev/null 2>&1 || die "rustc not found (install via rustup)"
        ((${#EXTRA[@]} == 0)) || die "'-- <args>' only applies to Cargo projects" 2
        check_file "$target" || rc=$?
    else
        die "not a project directory or .rs file: $target" 2
    fi
    summary
    ((rc == 124)) && exit 124
    ((rc == 0)) || exit 1
}

main "$@"
