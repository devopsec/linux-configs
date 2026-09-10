#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit nullglob

declare -g  SCRIPT_DIR

# this is the real way to do it
#SCRIPT_DIR="$(dirname $(realpath "$BASH_SOURCE"))"

declare -gi CLEAN_INSTALL=0
declare -gi SKIP_PACKAGES=0
declare -gi SKIP_CONFIGS=0
declare -ga ALL_APPS=(vim nvim nvimgit nvimpager vimpager)
declare -ga APPS=()

declare -ga VALID_INSTALL_MODES=(system user auto)
declare -ga VALID_CONFIG_MODES=(global users local auto)
declare -g  INSTALL_MODE="auto"
declare -g  CONFIG_MODE="auto"
declare -g  RESOLVED_INSTALL_MODE
declare -g  RESOLVED_CONFIG_MODE

function print_usage() {
cat <<EOF
Summary:
    Installer for Vim-like Text Editors (xvim)
Usage:
    $0 [-h] [-ci] [-sp] [-sc] [-im INSTALL_MODE] [-cm CONFIG_MODE] [APP...]
Options:
    -h      help                - show installer documentation
    -ci     clean install       - overwrite existing editor configs and clear state/cache
    -sp     skip packages       - skip installing package dependencies
    -sc     skip configs        - skip installing editor configurations
    -im     install mode        - where packages are installed: system, user, auto (default: auto)
    -cm     config mode         - where editor configs are installed: global, users, local, auto (default: auto)
Arguments:
    APP     app(s) to install   - one or more of: vim nvim nvimgit nvimpager vimpager
                                - defaults to all 5 apps when none are given
Notes:
    +   The installer should be run as the target user apps will be configured for
    +   Installing package dependencies requires target user to have sudo privileges
    +   The following package managers are supported by the installer:
            apt-get   ->  debian-based distros
            pacman    ->  arch-based distros
            nix       ->  nixos / nix package manager
            flatpak   ->  sandboxed app distribution
            bin       ->  marcosnils/bin, generic github release binary manager
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

function setup_install() {
    while (( $# > 0 )); do
        case "$1" in
        -h)
            print_usage
            exit 0
            ;;
        -ci)
            CLEAN_INSTALL=1
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
                echo "[ERROR]: '-im' requires one of: ${VALID_INSTALL_MODES[*]}" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            INSTALL_MODE="$2"
            shift 2
            ;;
        -cm)
            if (( $# < 2 )) || ! is_valid_config_mode "$2"; then
                echo "[ERROR]: '-cm' requires one of: ${VALID_CONFIG_MODES[*]}" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            CONFIG_MODE="$2"
            shift 2
            ;;
        -*)
            echo "[ERROR]: Invalid argument '$1'" >&2
            echo "" >&2
            print_usage >&2
            exit 1
            ;;
        *)
            if ! is_valid_app "$1"; then
                echo "[ERROR]: Invalid app '$1'" >&2
                echo "" >&2
                print_usage >&2
                exit 1
            fi
            if app_selected "$1"; then
                echo "[ERROR]: Duplicate app '$1'" >&2
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

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]] && (( EUID != 0 )); then
        echo "[ERROR]: '-im system' requires running as root (EUID=0)" >&2
        exit 1
    fi

    SCRIPT_DIR="$(realpath -m "${BASH_SOURCE[0]}/../")"

    return 0
}

declare -gA APT_PKG_NAME=(
    [vim]="vim"
    [nvim]="neovim"
    [nvimpager]="nvimpager"
    [tree-sitter-cli]="tree-sitter-cli"
)
declare -gA PACMAN_PKG_NAME=(
    [vim]="vim"
    [nvim]="neovim"
    [nvimpager]="nvimpager"
    [tree-sitter-cli]="tree-sitter-cli"
)
declare -gA FLATPAK_APP_ID=(
    [vim]="org.vim.Vim"
    [nvim]="io.neovim.nvim"
)
declare -gA BIN_GH_REPO=(
    [nvim]="neovim/neovim"
    [tree-sitter-cli]="tree-sitter/tree-sitter"
)
declare -gA LOCAL_DEB_RESOURCE=(
    [nvimpager]="nvimpager_0.14.0-1_all.deb"
    [vimpager]="vimpager_2.06-2_all.deb"
)
declare -ga BACKEND_ORDER=(sys_pkg_mgr flatpak bin_pkgmgr)

function resolved_bin_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        echo "/usr/local/bin"
    else
        echo "$HOME/.local/bin"
    fi

    return 0
}

