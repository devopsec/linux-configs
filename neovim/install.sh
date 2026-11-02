#!/usr/bin/env bash

# neovim family installer: nvim, nvimgit and nvimpager (and the treesitter CLI they need).
# fonts (the Nerd Font they expect) come from the separate 'fonts' family.
# sources the shared library for backends/flags/orchestration; can also run standalone
# as 'neovim/install.sh [-cc] [-cp] [-sp] [-sc] [-im MODE] [-cm MODE] [nvim nvimgit nvimpager]'

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -Eeuo pipefail
    shopt -s inherit_errexit nullglob
fi

NEOVIM_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
# shellcheck source=installer-libs/common.sh
source "$NEOVIM_INSTALL_DIR/../installer-libs/common.sh"

register_family neovim nvim nvimgit nvimpager
declare -ga NEOVIM_APPS=(nvim nvimgit nvimpager)
pkg_define nvim apt=neovim pacman=neovim nix=neovim
pkg_define nvimpager apt=nvimpager pacman=nvimpager nix=nvimpager
pkg_define treesitter apt=tree-sitter-cli pacman=tree-sitter-cli nix=tree-sitter
family_requires neovim git curl unzip build-tools man-db bash-completion

DOCS_NAMES[nvim]="nvim"
DOCS_MAN_URL[nvim]="https://raw.githubusercontent.com/neovim/neovim/v0.11.6/src/man/nvim.1"
DOCS_NAMES[treesitter]="tree-sitter"
DOCS_COMPLETION_CMD[treesitter]="tree-sitter complete --shell {shell}"
DOCS_NAMES[nvimpager]="nvimpager"

FLATPAK_APP_ID[nvim]="io.neovim.nvim"
FLATPAK_FS_OVERRIDES[nvim]="host /tmp"
FLATPAK_XDG_APPNAMES[nvim]="nvim nvimgit nvimpager"
FLATPAK_PATH_EXPOSE[nvim]=1
BIN_GH_REPO[nvim]="neovim/neovim"
BIN_ASSET_GLOB[nvim]="nvim-linux-x86_64.appimage"
BIN_GH_REPO[treesitter]="tree-sitter/tree-sitter"
BIN_ASSET_GLOB[treesitter]="tree-sitter-linux-x64.gz"
LOCAL_DEB_RESOURCE[nvimpager]="nvimpager_0.14.0-1_all.deb"
LOCAL_FLATPAK_RESOURCE[nvimpager]="io.github.lucc.nvimpager.flatpak"
FLATPAK_BASE_APP_ID[nvimpager]="io.neovim.nvim"
FLATPAK_APP_ID[nvimpager]="io.github.lucc.nvimpager"
FLATPAK_FS_OVERRIDES[nvimpager]="!host home /tmp /mnt /media"
FLATPAK_RUN_FLAGS[nvimpager]="--no-session-bus --no-a11y-bus"
FLATPAK_XDG_APPNAMES[nvimpager]="nvimpager"

function neovim_clean_packages() {
    local app
    for app in nvim nvimgit; do
        if app_selected "$app"; then
            app_pkg_uninstall nvim
            app_pkg_uninstall treesitter tree-sitter
            break
        fi
    done
    app_selected nvimpager && app_pkg_uninstall nvimpager
    return 0
}

function neovim_install_deps() {
    local app
    for app in nvim nvimgit; do
        if app_selected "$app"; then
            app_pkg_install nvim
            app_pkg_install treesitter tree-sitter
            break
        fi
    done
    app_selected nvimpager && app_pkg_install nvimpager
    return 0
}

# copies the neovim configs (and links nvimpager onto PATH) into the target home; as_root=1 uses sudo
function neovim_configure_home() {
    local target_home="$1" as_root="${2:-0}"
    local app link_as_root=0

    for app in "${NEOVIM_APPS[@]}"; do
        if app_selected "$app"; then
            install_tree "$as_root" "$NEOVIM_INSTALL_DIR/$app/." "$target_home/.config/$app" -af
        fi
    done

    [[ "$RESOLVED_INSTALL_MODE" == system && $EUID != 0 ]] && link_as_root=1
    if app_selected nvimpager && ! app_pkg_via_flatpak nvimpager; then
        link_path "$link_as_root" /usr/bin/nvimpager "$(scoped_bin_dir)/nvimpager"
    fi
    return 0
}

function neovim_clean_home() {
    local target_home="$1" as_root="${2:-0}"
    local app

    for app in "${NEOVIM_APPS[@]}"; do
        if app_selected "$app"; then
            remove_paths "$as_root" "$target_home/.config/$app" "$target_home/.local/share/$app" \
                "$target_home/.local/state/$app" "$target_home/.cache/$app"
            run_as "$as_root" mkdir -p "$target_home/.local/share/$app" "$target_home/.local/state/$app" "$target_home/.cache/$app"
        fi
    done
    return 0
}

