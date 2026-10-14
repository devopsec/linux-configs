#!/usr/bin/env bash

# shared installer library for the neovim and vim families: flag parsing, install and
# config mode resolution, the generic package backends (sys_pkg_mgr, flatpak, bin_pkgmgr)
# and the orchestration that drives each selected family's <family>_* functions;
# sourced by the root install.sh and by each family's install.sh, never run directly

if [[ -n "${LINUX_CONFIGS_COMMON_LOADED:-}" ]]; then
    return 0
fi
declare -g LINUX_CONFIGS_COMMON_LOADED=1

set -euo pipefail
shopt -s inherit_errexit nullglob

# repo root, regardless of which installer sourced this library
declare -g SCRIPT_DIR
SCRIPT_DIR="$(realpath -m "${BASH_SOURCE[0]}/../../")"

declare -gi CLEAN_CONFIGS=0
declare -gi CLEAN_PACKAGES=0
declare -gi SKIP_PACKAGES=0
declare -gi SKIP_CONFIGS=0
declare -ga ALL_APPS=()
declare -ga APPS=()
# each family registers itself (FAMILY_APPS[<family>]="<apps>") when its installer is sourced
declare -gA FAMILY_APPS=()

declare -ga VALID_INSTALL_MODES=(system user auto)
declare -ga VALID_CONFIG_MODES=(global users local auto)
declare -g  INSTALL_MODE="auto"
declare -g  CONFIG_MODE="auto"
declare -g  RESOLVED_INSTALL_MODE
declare -g  RESOLVED_CONFIG_MODE
declare -gi SUDO_GRANTED=0

declare -gr COLOR_RESET='\033[0m'
declare -gr COLOR_RED='\033[0;31m'
declare -gr COLOR_GREEN='\033[0;32m'
declare -gr COLOR_YELLOW='\033[0;33m'
declare -gr COLOR_BLUE='\033[0;34m'
declare -gr COLOR_MAGENTA='\033[0;35m'
declare -gr COLOR_CYAN='\033[0;36m'

declare -gi USE_COLOR=0
[[ -z "${NO_COLOR:-}" ]] && { [[ -t 1 ]] || [[ -t 2 ]]; } && USE_COLOR=1

# colorizes a log level tag (e.g. '[INFO]') for terminal output, falling back to
# plain text when stdout/stderr are not a tty or when NO_COLOR is set
function tag() {
    local level="$1" color=""

    case "$level" in
    INFO)
        color="$COLOR_GREEN"
        ;;
    WARN)
        color="$COLOR_YELLOW"
        ;;
    ERROR)
        color="$COLOR_RED"
        ;;
    NOTICE)
        color="$COLOR_CYAN"
        ;;
    DEBUG)
        color="$COLOR_MAGENTA"
        ;;
    PROMPT)
        color="$COLOR_BLUE"
        ;;
    esac

    if (( USE_COLOR == 1 )); then
        printf '%b[%s]%b' "$color" "$level" "$COLOR_RESET"
    else
        printf '[%s]' "$level"
    fi

    return 0
}