function flatpak_export_bin_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        echo "/var/lib/flatpak/exports/bin"
    else
        echo "$HOME/.local/share/flatpak/exports/bin"
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
    echo "[INFO] Installing baseline build/runtime tools via system package manager"

    if command -v apt-get &>/dev/null; then
        sudo apt-get update -y
        sudo apt-get install -y git curl build-essential unzip
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu --noconfirm --needed git curl base-devel unzip
    elif command -v nix &>/dev/null; then
        sudo nix-env -iA nixpkgs.git nixpkgs.curl nixpkgs.gnumake nixpkgs.gcc nixpkgs.unzip
    else
        echo "[ERROR]: Unsupported package manager" >&2
        exit 1
    fi

    echo "[INFO] Finished installing baseline tools"

    return 0
}

function install_via_sys_pkg_mgr() {
    local dep="$1" version="${2:-latest}"
    local pkg deb_name deb_path

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        if command -v apt-get &>/dev/null; then
            deb_name="${LOCAL_DEB_RESOURCE[$dep]:-}"
            if [[ -n "$deb_name" ]]; then
                deb_path="$SCRIPT_DIR/../resources/$deb_name"
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
                echo "[NOTICE]: pacman does not support pinning arbitrary versions, installing latest instead" >&2
            }
            pkg="${PACMAN_PKG_NAME[$dep]:-}"
            [[ -n "$pkg" ]] || return 1
            sudo pacman -S --noconfirm --needed "$pkg" && return 0
            return 1
        elif command -v nix &>/dev/null; then
            [[ "$version" == "latest" ]] || {
                echo "[NOTICE]: nixpkgs does not support pinning arbitrary versions here, installing latest instead" >&2
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
            echo "[NOTICE]: nixpkgs does not support pinning arbitrary versions here, installing latest instead" >&2
        }
        pkg="${APT_PKG_NAME[$dep]:-}"
        [[ -n "$pkg" ]] || return 1
        nix profile install "nixpkgs#$pkg" && return 0
        return 1
    fi

    return 1
}

function install_via_flatpak() {
    local dep="$1" cmd_name="$2" version="${3:-latest}"
    local app_id scope_flag export_dir target_dir install_ref

    app_id="${FLATPAK_APP_ID[$dep]:-}"
    [[ -n "$app_id" ]] || return 1
    command -v flatpak &>/dev/null || return 1

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        scope_flag="--system"
    else
        scope_flag="--user"
    fi

    install_ref="$app_id"
    [[ "$version" == "latest" ]] || install_ref="$app_id//$version"

    flatpak install --noninteractive --assumeyes "$scope_flag" flathub "$install_ref" || return 1

    export_dir="$(flatpak_export_bin_dir)"
    target_dir="$(resolved_bin_dir)"
    mkdir -p "$target_dir"
    ln -sf "$export_dir/$app_id" "$target_dir/$cmd_name"

    return 0
}

function install_via_bin_pkgmgr() {
    local dep="$1" cmd_name="$2" version="${3:-latest}"
    local repo install_ref pkg_target_dir link_dir

    repo="${BIN_GH_REPO[$dep]:-}"
    [[ -n "$repo" ]] || return 1
    command -v bin &>/dev/null || return 1

    install_ref="$repo"
    [[ "$version" == "latest" ]] || install_ref="$repo@$version"

    pkg_target_dir="$(bin_pkgmgr_target_dir)"
    link_dir="$(resolved_bin_dir)"

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        sudo mkdir -p "$pkg_target_dir" "$link_dir"
        sudo bin config set target "$pkg_target_dir" || return 1
        sudo bin install "$install_ref" || return 1
    else
        mkdir -p "$pkg_target_dir" "$link_dir"
        bin config set target "$pkg_target_dir" || return 1
        bin install "$install_ref" || return 1
    fi

    ln -sf "$pkg_target_dir/$cmd_name" "$link_dir/$cmd_name"

    return 0
}

function prompt_version() {
    local dep="$1" version=""

    # non-interactive sessions (CI/headless) always get the latest version
    if [[ ! -t 0 ]]; then
        echo "latest"
        return 0
    fi

    read -r -p "[PROMPT] Version to install for '$dep' (leave blank for latest): " version >&2
    echo "${version:-latest}"

    return 0
}

