#!/usr/bin/env bash


function usage() {
cat <<EOF
Summary:
    Installer for Vim-like Text Editors (xvim)
Usage:
    $0 [-h] [-ci] [-sd]
Options:
    -h      help                - show this usage documentation
    -ci     clean install       - clear cache/state before install and overwrite configs
    -sd     skip dependencies   - skip installing package dependencies
Notes:
    +   The installer should be run as the target user apps will be configured for
    +   Installing package dependencies requires target user to have sudo privileges
    +   The following package managers are supported by the installer:
            apt-get  ->  debian-based distros
            pacman   ->  arch-based distros
EOF
}


set -euo pipefail
shopt -s inherit_errexit nullglob

declare -g  SCRIPT_DIR
declare -gi CLEAN_INSTALL=0
declare -gi SKIP_DEPS=0


function setup_install() {
    while (( $# > 0 )); do
        case "$1" in
            -h)
                usage
                exit 0
                ;;
            -ci)
                CLEAN_INSTALL=1
                shift
                ;;
            -sd)
                SKIP_DEPS=1
                shift
                ;;
            *)
                echo "[ERROR]: Invalid argument '$1'" >&2
                echo "" >&2
                usage >&2
                exit 1
                ;;
        esac
    done

    SCRIPT_DIR="$(realpath -m "${BASH_SOURCE[0]}/../")"

    return 0
}

function install_deps() {
    local fd_cmd

    echo "[INFO] Installing app dependencies via system package manager"

    if command -v apt-get &>/dev/null; then
        sudo apt-get update -y
        sudo apt-get install -y \
            neovim vim git curl build-essential ripgrep fd-find unzip
    elif command -v pacman &>/dev/null; then
        sudo pacman -Syu --noconfirm --needed \
            neovim vim git curl base-devel ripgrep fd unzip
    else
        echo "[ERROR]: Unsupported package manager" >&2
        exit 1
    fi

    if fd_cmd=$(command -v fd 2>/dev/null); then
        return 0
    else
        fd_cmd=$(command -v fdfind 2>/dev/null) || {
            echo "[ERROR]: Failed normalizing 'fd' command" >&2
            exit 1
        }
    fi

    echo "[NOTICE]: normalizing command paths:"
    echo "          $fd_cmd -> /usr/local/bin/fd"
    sudo ln -sf "$fd_cmd" /usr/local/bin/fd

    echo "[INFO] Finished installing app dependencies"

    return 0
}

function configure_apps() {
    echo "[INFO] Configuring apps for user $USER"

    if (( CLEAN_INSTALL == 1 )); then
        rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
        rm -rf ~/.config/nvimgit ~/.local/share/nvimgit ~/.local/state/nvimgit ~/.cache/nvimgit
        rm -rf ~/.config/nvimpager ~/.local/share/nvimpager ~/.local/state/nvimpager ~/.cache/nvimpager
        rm -rf ~/.vim ~/.vimrc ~/.viminfo
    fi

    mkdir -p ~/.config/nvim
    mkdir -p ~/.config/nvimgit
    mkdir -p ~/.config/nvimpager

    cp -af "$SCRIPT_DIR"/nvim/. ~/.config/nvim/
    cp -af "$SCRIPT_DIR"/nvimgit/. ~/.config/nvimgit/
    cp -af "$SCRIPT_DIR"/nvimpager/. ~/.config/nvimpager/
    cp -f "$SCRIPT_DIR"/vim/vimrc.vim ~/.vimrc

    echo "[INFO] Finished configuring apps"

    return 0
}

# TODO: investigate lazy loading in native plugin manager
#       https://fredrikaverpil.github.io/blog/2026/04/15/from-lazy.nvim-to-vim.pack/
function install_plugs() {
    local -a vim_cmds
    local -a nvim_cmds

    if (( CLEAN_INSTALL == 1 )); then
        vim_cmds=('+PlugInstall! --sync' '+w! /dev/stdout' +qa)
        nvim_cmds=('+Lazy! install' +qa)
    else
        vim_cmds=('+PlugUpdate! --sync' '+w! /dev/stdout' +qa)
        nvim_cmds=('+Lazy! sync' +qa)
    fi

    echo "[INFO] Installing Vim editor plugins"
    vim --not-a-term -i NONE -u ~/.vimrc -es "${vim_cmds[@]}" || true
    vim --not-a-term -i NONE -u ~/.vimrc -es +PlugStatus '+w! /dev/stdout' +qa || {
        echo "[ERROR]: Failed installing Vim plugins" >&2
        exit 1
    }
    echo "[INFO] Finished installing Vim plugins"

    echo "[INFO] Installing Neovim editor plugins"
    for nvim_app in nvim nvimgit; do
        echo "[DEBUG] Installing '$nvim_app' LazyVim plugins"
        NVIM_APPNAME="$nvim_app" nvim --headless "${nvim_cmds[@]}"
    done
    echo "[INFO] Finished installing Neovim plugins"

    return 0
}


echo "[INFO] Starting xvim installation"
setup_install "$@"
(( SKIP_DEPS != 1 )) && install_deps
configure_apps
install_plugs
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