function print_usage() {
cat <<EOF
Summary:
    Installer for Linux configs (vim, neovim, and more)
Usage:
    $0 [-h] [-cc] [-cp] [-sp] [-sc] [-im INSTALL_MODE] [-cm CONFIG_MODE] [APP...]
Options:
    -h      help                - show installer documentation
    -cc     clean configs       - remove existing editor configs, data, state and cache, then reinstall them
    -cp     clean packages      - remove installed packages/binaries for the selected apps, then reinstall them
    -sp     skip packages       - skip installing package dependencies
    -sc     skip configs        - skip installing editor configurations
    -im     install mode        - where packages are installed: system, user, auto (default: auto)
    -cm     config mode         - where editor configs are installed: global, users, local, auto (default: auto)
Arguments:
    APP     app(s) to install   - one or more of: ${ALL_APPS[*]}
                                - defaults to all ${#ALL_APPS[@]} apps when none are given
Notes:
    +   The installer should be run as the target user apps will be configured for
    +   Installing package dependencies requires target user to have sudo privileges
    +   The following package managers are supported by the installer:
            apt-get   ->  debian-based distros
            pacman    ->  arch-based distros
            nix       ->  nixos / nix package manager
            flatpak   ->  sandboxed app distribution
            bin       ->  marcosnils/bin, generic github release binary manager
    +   Provider order for each app is flatpak (remote or local bundle), then binpak (bin release), then syspak (system package manager, remote or local .deb)
    +   INSTALL_MODE=auto resolves to 'system' when running as root (EUID=0), else 'user'
    +   CONFIG_MODE=auto resolves to 'users' when the resolved install mode is 'system', else 'local'
EOF
}

function is_valid_app() {
    local app candidate
    app="$1"

    for candidate in "${ALL_APPS[@]}"; do
        [[ "$candidate" == "$app" ]] && return 0
    done

    return 1
}

function app_selected() {
    local app candidate
    app="$1"

    for candidate in "${APPS[@]}"; do
        [[ "$candidate" == "$app" ]] && return 0
    done

    return 1
}

# a family (neovim, vim) is selected when at least one of its apps is selected
function family_selected() {
    local family="$1" app

    for app in ${FAMILY_APPS[$family]:-}; do
        if app_selected "$app"; then
            return 0
        fi
    done

    return 1
}

function is_valid_install_mode() {
    local mode candidate
    mode="$1"

    for candidate in "${VALID_INSTALL_MODES[@]}"; do
        [[ "$candidate" == "$mode" ]] && return 0
    done

    return 1
}

function is_valid_config_mode() {
    local mode candidate
    mode="$1"

    for candidate in "${VALID_CONFIG_MODES[@]}"; do
        [[ "$candidate" == "$mode" ]] && return 0
    done

    return 1
}

function resolve_scope() {
    if [[ "$INSTALL_MODE" == "auto" ]]; then
        if (( EUID == 0 )); then
            RESOLVED_INSTALL_MODE="system"
        else
            RESOLVED_INSTALL_MODE="user"
        fi
    else
        RESOLVED_INSTALL_MODE="$INSTALL_MODE"
    fi

    if [[ "$CONFIG_MODE" == "auto" ]]; then
        if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
            RESOLVED_CONFIG_MODE="users"
        else
            RESOLVED_CONFIG_MODE="local"
        fi
    else
        RESOLVED_CONFIG_MODE="$CONFIG_MODE"
    fi

    return 0
}

# after argument validation: offers sudo so a user-scope run can still install base
# dependencies, system packages and the man AppArmor override (skipped when root,
# when packages are skipped, or when there is no terminal to ask on)
function prompt_sudo() {
    local answer

    local needs_root=0 why=""

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        needs_root=1
        why="'-im system'"
    elif (( SKIP_CONFIGS != 1 )) && [[ "$RESOLVED_CONFIG_MODE" != "local" ]]; then
        needs_root=1
        why="'-cm ${RESOLVED_CONFIG_MODE}'"
    fi

    (( EUID == 0 )) && return 0
    if (( needs_root == 0 && SKIP_PACKAGES == 1 )); then
        return 0
    fi

    if ! command -v sudo &>/dev/null || [[ ! -t 0 ]]; then
        if (( needs_root == 1 )); then
            echo "$(tag ERROR): $why requires root (EUID=0) or an interactive sudo" >&2
            exit 1
        fi
        return 0
    fi

    if (( needs_root == 1 )); then
        echo "$(tag NOTICE): $why requires root privileges; sudo is needed"
        answer="y"
    else
        read -r -p "$(tag PROMPT) Use sudo to install base dependencies and system packages? [y/N] " answer
    fi
    case "$answer" in
    y|Y|yes|YES)
        if sudo -v; then
            SUDO_GRANTED=1
        else
            echo "$(tag WARN) sudo authentication failed; continuing without sudo" >&2
        fi
        ;;
    esac

    if (( needs_root == 1 && SUDO_GRANTED != 1 )); then
        echo "$(tag ERROR): $why requires root privileges and sudo was not granted" >&2
        exit 1
    fi

    return 0
}

# true when privileged package installs are possible (system scope or sudo granted)
function can_use_sudo() {
    [[ "$RESOLVED_INSTALL_MODE" == "system" ]] || (( SUDO_GRANTED == 1 ))
}

# flatpak pagers run under man's AppArmor profile, which denies the user namespace bwrap needs
function ensure_man_apparmor_userns() {
    local local_file="/etc/apparmor.d/local/usr.bin.man" profile="/etc/apparmor.d/usr.bin.man"
    local marker="# linux-configs: allow flatpak (bwrap) pagers under man"
    local -a priv=()

    [[ -f "$profile" ]] || return 0
    command -v apparmor_parser &>/dev/null || return 0
    grep -qsF "$marker" "$local_file" && return 0

    if (( EUID != 0 )); then
        if (( SUDO_GRANTED != 1 )); then
            echo "$(tag NOTICE): no sudo; add 'userns,' to $local_file by hand so flatpak pagers work under man"
            return 0
        fi
        priv=(sudo)
    fi

    printf '%s\nuserns,\n' "$marker" | "${priv[@]}" tee -a "$local_file" >/dev/null
    if ! "${priv[@]}" apparmor_parser -r "$profile"; then
        echo "$(tag WARN) could not reload the man AppArmor profile; reverting the userns override" >&2
        "${priv[@]}" sed -i -e "\|$marker|,+1d" "$local_file"
        return 0
    fi
    echo "$(tag INFO) Allowed user namespaces for man in AppArmor ($local_file)"

    return 0
}

