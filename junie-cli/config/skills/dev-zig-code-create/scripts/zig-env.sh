#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only report of the Zig toolchain an agent must target: compiler path
    and version, std/lib directories, local language reference, ZLS, and the
    version a project pins (build.zig.zon minimum_zig_version, .zigversion,
    mise/asdf tool files). Warns when installed and pinned versions differ.

Usage:
    ${0##*/} [-h] [-f <field>] [<project-dir>]

Arguments:
    -h            Show this usage documentation.
    -f <field>    Print a single value and exit. One of:
                  zig, version, series, lib_dir, std_dir, langref, pinned.
    <project-dir> Project root to inspect for version pins (default: .).

Environment:
    ZIG=<path>    Zig binary to inspect (default: first 'zig' on PATH).
    DEBUG=1       Trace execution.

Exit Codes:
    0   toolchain found (warnings may remain)
    1   zig not found or its environment could not be resolved
    2   usage error
    3   installed series differs from the project's pinned series
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

ZIG_BIN="${ZIG:-zig}"
FIELD=''
PROJECT='.'
ZIG_PATH=''
ZIG_VERSION=''
LIB_DIR=''
STD_DIR=''
LANGREF=''
PINNED=''
PINNED_FROM=''

warn() { printf '[warn] %s\n' "$*" >&2; }
die() { printf '[error] %s\n' "$1" >&2; exit "${2:-1}"; }

# Prints "0.17" for "0.17.0", "0.18.0-dev.828+9da287565", etc.
series_of() {
    local v="$1"
    [[ "$v" =~ ^([0-9]+)\.([0-9]+) ]] || return 1
    printf '%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

# Extracts a string field from 'zig env' output (ZON since 0.14, JSON before).
env_field() {
    local out="$1" key="$2"
    sed -nE "s/^[[:space:]]*(\.|\")${key}\"?[[:space:]]*[:=][[:space:]]*\"([^\"]*)\".*/\2/p" \
        <<<"$out" | head -n 1
}

resolve_toolchain() {
    local env_out=''
    ZIG_PATH="$(command -v -- "$ZIG_BIN" || true)"
    [[ -n "$ZIG_PATH" ]] || die "zig not found (set ZIG=/path/to/zig or add zig to PATH)"
    ZIG_VERSION="$("$ZIG_PATH" version 2>/dev/null || true)"
    [[ -n "$ZIG_VERSION" ]] || die "'$ZIG_PATH version' failed"
    env_out="$("$ZIG_PATH" env 2>/dev/null || true)"
    LIB_DIR="$(env_field "$env_out" lib_dir)"
    STD_DIR="$(env_field "$env_out" std_dir)"
    if [[ -z "$LIB_DIR" ]]; then
        # Release tarballs ship lib/ next to the binary.
        LIB_DIR="$(dirname -- "$(readlink -f -- "$ZIG_PATH")")/lib"
    fi
    [[ -n "$STD_DIR" ]] || STD_DIR="$LIB_DIR/std"
    [[ -d "$STD_DIR" ]] || die "std dir not found: $STD_DIR"
    local candidate
    for candidate in "$LIB_DIR/../doc/langref.html" "$LIB_DIR/../share/doc/zig/langref.html" \
        "$LIB_DIR/../../doc/zig/langref.html"; do
        if [[ -f "$candidate" ]]; then
            LANGREF="$(readlink -f -- "$candidate")"
            break
        fi
    done
}

# Sets PINNED/PINNED_FROM from the first pin found in the project.
resolve_pin() {
    local dir="$1" value=''
    if [[ -f "$dir/build.zig.zon" ]]; then
        value="$(sed -nE 's/^[[:space:]]*\.minimum_zig_version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
            "$dir/build.zig.zon" | head -n 1)"
        [[ -n "$value" ]] && { PINNED="$value"; PINNED_FROM='build.zig.zon minimum_zig_version'; return; }
    fi
    if [[ -f "$dir/.zigversion" ]]; then
        value="$(tr -d '[:space:]' <"$dir/.zigversion")"
        [[ -n "$value" ]] && { PINNED="$value"; PINNED_FROM='.zigversion'; return; }
    fi
    if [[ -f "$dir/.tool-versions" ]]; then
        value="$(awk '$1 == "zig" { print $2; exit }' "$dir/.tool-versions")"
        [[ -n "$value" ]] && { PINNED="$value"; PINNED_FROM='.tool-versions'; return; }
    fi
    local mise
    for mise in "$dir/mise.toml" "$dir/.mise.toml"; do
        [[ -f "$mise" ]] || continue
        value="$(sed -nE 's/^[[:space:]]*zig[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$mise" | head -n 1)"
        [[ -n "$value" ]] && { PINNED="$value"; PINNED_FROM="${mise##*/}"; return; }
    done
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

    resolve_toolchain
    resolve_pin "$PROJECT"

    local series pinned_series=''
    series="$(series_of "$ZIG_VERSION" || printf '%s' "$ZIG_VERSION")"
    [[ -n "$PINNED" ]] && pinned_series="$(series_of "$PINNED" || true)"

    case "$FIELD" in
        '') ;;
        zig) printf '%s\n' "$ZIG_PATH"; exit 0 ;;
        version) printf '%s\n' "$ZIG_VERSION"; exit 0 ;;
        series) printf '%s\n' "$series"; exit 0 ;;
        lib_dir) printf '%s\n' "$LIB_DIR"; exit 0 ;;
        std_dir) printf '%s\n' "$STD_DIR"; exit 0 ;;
        langref) [[ -n "$LANGREF" ]] || exit 1; printf '%s\n' "$LANGREF"; exit 0 ;;
        pinned) [[ -n "$PINNED" ]] || exit 1; printf '%s\n' "$PINNED"; exit 0 ;;
        *) die "unknown field: $FIELD" 2 ;;
    esac

    printf 'zig       %s\n' "$ZIG_PATH"
    printf 'version   %s (series %s)\n' "$ZIG_VERSION" "$series"
    [[ "$ZIG_VERSION" == *-dev* ]] && warn "dev build: APIs track master and change without notice"
    printf 'lib_dir   %s\n' "$LIB_DIR"
    printf 'std_dir   %s\n' "$STD_DIR"
    printf 'langref   %s\n' "${LANGREF:-<not shipped; use https://ziglang.org/documentation/$series.0/>}"
    if command -v zls >/dev/null 2>&1; then
        printf 'zls       %s\n' "$(zls --version 2>/dev/null || printf 'unknown')"
    else
        printf 'zls       <not installed>\n'
    fi
    if [[ -z "$PINNED" ]]; then
        printf 'pinned    <none found in %s>\n' "$PROJECT"
        return 0
    fi
    printf 'pinned    %s (%s)\n' "$PINNED" "$PINNED_FROM"
    if [[ -n "$pinned_series" && "$pinned_series" != "$series" ]]; then
        warn "project pins $pinned_series but installed zig is $series; APIs differ between series"
        exit 3
    fi
}

main "$@"
