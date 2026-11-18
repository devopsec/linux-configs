#!/usr/bin/env bash
#
# Offline test for the shell family installer: runs shell/install.sh with HOME set to a temporary
# directory (the real home is never read or written) and asserts install, the installed-profile
# checks, idempotency, in-place updates with backups, -cc, refusal on a symlink or a failing
# profile check, and that nothing calls sudo.
# The helper functions run through check "$@" and the EXIT trap:
# shellcheck disable=SC2329

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
FAMILY_DIR="$(dirname "$TESTS_DIR")"
REPO_DIR="$(dirname "$FAMILY_DIR")"
INSTALLER="$FAMILY_DIR/install.sh"
# <repo file under home/>:<path under HOME>, as in install.sh
FILES=(
    config/environment.d/60-xdg-dirs.conf:.config/environment.d/60-xdg-dirs.conf
    profile:.profile
    bashrc:.bashrc
    kshrc:.kshrc
    zprofile:.zprofile
    zshrc:.zshrc
)

declare -i OVERALL_RESULT=0
WORK=""
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
WORK="$(mktemp -d /tmp/linux-configs-shell-test.XXXXXX)"
export HOME="$WORK/home"
unset XDG_CONFIG_HOME

function check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        OVERALL_RESULT=1
    fi
}

# runs an installer (default: the repo's) in user/local scope; output goes to $WORK/out.log
function run_installer() {
    local installer="$INSTALLER"
    if [[ "${1-}" == --installer ]]; then
        installer="$2"
        shift 2
    fi
    PATH="$WORK/bin:$PATH" bash "$installer" -sp -im user -cm local "$@" </dev/null >"$WORK/out.log" 2>&1
}

function fails() {
    ! "$@"
}

function all_installed() {
    local entry
    for entry in "${FILES[@]}"; do
        cmp -s -- "$FAMILY_DIR/home/${entry%%:*}" "$HOME/${entry#*:}" || return 1
    done
}

function all_mode() {
    local entry
    for entry in "${FILES[@]}"; do
        [[ "$(stat -c %a -- "$HOME/${entry#*:}")" == "$1" ]] || return 1
    done
}

BACKUPS="$HOME/.var/backups/shell"

# counts the backed-up files (all of them are under $BACKUPS)
function backups() {
    find "$HOME/.var" -type f 2>/dev/null | wc -l
}

# no file other than the installed ones may appear in the home (e.g. a backup next to its file)
function only_installed_files() {
    local extra
    extra="$(find "$HOME" -path "$HOME/.var" -prune -o -type f -print | grep -cvE \
        '/(\.config/environment\.d/60-xdg-dirs\.conf|\.profile|\.bashrc|\.kshrc|\.zprofile|\.zshrc)$')" || true
    [[ "$extra" == 0 ]]
}

function inodes() {
    local entry
    for entry in "${FILES[@]}"; do stat -c %i -- "$HOME/${entry#*:}"; done
}

mkdir -p "$HOME" "$WORK/bin"
# any escalation fails the test
printf '#!/bin/sh\n: >"%s/sudo-called"\nexit 1\n' "$WORK" >"$WORK/bin/sudo"
chmod +x "$WORK/bin/sudo"

# fresh home
umask 022
check "install exits 0" run_installer
check "every file installed" all_installed
check "new files are private (600)" all_mode 600
check "no backups for new files" test "$(backups)" -eq 0
check "summary tells to log out for environment.d" grep -q 'log out completely' "$WORK/out.log"
check "installed profile passes check-profile.sh --installed" \
    bash "$TESTS_DIR/check-profile.sh" --installed

# idempotency
before="$(inodes)"
check "second run exits 0" run_installer
check "second run reports up to date" grep -q 'already up to date' "$WORK/out.log"
check "second run writes no backup" test "$(backups)" -eq 0
check "second run keeps inodes" test "$before" = "$(inodes)"

# changed files are updated in place after a backup, keeping their mode
printf 'old profile\n' >"$HOME/.profile"
chmod 640 "$HOME/.profile"
printf 'old bashrc\n' >"$HOME/.bashrc"
inode="$(stat -c %i -- "$HOME/.profile")"
check "update exits 0" run_installer
check "update installs every file" all_installed
check "update writes one backup per changed file" test "$(backups)" -eq 2
check "no backup is left next to the files" only_installed_files
profile_backup=("$BACKUPS"/*/.profile)
check "one backup directory per run" test "${#profile_backup[@]}" -eq 1
check "backup holds the old content" grep -qx 'old profile' "${profile_backup[0]}"
check "backup keeps the old mode" test "$(stat -c %a -- "${profile_backup[0]}")" = 640
check "backup directories are private (700)" test "$(stat -c %a -- "$HOME/.var" "$BACKUPS" "${profile_backup[0]%/*}" | sort -u)" = 700
check "update keeps the mode" test "$(stat -c %a -- "$HOME/.profile")" = 640
check "update keeps the inode" test "$(stat -c %i -- "$HOME/.profile")" = "$inode"
# the summary prints home paths with a literal ~
# shellcheck disable=SC2088
check "summary names the backup" grep -qF "~/.var/backups/shell/${profile_backup[0]#"$BACKUPS/"}" "$WORK/out.log"
rm -rf -- "$HOME/.var"

# -cc keeps the login files
check "-cc exits 0" run_installer -cc
check "-cc keeps every file" all_installed
check "-cc says nothing is removed" grep -q 'does not remove login files' "$WORK/out.log"

# a symlinked target stops the install before anything is written
printf 'old profile\n' >"$HOME/.profile"
ln -s /dev/null "$WORK/elsewhere"
mv -- "$HOME/.bashrc" "$WORK/bashrc.saved"
ln -s "$WORK/elsewhere" "$HOME/.bashrc"
check "symlink target fails the install" fails run_installer
check "symlink: nothing written" grep -qx 'old profile' "$HOME/.profile"
check "symlink: no backup" test "$(backups)" -eq 0
rm -f -- "$HOME/.bashrc"
mv -- "$WORK/bashrc.saved" "$HOME/.bashrc"

# a profile that fails check-profile.sh stops the install before anything is written
mkdir -p "$WORK/repo"
cp -r -- "$REPO_DIR/installer-libs" "$FAMILY_DIR" "$WORK/repo/"
printf 'unset_var_use=$undefined_var\n' >>"$WORK/repo/shell/home/profile"
check "failing profile check fails the install" \
    fails run_installer --installer "$WORK/repo/shell/install.sh"
check "failing check: nothing written" grep -qx 'old profile' "$HOME/.profile"
check "failing check: error names check-profile.sh" grep -q 'check-profile.sh failed' "$WORK/out.log"

# other homes and root-owned writes are skipped
check "as_root=1 is skipped" bash -c '
    source "$1" && shell_configure_home "$HOME" 1 && grep -qx "old profile" "$HOME/.profile"' _ "$INSTALLER"
check "another home is skipped" bash -c '
    source "$1" && shell_configure_home "$2" 0 && test ! -e "$2/.profile"' _ "$INSTALLER" "$WORK/other"

check "sudo was never called" test ! -e "$WORK/sudo-called"

(( OVERALL_RESULT == 0 )) && echo "All shell tests passed" || echo "Some shell tests FAILED"
exit "$OVERALL_RESULT"