function setup_install() {
    while (( $# > 0 )); do
        case "$1" in
        -h)
            print_usage
            exit 0
            ;;
        -cc)
            CLEAN_CONFIGS=1
            shift
            ;;
        -cp)
            CLEAN_PACKAGES=1
            shift
            ;;
        -sp)
            SKIP_PACKAGES=1
            shift
            ;;
        -sc)
            SKIP_CONFIGS=1
            shift
            ;;
        -im)
            if (( $# < 2 )) || ! is_valid_install_mode "$2"; then
                echo "$(tag ERROR): '-im' requires one of: ${VALID_INSTALL_MODES[*]}" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            INSTALL_MODE="$2"
            shift 2
            ;;
        -cm)
            if (( $# < 2 )) || ! is_valid_config_mode "$2"; then
                echo "$(tag ERROR): '-cm' requires one of: ${VALID_CONFIG_MODES[*]}" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            CONFIG_MODE="$2"
            shift 2
            ;;
        -*)
            echo "$(tag ERROR): Invalid argument '$1'" >&2
            echo "" >&2
            print_usage >&2
            exit 1
            ;;
        *)
            if ! is_valid_app "$1"; then
                echo "$(tag ERROR): Invalid app '$1'" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            if app_selected "$1"; then
                echo "$(tag ERROR): Duplicate app '$1'" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            APPS+=("$1")
            shift
            ;;
        esac
    done

    (( ${#APPS[@]} == 0 )) && APPS=("${ALL_APPS[@]}")

    resolve_scope

    prompt_sudo

    return 0
}

# per-family maps: each family appends only its own entries (APT_PKG_NAME+=(...)),
# so neither family needs to know about the other's apps
declare -gA APT_PKG_NAME=()
declare -gA PACMAN_PKG_NAME=()
declare -gA FLATPAK_APP_ID=()
# sandboxed apps used as pagers by arbitrary host tools need the real host filesystem
# ('host'), and flatpak gives each sandbox a private /tmp, so '/tmp' is granted too
declare -gA FLATPAK_FS_OVERRIDES=()
# run-only flags (not settable as overrides) for apps launched from AppArmor-confined parents:
# the dbus proxies make 'flatpak run' list '/', denied under man's profile, so such apps get a
# minimal exec wrapper instead of the plain symlink
declare -gA FLATPAK_RUN_FLAGS=()
# NVIM_APPNAMEs whose host XDG dirs are shared with the flatpak sandbox
declare -gA FLATPAK_XDG_APPNAMES=()
# apps whose flatpak sandbox also gets the user-local bin dir on its PATH
declare -gA FLATPAK_PATH_EXPOSE=()
declare -gA BIN_GH_REPO=()
declare -gA BIN_ASSET_GLOB=()
declare -gA LOCAL_DEB_RESOURCE=()
# committed flatpak bundles in resources/, installed on top of FLATPAK_BASE_APP_ID (from flathub)
declare -gA LOCAL_FLATPAK_RESOURCE=()
declare -gA FLATPAK_BASE_APP_ID=()
# auto-mode provider order: flatpak (remote or local bundle), binpak (bin release), syspak (system package manager)
declare -ga BACKEND_ORDER=(flatpak bin_pkgmgr sys_pkg_mgr)

function resolved_bin_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        echo "/usr/local/bin"
    else
        echo "$HOME/.local/bin"
    fi

    return 0
}

function bin_pkgmgr_target_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        echo "/usr/share/binpak"
    else
        echo "$HOME/.local/share/binpak"
    fi

    return 0
}

function install_baseline_tools() {
    echo "$(tag INFO) Installing baseline build/runtime tools via system package manager"

    if command -v apt-get &>/dev/null; then
        sudo apt-get update -y
        sudo apt-get install -y git curl build-essential unzip
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu --noconfirm --needed git curl base-devel unzip
    elif command -v nix &>/dev/null; then
        sudo nix-env -iA nixpkgs.git nixpkgs.curl nixpkgs.gnumake nixpkgs.gcc nixpkgs.unzip
    else
        echo "$(tag ERROR): Unsupported package manager" >&2
        exit 1
    fi

    echo "$(tag INFO) Finished installing baseline tools"

    return 0
}

function install_via_sys_pkg_mgr() {
    local dep="$1" version="${2:-latest}"
    local pkg deb_name deb_path

    if can_use_sudo; then
        if command -v apt-get &>/dev/null; then
            deb_name="${LOCAL_DEB_RESOURCE[$dep]:-}"
            if [[ -n "$deb_name" ]]; then
                deb_path="$SCRIPT_DIR/resources/$deb_name"
                if [[ -f "$deb_path" ]]; then
                    sudo dpkg -i "$deb_path" || sudo apt-get install -y -f
                    return 0
                fi
            fi

            pkg="${APT_PKG_NAME[$dep]:-}"
            [[ -n "$pkg" ]] || return 1
            [[ "$version" != "latest" ]] && pkg="$pkg=$version"
            sudo apt-get install -y "$pkg" && return 0
            return 1
        elif command -v pacman &>/dev/null; then
            [[ "$version" == "latest" ]] || {
                echo "$(tag NOTICE): pacman does not support pinning arbitrary versions, installing latest instead" >&2
            }
            pkg="${PACMAN_PKG_NAME[$dep]:-}"
            [[ -n "$pkg" ]] || return 1
            sudo pacman -S --noconfirm --needed "$pkg" && return 0
            return 1
        elif command -v nix &>/dev/null; then
            [[ "$version" == "latest" ]] || {
                echo "$(tag NOTICE): nixpkgs does not support pinning arbitrary versions here, installing latest instead" >&2
            }
            pkg="${APT_PKG_NAME[$dep]:-}"
            [[ -n "$pkg" ]] || return 1
            sudo nix-env -iA "nixpkgs.$pkg" && return 0
            return 1
        fi

        return 1
    fi

    # user scope: only a user-profile-capable manager (nix) qualifies here,
    # since apt/pacman cannot install packages without root
    if command -v nix &>/dev/null; then
        [[ "$version" == "latest" ]] || {
            echo "$(tag NOTICE): nixpkgs does not support pinning arbitrary versions here, installing latest instead" >&2
        }
        pkg="${APT_PKG_NAME[$dep]:-}"
        [[ -n "$pkg" ]] || return 1
        nix profile install "nixpkgs#$pkg" && return 0
        return 1
    fi

    return 1
}

# flatpak can leave a half-removed deploy dir behind ("Directory not empty" on uninstall) that
# is invisible to 'flatpak info' yet makes a later install a silent no-op; drop such leftovers
function flatpak_purge_stale_deploy() {
    local app_id="$1" scope_flag="$2" app_dir removed_dir
    local -a priv

    if [[ "$scope_flag" == "--system" ]]; then
        app_dir="/var/lib/flatpak/app/$app_id"
        removed_dir="/var/lib/flatpak/.removed"
        priv=(sudo)
    else
        app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/app/$app_id"
        removed_dir="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/.removed"
        priv=()
    fi

    # a stale '.removed/<app>-<commit>' left by an earlier failed removal makes every later
    # uninstall fail with "Directory not empty" (rename onto the existing dir), so clear it
    if [[ -d "$removed_dir" ]]; then
        "${priv[@]}" rm -rf "$removed_dir/$app_id"-* 2>/dev/null || true
    fi

    flatpak info "$scope_flag" "$app_id" &>/dev/null && return 0
    [[ -d "$app_dir" ]] && "${priv[@]}" rm -rf "$app_dir"

    return 0
}

function install_via_flatpak() {
    local dep="$1" cmd_name="$2" version="${3:-latest}"
    local app_id scope_flag target_dir export_bin install_ref bundle base_id
    local -a priv

    app_id="${FLATPAK_APP_ID[$dep]:-}"
    [[ -n "$app_id" ]] || return 1
    command -v flatpak &>/dev/null || return 1

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        scope_flag="--system"
    else
        scope_flag="--user"
    fi

    flatpak_purge_stale_deploy "$app_id" "$scope_flag"

    if [[ -n "${LOCAL_FLATPAK_RESOURCE[$dep]:-}" ]]; then
        # committed bundle: only a single build exists, so pinned versions fall through to the next backend
        [[ "$version" == "latest" ]] || return 1
        bundle="$SCRIPT_DIR/resources/${LOCAL_FLATPAK_RESOURCE[$dep]}"
        [[ -f "$bundle" ]] || return 1
        base_id="${FLATPAK_BASE_APP_ID[$dep]:-}"
        [[ -n "$base_id" ]] || return 1
        flatpak info "$base_id" &>/dev/null || flatpak install --noninteractive --assumeyes "$scope_flag" flathub "$base_id" || return 1
        flatpak install --noninteractive --assumeyes "$scope_flag" "$bundle" || return 1
    else
        install_ref="$app_id"
        [[ "$version" == "latest" ]] || install_ref="$app_id//$version"

        flatpak install --noninteractive --assumeyes "$scope_flag" flathub "$install_ref" || return 1
    fi

    flatpak info "$scope_flag" "$app_id" &>/dev/null || return 1

    configure_flatpak_app "$dep" "$app_id" || return 1
    ensure_man_apparmor_userns

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        priv=(sudo)
        export_bin="/var/lib/flatpak/exports/bin/$app_id"
    else
        priv=()
        export_bin="$HOME/.local/share/flatpak/exports/bin/$app_id"
    fi
    target_dir="$(resolved_bin_dir)"
    "${priv[@]}" mkdir -p "$target_dir"
    if [[ -n "${FLATPAK_RUN_FLAGS[$dep]:-}" ]]; then
        "${priv[@]}" rm -f "$target_dir/$cmd_name"
        printf '#!/bin/sh\nexec flatpak run %s %s "$@"\n' "${FLATPAK_RUN_FLAGS[$dep]}" "$app_id" | "${priv[@]}" tee "$target_dir/$cmd_name" >/dev/null
        "${priv[@]}" chmod +x "$target_dir/$cmd_name"
    else
        "${priv[@]}" ln -sfn "$export_bin" "$target_dir/$cmd_name"
    fi

    return 0
}

# flatpak forces XDG_*_HOME to ~/.var/app/<id>/...; 'xdg-{config,data,cache}/<name>'
# overrides bind-mount the host dirs there, while state (no xdg-state location) is symlinked
# config mode decides where overrides live: local -> per-user (--user) for $HOME,
# users/global -> system-wide overrides applying to every user's home ('/etc/skel' seeds them)
function configure_flatpak_app() {
    local dep="$1" app_id="$2"
    local fs appname cfg_home sandbox_dir
    local -a override_cmd priv override_args=()

    case "$RESOLVED_CONFIG_MODE" in
    local)
        cfg_home="$HOME"
        priv=()
        override_cmd=(flatpak override --user)
        ;;
    users)
        cfg_home="/etc/skel"
        priv=(sudo)
        override_cmd=(sudo flatpak override --system)
        ;;
    global)
        cfg_home=""
        priv=(sudo)
        override_cmd=(sudo flatpak override --system)
        echo "$(tag NOTICE): flatpak '$app_id' does not read host system-wide configs (/etc, /usr/share); only per-user configs are exposed"
        ;;
    esac

    for fs in ${FLATPAK_FS_OVERRIDES[$dep]:-}; do
        # a leading '!' revokes a permission (e.g. '!host' inherited from the base app)
        if [[ "$fs" == '!'* ]]; then
            override_args+=("--nofilesystem=${fs#!}")
        else
            override_args+=("--filesystem=$fs")
        fi
    done
    for appname in ${FLATPAK_XDG_APPNAMES[$dep]:-}; do
        override_args+=("--filesystem=xdg-config/$appname" "--filesystem=xdg-data/$appname"
            "--filesystem=xdg-cache/$appname" "--filesystem=~/.local/state/$appname")
    done

    # expose host tools (e.g. tree-sitter installed via bin) on the sandbox PATH
    # the sandbox's own default PATH is queried (with any previous override dropped) and the
    # host tool dir appended, instead of hardcoding sandbox-internal paths
    if [[ -n "${FLATPAK_PATH_EXPOSE[$dep]:-}" ]]; then
        local sandbox_path override_file
        if [[ "$RESOLVED_CONFIG_MODE" != "local" ]]; then
            override_file="/var/lib/flatpak/overrides/$app_id"
        else
            override_file="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/overrides/$app_id"
        fi
        # drop a previously set PATH/unset-environment so flatpak reports the sandbox default
        if [[ -f "$override_file" ]]; then
            "${priv[@]}" sed -i -e '/^PATH=/d' -e '/^unset-environment=PATH;$/d' "$override_file"
        fi
        sandbox_path="$(flatpak run --command=printenv "$app_id" PATH)" || return 1
        if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
            # 'host' already exposes /usr/local/bin at its normal host path (unlike
            # 'host-os', which would remount it under /run/host to avoid conflicts)
            override_args+=("--env=PATH=$sandbox_path:/usr/local/bin")
        elif [[ "$RESOLVED_CONFIG_MODE" == "local" ]]; then
            override_args+=("--env=PATH=$sandbox_path:$HOME/.local/bin")
        else
            echo "$(tag NOTICE): user-scope tools in '$(resolved_bin_dir)' are not exposed to other users' '$app_id' sandbox"
        fi
    fi

    if (( ${#override_args[@]} > 0 )); then
        "${override_cmd[@]}" "${override_args[@]}" "$app_id" || return 1
    fi

    [[ -n "$cfg_home" ]] || return 0

    # bind-mount sources must exist; state has no xdg-state location so it is a relative symlink
    for appname in ${FLATPAK_XDG_APPNAMES[$dep]:-}; do
        "${priv[@]}" mkdir -p "$cfg_home/.config/$appname" "$cfg_home/.local/share/$appname" \
            "$cfg_home/.cache/$appname" "$cfg_home/.local/state/$appname"
        sandbox_dir="$cfg_home/.var/app/$app_id/.local/state/$appname"
        "${priv[@]}" mkdir -p "${sandbox_dir%/*}"
        if [[ -d "$sandbox_dir" && ! -L "$sandbox_dir" ]]; then
            echo "$(tag NOTICE): moving existing sandbox dir '$sandbox_dir' to '$sandbox_dir.bak'"
            "${priv[@]}" rm -rf "$sandbox_dir.bak"
            "${priv[@]}" mv "$sandbox_dir" "$sandbox_dir.bak"
        fi
        "${priv[@]}" ln -sfn "../../../../../.local/state/$appname" "$sandbox_dir"
    done

    return 0
}

function install_via_bin_pkgmgr() {
    local dep="$1" cmd_name="$2" version="${3:-latest}"
    local repo asset install_ref pkg_target_dir link_dir
    local -a bin_cmd

    repo="${BIN_GH_REPO[$dep]:-}"
    [[ -n "$repo" ]] || return 1
    command -v bin &>/dev/null || return 1

    asset="${BIN_ASSET_GLOB[$dep]:-}"
    install_ref="github.com/$repo"
    [[ "$version" == "latest" ]] || install_ref="$install_ref/releases/tag/$version"

    pkg_target_dir="$(bin_pkgmgr_target_dir)"
    link_dir="$(resolved_bin_dir)"

    bin_cmd=(bin install --force "$install_ref")
    if [[ -n "$asset" ]]; then
        bin_cmd+=(-n "$asset")
    fi
    bin_cmd+=("$pkg_target_dir/$cmd_name")

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        sudo mkdir -p "$pkg_target_dir" "$link_dir"
        sudo "${bin_cmd[@]}" || return 1
    else
        mkdir -p "$pkg_target_dir" "$link_dir"
        "${bin_cmd[@]}" || return 1
    fi

    ln -sf "$pkg_target_dir/$cmd_name" "$link_dir/$cmd_name"

    return 0
}

# checks whether 'dep' is already installed via the system package manager
# (apt/pacman/nix), so a prior install from that backend can be reused as-is
function is_installed_via_sys_pkg_mgr() {
    local dep="$1" pkg

    if command -v dpkg-query &>/dev/null; then
        pkg="${APT_PKG_NAME[$dep]:-$dep}"
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" && return 0
    fi

    if command -v pacman &>/dev/null; then
        pkg="${PACMAN_PKG_NAME[$dep]:-$dep}"
        pacman -Qi "$pkg" &>/dev/null && return 0
    fi

    if command -v nix &>/dev/null; then
        pkg="${APT_PKG_NAME[$dep]:-$dep}"
        nix profile list 2>/dev/null | grep -q "$pkg" && return 0
    fi

    return 1
}

# checks whether 'dep' is already installed as a flatpak app
function is_installed_via_flatpak() {
    local dep="$1" app_id

    app_id="${FLATPAK_APP_ID[$dep]:-}"
    [[ -n "$app_id" ]] || return 1
    command -v flatpak &>/dev/null || return 1

    flatpak info "$app_id" &>/dev/null && return 0

    return 1
}

# checks whether 'dep' is already installed via the 'bin' package manager
# (i.e. a prior 'install_via_bin_pkgmgr' run already placed it in its target dir)
function is_installed_via_bin_pkgmgr() {
    local dep="$1" cmd_name="$2"

    [[ -n "${BIN_GH_REPO[$dep]:-}" ]] || return 1
    [[ -e "$(bin_pkgmgr_target_dir)/$cmd_name" ]] && return 0

    return 1
}

# prints the providers to use, one per line: system install mode uses only the system
# package manager; other modes use BACKEND_ORDER
function active_backend_order() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        echo "sys_pkg_mgr"
    else
        printf '%s\n' "${BACKEND_ORDER[@]}"
    fi
}

# returns (on stdout) the name of the first backend (in BACKEND_ORDER) that
# already provides 'dep', so install_editor_dep can reuse it instead of
# re-prompting/reinstalling; returns non-zero if nothing is installed yet
function detect_installed_backend() {
    local dep="$1" cmd_name="$2" backend
    local -a order

    mapfile -t order < <(active_backend_order)

    for backend in "${order[@]}"; do
        case "$backend" in
        sys_pkg_mgr)
            is_installed_via_sys_pkg_mgr "$dep" && { echo "$backend"; return 0; }
            ;;
        flatpak)
            is_installed_via_flatpak "$dep" && { echo "$backend"; return 0; }
            ;;
        bin_pkgmgr)
            is_installed_via_bin_pkgmgr "$dep" "$cmd_name" && { echo "$backend"; return 0; }
            ;;
        esac
    done

    return 1
}

