#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Read-only check of the toolchain, system libraries, packaging tools, and
    desktop session needed to build COSMIC (libcosmic) apps and applets.
    Prints distro-specific install hints; never installs anything.

Usage:
    ${0##*/} [-h] [-m <rust-version>]

Arguments:
    -h                  Show this usage documentation.
    -m <rust-version>   Minimum rustc version to require (default: ${DEFAULT_MSRV}).
                        Use the libcosmic 'rust-version' from 'upstream.sh rev'.

Environment:
    DEBUG=1             Trace execution.

Exit Codes:
    0   all required items present (warnings may remain)
    1   one or more required items missing
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

DEFAULT_MSRV='1.93'
MSRV="$DEFAULT_MSRV"
MISSING=0
WARNINGS=0
DISTRO=''
declare -a HINT_PKGS=()

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
ok() { printf '[ok]      %s\n' "$*"; }
warn() { printf '[warn]    %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
missing() { printf '[missing] %s\n' "$*"; MISSING=$((MISSING + 1)); }
section() { printf '\n== %s ==\n' "$*"; }

# Returns 0 when version $1 >= version $2 (dotted numeric).
version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort --version-sort | head -n 1)" == "$2" ]]
}

detect_distro() {
    local id='' id_like=''
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id="$(. /etc/os-release && printf '%s' "${ID:-}")"
        # shellcheck disable=SC1091
        id_like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    fi
    case " $id $id_like " in
        *' debian '* | *' ubuntu '* | *' pop '*) DISTRO='debian' ;;
        *' fedora '* | *' rhel '*) DISTRO='fedora' ;;
        *' arch '*) DISTRO='arch' ;;
        *' opensuse'* | *' suse '*) DISTRO='suse' ;;
        *) DISTRO='unknown' ;;
    esac
}

# Map a logical dependency to the distro package name.
pkg_name() {
    local dep="$1"
    case "$DISTRO:$dep" in
        debian:xkbcommon) echo 'libxkbcommon-dev' ;;
        debian:fontconfig) echo 'libfontconfig-dev' ;;
        debian:freetype2) echo 'libfreetype-dev' ;;
        debian:expat) echo 'libexpat1-dev' ;;
        debian:pkg-config) echo 'pkgconf' ;;
        fedora:xkbcommon) echo 'libxkbcommon-devel' ;;
        fedora:fontconfig) echo 'fontconfig-devel' ;;
        fedora:freetype2) echo 'freetype-devel' ;;
        fedora:expat) echo 'expat-devel' ;;
        fedora:pkg-config) echo 'pkgconf-pkg-config' ;;
        arch:xkbcommon) echo 'libxkbcommon' ;;
        arch:freetype2) echo 'freetype2' ;;
        arch:pkg-config) echo 'pkgconf' ;;
        suse:xkbcommon) echo 'libxkbcommon-devel' ;;
        suse:fontconfig) echo 'fontconfig-devel' ;;
        suse:freetype2) echo 'freetype2-devel' ;;
        suse:expat) echo 'libexpat-devel' ;;
        suse:pkg-config) echo 'pkgconf' ;;
        *) echo "$dep" ;;
    esac
}

check_cmd() {
    local cmd="$1" required="$2" hint="$3"
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd ($(command -v "$cmd"))"
        return 0
    fi
    if [[ "$required" == 'required' ]]; then
        missing "$cmd — $hint"
    else
        warn "$cmd not found (optional) — $hint"
    fi
    return 1
}

check_rust() {
    local rustc_ver=''
    section 'Rust toolchain'
    if check_cmd cargo required 'install via https://rustup.rs'; then
        rustc_ver="$(rustc --version 2>/dev/null | awk '{print $2}')"
        if [[ -z "$rustc_ver" ]]; then
            missing 'rustc not runnable'
        elif version_ge "$rustc_ver" "$MSRV"; then
            ok "rustc $rustc_ver >= $MSRV"
        else
            missing "rustc $rustc_ver < $MSRV — run 'rustup update' or add rust-toolchain.toml"
        fi
        if cargo fmt --version &>/dev/null; then ok 'rustfmt'; else warn 'rustfmt missing — rustup component add rustfmt'; fi
        if cargo clippy --version &>/dev/null; then ok 'clippy'; else warn 'clippy missing — rustup component add clippy'; fi
        if cargo generate --version &>/dev/null; then
            ok "cargo-generate ($(cargo generate --version 2>/dev/null | head -n 1))"
        else
            warn 'cargo-generate missing (needed by scaffold.sh) — cargo install cargo-generate'
        fi
    fi
}

