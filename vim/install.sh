#!/usr/bin/env bash

# vim family installer: vim and vimpager. sources the shared library for
# backends/flags/orchestration; can also run standalone as
# 'vim/install.sh [-cc] [-cp] [-sp] [-sc] [-im MODE] [-cm MODE] [vim vimpager]'

VIM_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
source "$VIM_INSTALL_DIR/../installer-libs/common.sh"

ALL_APPS+=(vim vimpager)
FAMILY_APPS[vim]="vim vimpager"

APT_PKG_NAME[vim]="vim"
APT_PKG_NAME[vimpager]="vimpager"
PACMAN_PKG_NAME[vim]="vim"
PACMAN_PKG_NAME[vimpager]="vimpager"
FLATPAK_APP_ID[vim]="org.vim.Vim"
# both sandboxed editors are also used as pagers (vimpager/nvimpager) invoked by
# arbitrary host tools -- e.g. 'man' chdir()s to '/' before exec'ing the pager -- so
# they need the real host filesystem ('host'). '/tmp' is listed explicitly because
# flatpak gives every sandbox its own private /tmp, which man-db and vimpager use
FLATPAK_FS_OVERRIDES[vim]="host /tmp"
LOCAL_DEB_RESOURCE[vimpager]="vimpager_2.06-2_all.deb"
LOCAL_FLATPAK_RESOURCE[vimpager]="io.github.rkitover.vimpager.flatpak"
FLATPAK_BASE_APP_ID[vimpager]="org.vim.Vim"
FLATPAK_APP_ID[vimpager]="io.github.rkitover.vimpager"
FLATPAK_FS_OVERRIDES[vimpager]="!host home /tmp /mnt /media"
FLATPAK_RUN_FLAGS[vimpager]="--no-session-bus --no-a11y-bus"

function vim_clean_packages() {
    app_selected vim && uninstall_dep vim
    app_selected vimpager && uninstall_dep vimpager

    return 0
}

function vim_install_deps() {
    if app_selected vim; then
        install_editor_dep vim
    fi

    if app_selected vimpager; then
        install_editor_dep vimpager
    fi

    return 0
}

# copies the vim configs (and links vimpager onto PATH) into the target home; as_root=1 uses sudo
function vim_configure_home() {
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

    if app_selected vim; then
        "${cp_cmd[@]}" -f "$VIM_INSTALL_DIR"/vim/vimrc.vim "$target_home/.vimrc"
    fi

    if app_selected vimpager; then
        "${cp_cmd[@]}" -f "$VIM_INSTALL_DIR"/vimpager/vimpagerrc "$target_home/.vimpagerrc"
    fi

    # symlink the vendored pager from the .deb onto PATH (resolved_bin_dir() always precedes
    # '/usr/bin'); it resolves 'vim' from PATH, so no wrapper or dedicated editor is needed
    if app_selected vimpager && ! is_installed_via_flatpak vimpager; then
        # depends on the install mode (not the config mode): system installs write to a root-owned bin dir
        local -a bin_sudo=()
        [[ "$RESOLVED_INSTALL_MODE" == "system" && $EUID -ne 0 ]] && bin_sudo=(sudo)
        "${bin_sudo[@]}" mkdir -p "$(resolved_bin_dir)"
        "${bin_sudo[@]}" ln -sfn /usr/bin/vimpager "$(resolved_bin_dir)/vimpager"
    fi

    return 0
}

function vim_clean_home() {
    local target_home="$1" as_root="${2:-0}"
    local -a rm_cmd

    if (( as_root == 1 )); then
        rm_cmd=(sudo rm)
    else
        rm_cmd=(rm)
    fi

    app_selected vim && "${rm_cmd[@]}" -rf "$target_home/.vim" "$target_home/.vimrc" "$target_home/.viminfo"
    app_selected vimpager && "${rm_cmd[@]}" -f "$target_home/.vimpagerrc"

    return 0
}

function vim_configure_global() {
    if app_selected vim; then
        sudo mkdir -p /etc/vim
        sudo cp -f "$VIM_INSTALL_DIR"/vim/vimrc.vim /etc/vim/vimrc.local
    fi

    if app_selected vimpager; then
        sudo cp -f "$VIM_INSTALL_DIR"/vimpager/vimpagerrc /etc/vimpagerrc
    fi

    return 0
}

function vim_install_plugins() {
    local -a vim_cmds

    if (( CLEAN_CONFIGS == 1 )); then
        vim_cmds=('+PlugInstall! --sync' '+w! /dev/stdout' +qa)
    else
        vim_cmds=('+PlugUpdate! --sync' '+w! /dev/stdout' +qa)
    fi

    if app_selected vim; then
        echo "$(tag INFO) Installing Vim editor plugins"
        vim --not-a-term -i NONE -u ~/.vimrc -es "${vim_cmds[@]}" || true
        vim --not-a-term -i NONE -u ~/.vimrc -es +PlugStatus '+w! /dev/stdout' +qa || {
            echo "$(tag ERROR): Failed installing Vim plugins" >&2
            exit 1
        }
        echo "$(tag INFO) Finished installing Vim plugins"
    fi

    return 0
}

# standalone entrypoint: only runs when invoked directly, not when sourced by the root installer
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    setup_install "$@"
    run_install vim
fi