function install_editor_dep() {
    local dep="$1" cmd_name="${2:-$1}"
    local backend version existing_backend
    local -a order

    if existing_backend="$(detect_installed_backend "$dep" "$cmd_name")"; then
        echo "$(tag INFO) '$dep' is already installed via $existing_backend; using the existing installation"
        return 0
    fi

    version="latest"
    mapfile -t order < <(active_backend_order)

    for backend in "${order[@]}"; do
        case "$backend" in
        sys_pkg_mgr)
            echo "$(tag INFO) Installing '$dep' ($version) via system package manager"
            install_via_sys_pkg_mgr "$dep" "$version" && {
                echo "$(tag INFO) Installed '$dep' ($version) via system package manager"
                return 0
            }
            ;;
        flatpak)
            echo "$(tag INFO) Installing '$dep' ($version) via flatpak"
            install_via_flatpak "$dep" "$cmd_name" "$version" && {
                echo "$(tag INFO) Installed '$dep' ($version) via flatpak"
                return 0
            }
            ;;
        bin_pkgmgr)
            echo "$(tag INFO) Installing '$dep' ($version) via bin package manager"
            install_via_bin_pkgmgr "$dep" "$cmd_name" "$version" && {
                echo "$(tag INFO) Installed '$dep' ($version) via bin package manager"
                return 0
            }
            ;;
        esac
        echo "$(tag WARN) backend '$backend' could not provide '$dep', trying next backend" >&2
    done

    if [[ "$version" == "latest" ]] && command -v "$cmd_name" &>/dev/null; then
        echo "$(tag INFO) Using already-installed '$cmd_name' at $(command -v "$cmd_name") for '$dep'"
        return 0
    fi

    echo "$(tag ERROR): Failed to install '$dep' via any available backend" >&2
    exit 1
}