check_build_deps() {
    local dep
    section 'Build tools & system libraries'
    check_cmd git required 'install git' || HINT_PKGS+=('git')
    check_cmd just required 'COSMIC justfiles need just' || HINT_PKGS+=('just')
    check_cmd cmake optional 'some -sys crates need cmake' || HINT_PKGS+=('cmake')
    if check_cmd pkg-config required 'needed to locate system libraries'; then
        for dep in xkbcommon fontconfig freetype2 expat; do
            if pkg-config --exists "$dep" 2>/dev/null; then
                ok "lib $dep ($(pkg-config --modversion "$dep" 2>/dev/null))"
            else
                missing "development headers for $dep"
                HINT_PKGS+=("$(pkg_name "$dep")")
            fi
        done
    else
        HINT_PKGS+=("$(pkg_name pkg-config)")
    fi
}

check_packaging() {
    section 'Packaging & metadata tools (optional)'
    check_cmd desktop-file-validate optional 'desktop-file-utils' || true
    check_cmd appstreamcli optional 'appstream' || true
    if check_cmd flatpak optional 'needed for Flatpak builds'; then
        if flatpak info --user org.flatpak.Builder &>/dev/null || flatpak info --system org.flatpak.Builder &>/dev/null; then
            ok 'org.flatpak.Builder (flatpak-builder + flatpak-builder-lint)'
        else
            warn 'org.flatpak.Builder not installed — flatpak install --user flathub org.flatpak.Builder'
        fi
    fi
    check_cmd flatpak-builder optional 'or use org.flatpak.Builder via flatpak run' || true
    if [[ -n "${FLATPAK_CARGO_GENERATOR:-}" && -f "$FLATPAK_CARGO_GENERATOR" ]]; then
        ok "flatpak-cargo-generator ($FLATPAK_CARGO_GENERATOR)"
    elif command -v flatpak-cargo-generator.py &>/dev/null; then
        ok 'flatpak-cargo-generator.py (PATH)'
    else
        warn 'flatpak-cargo-generator not configured — set FLATPAK_CARGO_GENERATOR=/path/to/flatpak-cargo-generator.py'
    fi
    check_cmd shellcheck optional 'lint helper scripts' || true
}

check_session() {
    section 'Desktop session'
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *COSMIC* ]]; then
        ok "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP}"
    else
        warn "not a COSMIC session (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset}) — apps build, but runtime/applet testing needs COSMIC"
    fi
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then ok "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"; else warn 'WAYLAND_DISPLAY unset — no Wayland session'; fi
    if command -v cosmic-panel &>/dev/null; then ok 'cosmic-panel installed (applets testable)'; else warn 'cosmic-panel not installed — applets cannot be tested locally'; fi
}

print_hints() {
    local -a uniq_pkgs=()
    (( ${#HINT_PKGS[@]} == 0 )) && return 0
    mapfile -t uniq_pkgs < <(printf '%s\n' "${HINT_PKGS[@]}" | sort -u)
    section "Install hint ($DISTRO, run as root after user approval)"
    case "$DISTRO" in
        debian) printf 'apt install %s\n' "${uniq_pkgs[*]}" ;;
        fedora) printf 'dnf install %s\n' "${uniq_pkgs[*]}" ;;
        arch) printf 'pacman -S --needed %s\n' "${uniq_pkgs[*]}" ;;
        suse) printf 'zypper install %s\n' "${uniq_pkgs[*]}" ;;
        *) printf 'packages needed: %s\n' "${uniq_pkgs[*]}" ;;
    esac
}

main() {
    local opt
    while getopts ':hm:' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            m) MSRV="$OPTARG" ;;
            :) log "option -$OPTARG requires an argument"; usage >&2; exit 2 ;;
            *) log "unknown option -$OPTARG"; usage >&2; exit 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (( $# == 0 )) || { log "unexpected arguments: $*"; exit 2; }
    [[ "$MSRV" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { log "invalid rust version: $MSRV"; exit 2; }
    if [[ "${DEBUG:-0}" == 1 ]]; then set -x; fi

    detect_distro
    check_rust
    check_build_deps
    check_packaging
    check_session
    print_hints

    section 'Summary'
    printf 'missing required: %d, warnings: %d\n' "$MISSING" "$WARNINGS"
    (( MISSING == 0 ))
}

main "$@"
