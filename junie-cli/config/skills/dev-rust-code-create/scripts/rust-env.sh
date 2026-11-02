#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only report of the Rust toolchain an agent must target: rustc/cargo
    versions, active toolchain, sysroot, local docs (std, book, reference,
    edition guide, releases.md), rust-src, components and cargo subcommands,
    plus what the project pins: rust-toolchain(.toml) channel, Cargo.toml
    rust-version (MSRV) and edition. Never installs anything: when the pinned
    toolchain is missing, rustc is queried through the default toolchain.

Usage:
    ${0##*/} [-h] [-f <field>] [<project-dir>]

Arguments:
    -h            Show this usage documentation.
    -f <field>    Print a single value and exit. One of:
                  rustc, version, toolchain, sysroot, docs, releases,
                  rust_src, pinned, msrv, edition.
    <project-dir> Project root to inspect for pins (default: .).

Environment:
    RUSTUP_TOOLCHAIN=<name>  Toolchain to inspect instead of the resolved one.
    DEBUG=1                  Trace execution.

Exit Codes:
    0   toolchain found (warnings may remain)
    1   rustc not found or a requested field is unavailable
    2   usage error
    3   pinned toolchain not installed, or rustc older than rust-version
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

# Never let rustup download a toolchain as a side effect of this report.
export RUSTUP_AUTO_INSTALL=0

FIELD=''
PROJECT='.'
PINNED=''
PINNED_FROM=''
PIN_MISSING=0
ENV_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-}"
MSRV=''
EDITION=''
RUSTC_VERSION=''
HOST=''
SYSROOT=''
TOOLCHAIN=''

warn() { printf '[warn] %s\n' "$*" >&2; }
die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Prints the channel pinned by rust-toolchain.toml / rust-toolchain in $1 or a parent.
resolve_pin() {
    local dir file value
    dir="$(readlink -f -- "$1")"
    while [[ -n "$dir" ]]; do
        for file in "$dir/rust-toolchain.toml" "$dir/rust-toolchain"; do
            [[ -f "$file" ]] || continue
            value="$(sed -nE 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$file" | head -n 1)"
            if [[ -z "$value" && "${file##*/}" == rust-toolchain ]]; then
                # Legacy single-line format: the file holds only the channel name.
                value="$(grep -vE '^[[:space:]]*(#|\[|$)' "$file" | head -n 1 | tr -d '[:space:]')"
            fi
            if [[ -n "$value" ]]; then
                PINNED="$value"
                PINNED_FROM="$file"
                return 0
            fi
        done
        [[ "$dir" == / ]] && break
        dir="$(dirname -- "$dir")"
    done
}

# Succeeds when rustup has a toolchain matching channel $1 installed.
pin_installed() {
    local pin="$1" name
    command -v rustup >/dev/null 2>&1 || return 0
    while read -r name _; do
        [[ "$name" == "$pin" || "$name" == "$pin"-* ]] && return 0
    done < <(rustup toolchain list 2>/dev/null)
    return 1
}

resolve_toolchain() {
    local out
    [[ -n "$PINNED" ]] && ! pin_installed "$PINNED" && PIN_MISSING=1
    if ((PIN_MISSING)) && [[ -z "$ENV_TOOLCHAIN" ]]; then
        # Querying rustc here would make rustup try to install the pinned toolchain.
        export RUSTUP_TOOLCHAIN
        RUSTUP_TOOLCHAIN="$(rustup default 2>/dev/null | awk '{ print $1; exit }')"
        [[ -n "$RUSTUP_TOOLCHAIN" ]] || die "pinned toolchain $PINNED is not installed and rustup has no default" 3
    fi
    command -v rustc >/dev/null 2>&1 || die "rustc not found (install via rustup: https://rustup.rs)"
    out="$(rustc -vV 2>/dev/null)" || die "'rustc -vV' failed"
    RUSTC_VERSION="$(awk '/^release:/ { print $2 }' <<<"$out")"
    HOST="$(awk '/^host:/ { print $2 }' <<<"$out")"
    SYSROOT="$(rustc --print sysroot 2>/dev/null)"
    if command -v rustup >/dev/null 2>&1; then
        TOOLCHAIN="${RUSTUP_TOOLCHAIN:-$(rustup show active-toolchain 2>/dev/null | awk '{ print $1; exit }')}"
    fi
    TOOLCHAIN="${TOOLCHAIN:-${SYSROOT##*/}}"
}

# Sets MSRV/EDITION from cargo metadata (handles workspace inheritance), else Cargo.toml.
resolve_manifest() {
    local manifest="$1/Cargo.toml" meta
    [[ -f "$manifest" ]] || return 0
    if command -v jq >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1 &&
        meta="$(cargo metadata --no-deps --offline --format-version 1 --manifest-path "$manifest" 2>/dev/null)"; then
        MSRV="$(jq -r '[.packages[].rust_version // empty] | sort_by(split(".") | map(tonumber? // 0)) | last // empty' <<<"$meta")"
        EDITION="$(jq -r '[.packages[].edition] | unique | join(",")' <<<"$meta")"
        return 0
    fi
    MSRV="$(sed -nE 's/^[[:space:]]*rust-version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
    EDITION="$(sed -nE 's/^[[:space:]]*edition[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$manifest" | head -n 1)"
}

