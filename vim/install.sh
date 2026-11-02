#!/usr/bin/env bash

# vim family installer: vim and vimpager. sources the shared library for
# backends/flags/orchestration; can also run standalone as
# 'vim/install.sh [-cc] [-cp] [-sp] [-sc] [-im MODE] [-cm MODE] [vim vimpager]'

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -Eeuo pipefail
    shopt -s inherit_errexit nullglob
fi

VIM_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
# shellcheck source=installer-libs/common.sh
source "$VIM_INSTALL_DIR/../installer-libs/common.sh"

register_family vim vim vimpager
pkg_define vim apt=vim pacman=vim nix=vim
pkg_define vimpager apt=vimpager pacman=vimpager nix=vimpager
family_requires vim git curl man-db bash-completion

DOCS_NAMES[vim]="vim vimdiff vimtutor xxd"
DOCS_NAMES[vimpager]="vimpager vimcat"

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
    app_selected vim && app_pkg_uninstall vim
    app_selected vimpager && app_pkg_uninstall vimpager
    return 0
}

function vim_install_deps() {
    app_selected vim && app_pkg_install vim
    app_selected vimpager && app_pkg_install vimpager
    return 0
}

# copies the vim configs (and links vimpager onto PATH) into the target home; as_root=1 uses sudo
function vim_configure_home() {
    local target_home="$1" as_root="${2:-0}"
    local link_as_root=0
    [[ "$RESOLVED_INSTALL_MODE" == system && $EUID != 0 ]] && link_as_root=1

    if app_selected vim; then
        install_file "$as_root" "$VIM_INSTALL_DIR/vim/vimrc.vim" "$target_home/.vimrc" -f
    fi

    if app_selected vimpager; then
        install_file "$as_root" "$VIM_INSTALL_DIR/vimpager/vimpagerrc" "$target_home/.vimpagerrc" -f
    fi

    # symlink the vendored pager from the .deb onto PATH (resolved_bin_dir() always precedes
    # '/usr/bin'); it resolves 'vim' from PATH, so no wrapper or dedicated editor is needed
    if app_selected vimpager && ! app_pkg_via_flatpak vimpager; then
        link_path "$link_as_root" /usr/bin/vimpager "$(scoped_bin_dir)/vimpager"
    fi
    return 0
}

function vim_clean_home() {
    local target_home="$1" as_root="${2:-0}"
    app_selected vim && remove_paths "$as_root" "$target_home/.vim" "$target_home/.vimrc" "$target_home/.viminfo"
    app_selected vimpager && remove_paths "$as_root" "$target_home/.vimpagerrc"
    return 0
}

function vim_configure_global() {
    if app_selected vim; then
        install_file 1 "$VIM_INSTALL_DIR/vim/vimrc.vim" /etc/vim/vimrc.local -f
    fi

    if app_selected vimpager; then
        install_file 1 "$VIM_INSTALL_DIR/vimpager/vimpagerrc" /etc/vimpagerrc -f
    fi
    return 0
}

function vim_clean_global() {
    if app_selected vim; then remove_paths 1 /etc/vim/vimrc.local; fi
    if app_selected vimpager; then remove_paths 1 /etc/vimpagerrc; fi
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

function vim_post_install() {
    app_selected vimpager && log_info "Set PAGER='vimpager' and MANPAGER='vimpager -p' if you want to use the Vim pager."
    return 0
}

# standalone entrypoint: only runs when invoked directly, not when sourced by the root installer
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    setup_install "$@" || exit $?
    run_install vim
fi