function install_editor_dep() {
    local dep="$1" cmd_name="${2:-$1}"
    local backend version

    version="$(prompt_version "$dep")"

    for backend in "${BACKEND_ORDER[@]}"; do
        case "$backend" in
        sys_pkg_mgr)
            install_via_sys_pkg_mgr "$dep" "$version" && {
                echo "[INFO] Installed '$dep' ($version) via system package manager"
                return 0
            }
            ;;
        flatpak)
            install_via_flatpak "$dep" "$cmd_name" "$version" && {
                echo "[INFO] Installed '$dep' ($version) via flatpak"
                return 0
            }
            ;;
        bin_pkgmgr)
            install_via_bin_pkgmgr "$dep" "$cmd_name" "$version" && {
                echo "[INFO] Installed '$dep' ($version) via bin package manager"
                return 0
            }
            ;;
        esac
        echo "[WARN] backend '$backend' could not provide '$dep', trying next backend" >&2
    done

    echo "[ERROR]: Failed to install '$dep' via any available backend" >&2
    exit 1
}

function install_deps() {
    echo "[INFO] Installing app dependencies (install mode: $RESOLVED_INSTALL_MODE)"

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        install_baseline_tools
    else
        echo "[NOTICE]: skipping baseline tool install (git/curl/build tools) in user scope; ensure they are already present"
    fi

    app_selected vim && install_editor_dep vim

    if app_selected nvim || app_selected nvimgit; then
        install_editor_dep nvim
        install_editor_dep tree-sitter-cli
    fi

    app_selected nvimpager && install_editor_dep nvimpager
    app_selected vimpager && install_editor_dep vimpager

    echo "[INFO] Finished installing app dependencies"

    return 0
}

function configure_app_files() {
    local target_home="$1" as_root="${2:-0}"
    local -a cp_cmd mkdir_cmd rm_cmd

    if (( as_root == 1 )); then
        cp_cmd=(sudo cp)
        mkdir_cmd=(sudo mkdir)
        rm_cmd=(sudo rm)
    else
        cp_cmd=(cp)
        mkdir_cmd=(mkdir)
        rm_cmd=(rm)
    fi

    if app_selected nvim; then
        "${mkdir_cmd[@]}" -p "$target_home/.config/nvim"
        "${cp_cmd[@]}" -af "$SCRIPT_DIR"/nvim/. "$target_home/.config/nvim/"
    fi

    if app_selected nvimgit; then
        "${mkdir_cmd[@]}" -p "$target_home/.config/nvimgit"
        "${cp_cmd[@]}" -af "$SCRIPT_DIR"/nvimgit/. "$target_home/.config/nvimgit/"
    fi

    if app_selected nvimpager; then
        "${mkdir_cmd[@]}" -p "$target_home/.config/nvimpager"
        "${cp_cmd[@]}" -af "$SCRIPT_DIR"/nvimpager/. "$target_home/.config/nvimpager/"
    fi

    if app_selected vim; then
        "${cp_cmd[@]}" -f "$SCRIPT_DIR"/vim/vimrc.vim "$target_home/.vimrc"
    fi

    if app_selected vimpager; then
        "${cp_cmd[@]}" -f "$SCRIPT_DIR"/vimpager/vimpagerrc "$target_home/.vimpagerrc"
    fi

    return 0
}

function clean_app_files() {
    local target_home="$1" as_root="${2:-0}"
    local -a rm_cmd

    if (( as_root == 1 )); then
        rm_cmd=(sudo rm)
    else
        rm_cmd=(rm)
    fi

    app_selected nvim && "${rm_cmd[@]}" -rf "$target_home/.config/nvim" "$target_home/.local/share/nvim" "$target_home/.local/state/nvim" "$target_home/.cache/nvim"
    app_selected nvimgit && "${rm_cmd[@]}" -rf "$target_home/.config/nvimgit" "$target_home/.local/share/nvimgit" "$target_home/.local/state/nvimgit" "$target_home/.cache/nvimgit"
    app_selected nvimpager && "${rm_cmd[@]}" -rf "$target_home/.config/nvimpager" "$target_home/.local/share/nvimpager" "$target_home/.local/state/nvimpager" "$target_home/.cache/nvimpager"
    app_selected vim && "${rm_cmd[@]}" -rf "$target_home/.vim" "$target_home/.vimrc" "$target_home/.viminfo"
    app_selected vimpager && "${rm_cmd[@]}" -f "$target_home/.vimpagerrc"

    return 0
}

function configure_apps_local() {
    echo "[INFO] Configuring apps for user $USER (local scope)"

    (( CLEAN_INSTALL == 1 )) && clean_app_files "$HOME"
    configure_app_files "$HOME"

    echo "[INFO] Finished configuring apps"

    return 0
}