# removes a dependency installed by any backend (flatpak app, bin release or system package), skipping
# missing ones quietly; used by the families' clean-packages (-cp) step
function uninstall_dep() {
    local dep="$1" cmd_name="${2:-$1}" pkg bin_target link_dir

    if [[ -n "${FLATPAK_APP_ID[$dep]:-}" ]] && command -v flatpak &>/dev/null; then
        flatpak_purge_stale_deploy "${FLATPAK_APP_ID[$dep]}" "$([[ "$RESOLVED_INSTALL_MODE" == "system" ]] && echo --system || echo --user)"
    fi
    if is_installed_via_flatpak "$dep"; then
        flatpak uninstall -y --noninteractive "${FLATPAK_APP_ID[$dep]}" &>/dev/null || true
        flatpak_purge_stale_deploy "${FLATPAK_APP_ID[$dep]}" "$([[ "$RESOLVED_INSTALL_MODE" == "system" ]] && echo --system || echo --user)"
    fi
    if is_installed_via_bin_pkgmgr "$dep" "$cmd_name"; then
        bin_target="$(bin_pkgmgr_target_dir)/$cmd_name"
        link_dir="$(resolved_bin_dir)"
        if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
            [[ "$(readlink "$link_dir/$cmd_name" 2>/dev/null)" == "$bin_target" ]] && sudo rm -f "$link_dir/$cmd_name"
            sudo rm -rf "$bin_target"
        else
            [[ "$(readlink "$link_dir/$cmd_name" 2>/dev/null)" == "$bin_target" ]] && rm -f "$link_dir/$cmd_name"
            rm -rf "$bin_target"
        fi
    fi
    if is_installed_via_sys_pkg_mgr "$dep"; then
        pkg="${APT_PKG_NAME[$dep]:-$dep}"
        if command -v dpkg-query &>/dev/null && dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            sudo apt-get remove -y "$pkg" &>/dev/null || true
        elif command -v pacman &>/dev/null; then
            sudo pacman -Rns --noconfirm "${PACMAN_PKG_NAME[$dep]:-$dep}" &>/dev/null || true
        fi
    fi

    # drop leftover PATH symlinks / flatpak run wrappers (and legacy dedicated-editor links) from previous installs
    link_dir="$(resolved_bin_dir)"
    local -a rm_cmd=(rm)
    [[ "$RESOLVED_INSTALL_MODE" == "system" && $EUID -ne 0 ]] && rm_cmd=(sudo rm)
    local stale
    for stale in "$link_dir/$cmd_name" "$link_dir/$cmd_name-nvim"; do
        if [[ -L "$stale" ]] || { [[ -f "$stale" ]] && grep -q 'flatpak run' "$stale" 2>/dev/null && [[ $(wc -c <"$stale") -lt 1024 ]]; }; then
            "${rm_cmd[@]}" -f "$stale"
        fi
    done

    return 0
}

