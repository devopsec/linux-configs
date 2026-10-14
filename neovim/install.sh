#!/usr/bin/env bash

# neovim family installer: nvim, nvimgit and nvimpager (and the treesitter CLI they need).
# sources the shared library for backends/flags/orchestration; can also run standalone
# as 'neovim/install.sh [-cc] [-cp] [-sp] [-sc] [-im MODE] [-cm MODE] [nvim nvimgit nvimpager]'

NEOVIM_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
source "$NEOVIM_INSTALL_DIR/../installer-libs/common.sh"

ALL_APPS+=(nvim nvimgit nvimpager)
FAMILY_APPS[neovim]="nvim nvimgit nvimpager"

APT_PKG_NAME[nvim]="neovim"
APT_PKG_NAME[nvimpager]="nvimpager"
APT_PKG_NAME[treesitter]="tree-sitter-cli"
PACMAN_PKG_NAME[nvim]="neovim"
PACMAN_PKG_NAME[nvimpager]="nvimpager"
PACMAN_PKG_NAME[treesitter]="tree-sitter-cli"
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
    if app_selected nvim || app_selected nvimgit; then
        uninstall_dep nvim
        uninstall_dep treesitter tree-sitter
    fi
    app_selected nvimpager && uninstall_dep nvimpager

    return 0
}

function neovim_install_deps() {
    if app_selected nvim || app_selected nvimgit; then
        install_editor_dep nvim
        install_editor_dep treesitter tree-sitter
    fi

    if app_selected nvimpager; then
        install_editor_dep nvimpager
    fi

    return 0
}

# copies the neovim configs (and links nvimpager onto PATH) into the target home; as_root=1 uses sudo
function neovim_configure_home() {
    local target_home="$1" as_root="${2:-0}"
    local -a cp_cmd mkdir_cmd ln_cmd

    if (( as_root == 1 )); then
        cp_cmd=(sudo cp)
        mkdir_cmd=(sudo mkdir)
        ln_cmd=(sudo ln)
    else
        cp_cmd=(cp)
        mkdir_cmd=(mkdir)
        ln_cmd=(ln)
    fi

    if app_selected nvim; then
        "${mkdir_cmd[@]}" -p "$target_home/.config/nvim"
        "${cp_cmd[@]}" -af "$NEOVIM_INSTALL_DIR"/nvim/. "$target_home/.config/nvim/"
    fi

    if app_selected nvimgit; then
        "${mkdir_cmd[@]}" -p "$target_home/.config/nvimgit"
        "${cp_cmd[@]}" -af "$NEOVIM_INSTALL_DIR"/nvimgit/. "$target_home/.config/nvimgit/"
    fi

    if app_selected nvimpager; then
        "${mkdir_cmd[@]}" -p "$target_home/.config/nvimpager"
        "${cp_cmd[@]}" -af "$NEOVIM_INSTALL_DIR"/nvimpager/. "$target_home/.config/nvimpager/"
    fi

    # symlink the vendored pager from the .deb onto PATH (resolved_bin_dir() always precedes
    # '/usr/bin'); it resolves 'nvim' from PATH, so no wrapper or dedicated editor is needed
    if app_selected nvimpager && ! is_installed_via_flatpak nvimpager; then
        # depends on the install mode (not the config mode): system installs write to a root-owned bin dir
        local -a bin_sudo=()
        [[ "$RESOLVED_INSTALL_MODE" == "system" && $EUID -ne 0 ]] && bin_sudo=(sudo)
        "${bin_sudo[@]}" mkdir -p "$(resolved_bin_dir)"
        "${bin_sudo[@]}" ln -sfn /usr/bin/nvimpager "$(resolved_bin_dir)/nvimpager"
    fi

    return 0
}

function neovim_clean_home() {
    local target_home="$1" as_root="${2:-0}"
    local -a rm_cmd mkdir_cmd
    local app

    if (( as_root == 1 )); then
        rm_cmd=(sudo rm)
        mkdir_cmd=(sudo mkdir)
    else
        rm_cmd=(rm)
        mkdir_cmd=(mkdir)
    fi

    app_selected nvim && "${rm_cmd[@]}" -rf "$target_home/.config/nvim" "$target_home/.local/share/nvim" "$target_home/.local/state/nvim" "$target_home/.cache/nvim"
    app_selected nvimgit && "${rm_cmd[@]}" -rf "$target_home/.config/nvimgit" "$target_home/.local/share/nvimgit" "$target_home/.local/state/nvimgit" "$target_home/.cache/nvimgit"
    app_selected nvimpager && "${rm_cmd[@]}" -rf "$target_home/.config/nvimpager" "$target_home/.local/share/nvimpager" "$target_home/.local/state/nvimpager" "$target_home/.cache/nvimpager"

    # flatpak sandboxes symlink their state dirs to these host paths (see configure_flatpak_app),
    # so the removed dirs are recreated empty; otherwise the links dangle and mkdir fails with EEXIST
    for app in nvim nvimgit nvimpager; do
        app_selected "$app" && "${mkdir_cmd[@]}" -p "$target_home/.local/share/$app" "$target_home/.local/state/$app" "$target_home/.cache/$app"
    done

    return 0
}

function neovim_configure_global() {
    if app_selected nvim; then
        sudo mkdir -p /usr/share/nvim
        sudo cp -f "$NEOVIM_INSTALL_DIR"/nvim/init.lua /usr/share/nvim/sysinit.lua
    fi

    if app_selected nvimgit; then
        echo "$(tag NOTICE): 'nvimgit' has no documented system-wide global config path; falling back to '/etc/skel'"
        sudo mkdir -p /etc/skel/.config/nvimgit
        sudo cp -af "$NEOVIM_INSTALL_DIR"/nvimgit/. /etc/skel/.config/nvimgit/
    fi

    if app_selected nvimpager; then
        echo "$(tag NOTICE): 'nvimpager' has no documented system-wide global config path; falling back to '/etc/skel'"
        sudo mkdir -p /etc/skel/.config/nvimpager
        sudo cp -af "$NEOVIM_INSTALL_DIR"/nvimpager/. /etc/skel/.config/nvimpager/
    fi

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

    return 0
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
    setup_install "$@"
    run_install neovim
fi