# Succeeds when version $1 < version $2 (numeric x.y.z comparison).
version_lt() {
    [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" == "$1" ]]
}

report_tools() {
    local -a have=() missing=() comps=()
    local c
    if command -v rustup >/dev/null 2>&1; then
        mapfile -t comps < <(rustup component list --installed 2>/dev/null | sed -E "s/-$HOST\$//")
        printf 'components %s\n' "${comps[*]:-<unknown>}"
    fi
    for c in clippy fmt nextest miri fuzz llvm-cov deny audit msrv semver-checks \
        flamegraph criterion expand machete udeps asm bloat; do
        if command -v "cargo-$c" >/dev/null 2>&1; then have+=("$c"); else missing+=("$c"); fi
    done
    printf 'cargo+    %s\n' "${have[*]:-<none>}"
    printf 'missing   %s\n' "${missing[*]:-<none>}"
    if command -v rustup >/dev/null 2>&1; then
        printf 'toolchains %s\n' "$(rustup toolchain list 2>/dev/null | awk '{ printf "%s%s", sep, $1; sep = " " }')"
    fi
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
    (($# <= 1)) || die "expected at most one project directory" 2
    PROJECT="${1:-.}"
    [[ -d "$PROJECT" ]] || die "not a directory: $PROJECT" 2
    [[ "${DEBUG:-0}" == 1 ]] && set -x

    resolve_pin "$PROJECT"
    resolve_toolchain
    resolve_manifest "$PROJECT"

    local docs="$SYSROOT/share/doc/rust/html" releases rust_src
    releases="$docs/releases.md"
    [[ -f "$releases" ]] || releases=''
    [[ -d "$docs/std" ]] || docs=''
    rust_src="$SYSROOT/lib/rustlib/src/rust/library"
    [[ -d "$rust_src" ]] || rust_src=''

    case "$FIELD" in
        '') ;;
        rustc) command -v rustc; exit 0 ;;
        version) printf '%s\n' "$RUSTC_VERSION"; exit 0 ;;
        toolchain) printf '%s\n' "$TOOLCHAIN"; exit 0 ;;
        sysroot) printf '%s\n' "$SYSROOT"; exit 0 ;;
        docs) [[ -n "$docs" ]] || exit 1; printf '%s\n' "$docs"; exit 0 ;;
        releases) [[ -n "$releases" ]] || exit 1; printf '%s\n' "$releases"; exit 0 ;;
        rust_src) [[ -n "$rust_src" ]] || exit 1; printf '%s\n' "$rust_src"; exit 0 ;;
        pinned) [[ -n "$PINNED" ]] || exit 1; printf '%s\n' "$PINNED"; exit 0 ;;
        msrv) [[ -n "$MSRV" ]] || exit 1; printf '%s\n' "$MSRV"; exit 0 ;;
        edition) [[ -n "$EDITION" ]] || exit 1; printf '%s\n' "$EDITION"; exit 0 ;;
        *) die "unknown field: $FIELD" 2 ;;
    esac

    printf 'rustc     %s\n' "$(command -v rustc)"
    printf 'version   %s (host %s)\n' "$RUSTC_VERSION" "$HOST"
    [[ "$RUSTC_VERSION" == *nightly* || "$TOOLCHAIN" == nightly* ]] &&
        warn "nightly toolchain: #![feature] APIs can change or vanish without notice"
    printf 'cargo     %s\n' "$(cargo -V 2>/dev/null || printf '<not found>')"
    printf 'toolchain %s%s\n' "$TOOLCHAIN" "${ENV_TOOLCHAIN:+ (from env RUSTUP_TOOLCHAIN)}"
    printf 'sysroot   %s\n' "$SYSROOT"
    printf 'docs      %s\n' "${docs:-<rust-docs not installed; https://doc.rust-lang.org/$RUSTC_VERSION/std/>}"
    printf 'releases  %s\n' "${releases:-<not shipped; https://doc.rust-lang.org/stable/releases.html>}"
    printf 'rust_src  %s\n' "${rust_src:-<not installed; 'rustup component add rust-src' (ask first)>}"
    report_tools

    local rc=0
    if [[ -n "$PINNED" ]]; then
        printf 'pinned    %s (%s)\n' "$PINNED" "$PINNED_FROM"
        if [[ -n "$ENV_TOOLCHAIN" && "$ENV_TOOLCHAIN" != "$PINNED" && "$ENV_TOOLCHAIN" != "$PINNED"-* ]]; then
            warn "RUSTUP_TOOLCHAIN=$ENV_TOOLCHAIN in the environment overrides the project pin $PINNED (set by mise/shell?)"
            rc=3
        fi
        if ((PIN_MISSING)); then
            warn "pinned toolchain $PINNED is not installed; cargo here will fail or try to install it (ask first)"
            rc=3
        fi
    else
        printf 'pinned    <no rust-toolchain file>\n'
    fi
    printf 'msrv      %s\n' "${MSRV:-<no rust-version in Cargo.toml>}"
    printf 'edition   %s\n' "${EDITION:-<no Cargo.toml in $PROJECT>}"
    if [[ -n "$MSRV" ]] && version_lt "${RUSTC_VERSION%%-*}" "$MSRV"; then
        warn "rustc $RUSTC_VERSION is older than the project's rust-version $MSRV"
        rc=3
    fi
    exit "$rc"
}

main "$@"