function configure_apps_users() {
    echo "[INFO] Installing default editor configurations to /etc/skel"

    sudo mkdir -p /etc/skel
    (( CLEAN_INSTALL == 1 )) && clean_app_files /etc/skel 1
    configure_app_files /etc/skel 1

    if (( CLEAN_INSTALL == 1 )); then
        local home_dir
        for home_dir in /home/*/; do
            home_dir="${home_dir%/}"
            [[ -d "$home_dir" ]] || continue
            echo "[INFO] Refreshing configs for $home_dir"
            clean_app_files "$home_dir" 1
            configure_app_files "$home_dir" 1
            sudo chown -R --reference="$home_dir" "$home_dir"
        done
    fi

    echo "[INFO] Finished installing default configurations"

    return 0
}

function configure_apps_global() {
    echo "[INFO] Installing global default editor configurations"

    if app_selected vim; then
        sudo mkdir -p /etc/vim
        sudo cp -f "$SCRIPT_DIR"/vim/vimrc.vim /etc/vim/vimrc.local
    fi

    if app_selected nvim; then
        sudo mkdir -p /usr/share/nvim
        sudo cp -f "$SCRIPT_DIR"/nvim/init.lua /usr/share/nvim/sysinit.lua
    fi

    if app_selected vimpager; then
        sudo cp -f "$SCRIPT_DIR"/vimpager/vimpagerrc /etc/vimpagerrc
    fi

    if app_selected nvimgit; then
        echo "[NOTICE]: 'nvimgit' has no documented system-wide global config path; falling back to '/etc/skel'"
        sudo mkdir -p /etc/skel/.config/nvimgit
        sudo cp -af "$SCRIPT_DIR"/nvimgit/. /etc/skel/.config/nvimgit/
    fi

    if app_selected nvimpager; then
        echo "[NOTICE]: 'nvimpager' has no documented system-wide global config path; falling back to '/etc/skel'"
        sudo mkdir -p /etc/skel/.config/nvimpager
        sudo cp -af "$SCRIPT_DIR"/nvimpager/. /etc/skel/.config/nvimpager/
    fi

    echo "[INFO] Finished installing global configurations"

    return 0
}

function configure_apps() {
    if [[ "$RESOLVED_CONFIG_MODE" != "local" ]] && (( EUID != 0 )); then
        echo "[ERROR]: '-cm ${RESOLVED_CONFIG_MODE}' requires running as root (EUID=0)" >&2
        exit 1
    fi

    case "$RESOLVED_CONFIG_MODE" in
    global)
        configure_apps_global
        ;;
    users)
        configure_apps_users
        ;;
    local)
        configure_apps_local
        ;;
    esac

    return 0
}

# TODO: investigate lazy loading in native plugin manager
#       https://fredrikaverpil.github.io/blog/2026/04/15/from-lazy.nvim-to-vim.pack/
function install_plugs() {
    local -a vim_cmds
    local -a nvim_cmds
    local nvim_app

    if (( CLEAN_INSTALL == 1 )); then
        vim_cmds=('+PlugInstall! --sync' '+w! /dev/stdout' +qa)
        nvim_cmds=('+Lazy! install' +qa)
    else
        vim_cmds=('+PlugUpdate! --sync' '+w! /dev/stdout' +qa)
        nvim_cmds=('+Lazy! sync' +qa)
    fi

    if app_selected vim; then
        echo "[INFO] Installing Vim editor plugins"
        vim --not-a-term -i NONE -u ~/.vimrc -es "${vim_cmds[@]}" || true
        vim --not-a-term -i NONE -u ~/.vimrc -es +PlugStatus '+w! /dev/stdout' +qa || {
            echo "[ERROR]: Failed installing Vim plugins" >&2
            exit 1
        }
        echo "[INFO] Finished installing Vim plugins"
    fi

    echo "[INFO] Installing Neovim editor plugins"
    for nvim_app in nvim nvimgit; do
        if app_selected "$nvim_app"; then
            echo "[DEBUG] Installing '$nvim_app' LazyVim plugins"
            NVIM_APPNAME="$nvim_app" nvim --headless "${nvim_cmds[@]}"
        fi
    done
    echo "[INFO] Finished installing Neovim plugins"

    return 0
}


echo "[INFO] Starting xvim installation"
setup_install "$@"
(( SKIP_PACKAGES != 1 )) && install_deps

if (( SKIP_CONFIGS != 1 )); then
    configure_apps

    if [[ "$RESOLVED_CONFIG_MODE" == "local" ]]; then
        install_plugs
    else
        echo "[NOTICE] Skipping plugin sync for config mode '$RESOLVED_CONFIG_MODE': plugins must be installed/updated per-user by running '$0 -cm local' as that user"
    fi
else
    echo "[NOTICE] Skipping plugin sync because configs were skipped ('-sc')"
fi

echo "[INFO] Completed xvim installation"

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

exit 0