function neovim_configure_global() {
    if app_selected nvim; then
        install_file 1 "$NEOVIM_INSTALL_DIR/nvim/init.lua" /usr/share/nvim/sysinit.lua -f
    fi

    if app_selected nvimgit; then
        echo "$(tag NOTICE): 'nvimgit' has no documented system-wide global config path; falling back to '/etc/skel'"
        install_tree 1 "$NEOVIM_INSTALL_DIR/nvimgit/." /etc/skel/.config/nvimgit -af
    fi

    if app_selected nvimpager; then
        echo "$(tag NOTICE): 'nvimpager' has no documented system-wide global config path; falling back to '/etc/skel'"
        install_tree 1 "$NEOVIM_INSTALL_DIR/nvimpager/." /etc/skel/.config/nvimpager -af
    fi
    return 0
}

function neovim_clean_global() {
    if app_selected nvim; then remove_paths 1 /usr/share/nvim/sysinit.lua; fi
    if app_selected nvimgit; then remove_paths 1 /etc/skel/.config/nvimgit; fi
    if app_selected nvimpager; then remove_paths 1 /etc/skel/.config/nvimpager; fi
    return 0
}

# TODO: investigate lazy loading in native plugin manager as Lazy.nvim replacement
#       https://fredrikaverpil.github.io/blog/2026/04/15/from-lazy.nvim-to-vim.pack/
function neovim_install_plugins() {
    local -a nvim_cmds
    local nvim_app nvim_log

    if (( CLEAN_CONFIGS == 1 )); then
        nvim_cmds=('+Lazy! install' +qa)
    else
        nvim_cmds=('+Lazy! sync' +qa)
    fi

    echo "$(tag INFO) Installing Neovim editor plugins"
    # nvimpager is included here too: without a pre-install its lazy.nvim plugins
    # would otherwise bootstrap for the first time live, inside a 'man'/pager pipe,
    # which is fragile (slow clone over a non-interactive pipeline, no visible UI)
    for nvim_app in nvim nvimgit nvimpager; do
        if app_selected "$nvim_app"; then
            echo "$(tag DEBUG) Installing '$nvim_app' LazyVim plugins"
            nvim_log="$(mktemp /tmp/linux-configs-nvim.XXXXXX)"
            NVIM_APPNAME="$nvim_app" nvim --headless "${nvim_cmds[@]}" 2>&1 | tee "$nvim_log" || {
                echo "$(tag ERROR): '$nvim_app' plugin install exited non-zero" >&2
                exit 1
            }
            if grep -qE '^Error |Unmet requirements|E[0-9]+: ' "$nvim_log"; then
                echo "$(tag ERROR): '$nvim_app' reported errors during plugin install (log: $nvim_log)" >&2
                exit 1
            fi
            rm -f "$nvim_log"
        fi
    done
    echo "$(tag INFO) Finished installing Neovim plugins"

    neovim_update_treesitter_parsers

}

function neovim_post_install() {
    cat <<'EOF'
For editor and Git integration, consider setting EDITOR='nvim', VISUAL='nvim',
and configuring nvimpager as PAGER/MANPAGER. See the README for the Git settings.
EOF
}

# blocks until nvim-treesitter has (re)built its parsers: its own build hook runs async and
# the headless plugin install would otherwise quit before the parser compilation finishes
function neovim_update_treesitter_parsers() {
    local nvim_log

    app_selected nvim || return 0

    echo "$(tag INFO) Updating Treesitter parsers for 'nvim'"
    nvim_log="$(mktemp /tmp/linux-configs-nvim.XXXXXX)"
    NVIM_APPNAME=nvim nvim --headless \
        "+lua require('lazy').load({ plugins = { 'nvim-treesitter' } })" \
        "+lua local lc = require('lazy.core.config'); local o = require('lazy.core.plugin').values(lc.plugins['nvim-treesitter'], 'opts', false); local ti = require('nvim-treesitter.install'); assert(ti.install(o.ensure_installed or {}, { summary = true }):wait(900000)); assert(ti.update(nil, { summary = true }):wait(900000))" \
        +qa 2>&1 | tee "$nvim_log" || {
        echo "$(tag ERROR): 'nvim' Treesitter parser update exited non-zero" >&2
        exit 1
    }
    if grep -qE '^Error |E[0-9]+: ' "$nvim_log"; then
        echo "$(tag ERROR): 'nvim' reported errors during Treesitter parser update (log: $nvim_log)" >&2
        exit 1
    fi
    rm -f "$nvim_log"
    echo "$(tag INFO) Finished updating Treesitter parsers"

    return 0
}

# standalone entrypoint: only runs when invoked directly, not when sourced by the root installer
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    setup_install "$@" || exit $?
    run_install neovim
fi
