#!/usr/bin/env bash

# shell family installer: the login chain (~/.profile, the XDG directories it reads from
# ~/.config/environment.d/60-xdg-dirs.conf, ~/.zprofile) and the bash, ksh and zsh rc files.
# The repo copies in home/ have no leading dot; the profile is checked by tests/check-profile.sh
# before any file is written. Each file is written in place, so an existing one keeps its mode,
# owner and inode, after a backup to ~/.var/backups/shell/<timestamp>/<same path>; identical
# files are left alone.
# User scope only: '-cm global' and '-cm users' (/etc/skel and every /home) are skipped, and
# -cc never removes a login file. sources the shared library for flags/orchestration; can also
# run standalone as 'shell/install.sh [-cc] [-sc] [-sp] [shell]'

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -Eeuo pipefail
    shopt -s inherit_errexit nullglob
fi

SHELL_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
# shellcheck source=installer-libs/common.sh
source "$SHELL_INSTALL_DIR/../installer-libs/common.sh"

register_family shell shell

# <repo file under home/>:<path under the target home>, in install order: the profile reads
# the environment.d file, and the rc files are read by the profile and ~/.zprofile
SHELL_FILES=(
    config/environment.d/60-xdg-dirs.conf:.config/environment.d/60-xdg-dirs.conf
    profile:.profile
    bashrc:.bashrc
    kshrc:.kshrc
    zprofile:.zprofile
    zshrc:.zshrc
)
SHELL_ENV_D_FILE=.config/environment.d/60-xdg-dirs.conf
# one directory per run under the target home; each backup keeps its home-relative path
SHELL_BACKUP_REL=".var/backups/shell/$(date +%Y%m%d-%H%M%S)"
# home-relative paths written in this run, for the summary
declare -ga SHELL_CHANGED=()
declare -gi SHELL_CONFIGURED=0

# writes "$1" over "$2/$3" in place, so an existing file keeps its mode, owner and inode, after a
# backup to "$2/$SHELL_BACKUP_REL/$3"; new files and directories are created private (umask 077)
function shell_write_file() {
    local source_path="$1" destination="$2/$3" backup="$2/$SHELL_BACKUP_REL/$3"
    if [[ -e "$destination" ]]; then
        (umask 077 && mkdir -p -- "${backup%/*}")
        cp -p -- "$destination" "$backup"
        cat -- "$source_path" >"$destination"
    else
        (umask 077 && mkdir -p -- "${destination%/*}" && cat -- "$source_path" >"$destination")
    fi
}

function shell_configure_home() {
    local target_home="$1" as_root="${2:-0}" entry destination out
    if (( as_root != 0 )) || [[ "$target_home" != "$HOME" ]]; then
        log_notice "shell: skipping $target_home; login files are only installed for the current user ('-cm local')"
        return 0
    fi

    # every check runs before the first write, so a failure leaves all files as they were
    if ! out="$(bash "$SHELL_INSTALL_DIR/tests/check-profile.sh" 2>&1)"; then
        printf '%s\n' "$out" >&2
        log_error "shell: tests/check-profile.sh failed; no login file was changed"
        return 1
    fi
    for entry in "${SHELL_FILES[@]}"; do
        destination="$target_home/${entry#*:}"
        if [[ -L "$destination" || (-e "$destination" && ! -f "$destination") ]]; then
            log_error "shell: $destination is not a regular file; no login file was changed"
            return 1
        fi
    done

    for entry in "${SHELL_FILES[@]}"; do
        destination="$target_home/${entry#*:}"
        cmp -s -- "$SHELL_INSTALL_DIR/home/${entry%%:*}" "$destination" && continue
        shell_write_file "$SHELL_INSTALL_DIR/home/${entry%%:*}" "$target_home" "${entry#*:}"
        SHELL_CHANGED+=("${entry#*:}")
    done
    for entry in .bash_profile .bash_login; do
        [[ -e "$target_home/$entry" ]] && log_warn "shell: bash login shells read ~/$entry instead of ~/.profile"
    done
    SHELL_CONFIGURED=1
    return 0
}

# -cc: a missing ~/.profile or ~/.bashrc can lock a user out, so nothing is removed; the
# install that follows replaces each changed file after a backup
function shell_clean_home() {
    log_notice "shell: -cc does not remove login files; changed files are replaced after a backup"
    return 0
}

function shell_configure_global() {
    log_notice "shell: no global configuration; login files are only installed with '-cm local'"
    return 0
}

function shell_post_install() {
    local file backed_up=0
    log_info "Shell summary:"
    if (( SHELL_CONFIGURED == 0 )); then
        echo "  - no login file was installed (needs '-cm local' without '-sc')"
        return 0
    fi
    if (( ${#SHELL_CHANGED[@]} == 0 )); then
        echo "  - login files already up to date"
        return 0
    fi
    for file in "${SHELL_CHANGED[@]}"; do
        if [[ -e "$HOME/$SHELL_BACKUP_REL/$file" ]]; then
            echo "  - ~/$file (previous version: ~/$SHELL_BACKUP_REL/$file)"
            backed_up=1
        else
            echo "  - ~/$file (new)"
        fi
    done
    echo "  New shells read them."
    if (( backed_up == 1 )); then
        echo "  Undo one with: cp -p ~/$SHELL_BACKUP_REL/<file> ~/<file>"
    fi
    for file in "${SHELL_CHANGED[@]}"; do
        if [[ "$file" == "$SHELL_ENV_D_FILE" ]]; then
            echo "  The desktop reads ~/$SHELL_ENV_D_FILE only at login: log out completely or reboot."
        fi
    done
    return 0
}

# standalone entrypoint: only runs when invoked directly, not when sourced by the root installer
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    setup_install "$@" || exit $?
    run_install shell
fi