# configures the given families for the resolved config mode; each family provides
# <family>_configure_home, <family>_clean_home and <family>_configure_global
function configure_apps() {
    local family home_dir
    local -a families=("$@")

    if [[ "$RESOLVED_CONFIG_MODE" != "local" ]] && (( EUID != 0 && SUDO_GRANTED != 1 )); then
        echo "$(tag ERROR): '-cm ${RESOLVED_CONFIG_MODE}' requires running as root (EUID=0)" >&2
        exit 1
    fi

    case "$RESOLVED_CONFIG_MODE" in
    global)
        echo "$(tag INFO) Installing global default editor configurations"
        for family in "${families[@]}"; do
            "${family}_configure_global"
        done
        echo "$(tag INFO) Finished installing global configurations"
        ;;
    users)
        echo "$(tag INFO) Installing default editor configurations to /etc/skel"
        sudo mkdir -p /etc/skel
        for family in "${families[@]}"; do
            if (( CLEAN_CONFIGS == 1 )); then
                "${family}_clean_home" /etc/skel 1
            fi
            "${family}_configure_home" /etc/skel 1
        done
        if (( CLEAN_CONFIGS == 1 )); then
            for home_dir in /home/*/; do
                home_dir="${home_dir%/}"
                [[ -d "$home_dir" ]] || continue
                echo "$(tag INFO) Refreshing configs for $home_dir"
                for family in "${families[@]}"; do
                    "${family}_clean_home" "$home_dir" 1
                    "${family}_configure_home" "$home_dir" 1
                done
                sudo chown -R --reference="$home_dir" "$home_dir"
            done
        fi
        echo "$(tag INFO) Finished installing default configurations"
        ;;
    local)
        echo "$(tag INFO) Configuring apps for user $USER (local scope)"
        for family in "${families[@]}"; do
            if (( CLEAN_CONFIGS == 1 )); then
                "${family}_clean_home" "$HOME" 0
            fi
            "${family}_configure_home" "$HOME" 0
        done
        echo "$(tag INFO) Finished configuring apps"
        ;;
    esac

    return 0
}

# drives the install for the given families (e.g. 'vim neovim'), each limited to its
# selected apps: clean packages (-cp), dependencies, configs (-cc), then plugin sync;
# each family provides <family>_clean_packages, _install_deps and _install_plugins
function run_install() {
    local family
    local -a families=()

    for family in "$@"; do
        if family_selected "$family"; then
            families+=("$family")
        fi
    done

    echo "$(tag INFO) Starting linux-configs installation for: ${families[*]}"

    if (( CLEAN_PACKAGES == 1 )); then
        for family in "${families[@]}"; do
            "${family}_clean_packages"
        done
    fi

    if (( SKIP_PACKAGES != 1 )); then
        echo "$(tag INFO) Installing app dependencies (install mode: $RESOLVED_INSTALL_MODE)"
        if can_use_sudo; then
            install_baseline_tools
        else
            echo "$(tag NOTICE): skipping baseline tool install (git/curl/build tools) without sudo; ensure they are already present"
        fi
        for family in "${families[@]}"; do
            "${family}_install_deps"
        done
        echo "$(tag INFO) Finished installing app dependencies"
    fi

    if (( SKIP_CONFIGS != 1 )); then
        configure_apps "${families[@]}"

        if [[ "$RESOLVED_CONFIG_MODE" == "local" ]]; then
            for family in "${families[@]}"; do
                "${family}_install_plugins"
            done
        else
            echo "$(tag NOTICE) Skipping plugin sync for config mode '$RESOLVED_CONFIG_MODE': plugins must be installed/updated per-user by running '$0 -cm local' as that user"
        fi
    else
        echo "$(tag NOTICE) Skipping plugin sync because configs were skipped ('-sc')"
    fi

    echo "$(tag INFO) Completed linux-configs installation"
    print_post_install

    return 0
}

function print_post_install() {
cat <<'EOF'
You may want to configure these additional settings.

~/.bashrc:
    export PAGER='nvimpager'
    export MANPAGER='nvimpager -p'
    export EDITOR='nvim'
    export VISUAL='nvim'

~/.gitconfig:
[core]
	pager = nvimpager -a
	editor = NVIM_APPNAME=nvimgit nvim
[diff]
    tool = nvim
[difftool "vim"]
    cmd = vimdiff "$LOCAL" "$REMOTE"
[difftool "nvim"]
    cmd = NVIM_APPNAME=nvimgit nvim -d "$LOCAL" "$REMOTE"
[merge]
    tool = nvim
[mergetool "vim"]
    cmd = vimdiff "$LOCAL" "$MERGED" "$REMOTE"
[mergetool "nvim"]
    cmd = NVIM_APPNAME=nvimgit nvim -d "$LOCAL" "$MERGED" "$REMOTE"

EOF
}
