#!/usr/bin/env bash

# scm-auth family installer: the login keyring is the single source of SSH keys and HTTPS tokens
# for git/ssh and other SCM clients. Installs an SSH drop-in that leaves the agent to
# $SSH_AUTH_SOCK (gcr-ssh-agent), pulls it into ~/.ssh/config with an Include line and puts the
# scm-auth-migrate / scm-auth-status helpers on PATH (the migration is never run automatically),
# plus git-credential-token, scm-auth-login, forge-gist and the hf shim that hand the keyring
# token to forge/hf (gcli is retired by -cp). git-credential-scm (the keyring credential helper
# of the git chain) is built from source with zig 0.17 and installed next to them.
# sources the shared library for flags/orchestration; can also run standalone
# as 'scm-auth/install.sh [-cc] [-cp] [-sp] [-sc] [-im MODE] [-cm MODE] [scm-auth]'

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -Eeuo pipefail
    shopt -s inherit_errexit nullglob
fi

SCM_AUTH_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
# shellcheck source=installer-libs/common.sh
source "$SCM_AUTH_INSTALL_DIR/../installer-libs/common.sh"

register_family scm-auth scm-auth

SCM_AUTH_SSH_SRC_DIR="$SCM_AUTH_INSTALL_DIR/ssh/config.d"
SCM_AUTH_BIN_SRC_DIR="$SCM_AUTH_INSTALL_DIR/bin"
SCM_AUTH_GIT_SRC="$SCM_AUTH_INSTALL_DIR/git/scm-auth.gitconfig"
SCM_AUTH_GIT_REL=".config/git/scm-auth.gitconfig"
# literal '~/' so git expands it per user, also when the gitconfig is copied via /etc/skel
# shellcheck disable=SC2088
SCM_AUTH_GIT_INCLUDE="~/$SCM_AUTH_GIT_REL"
# top-level credential.helper values the include owns (same order as in the include)
SCM_AUTH_GIT_HELPERS=(scm scm-oauth)
# top-level credential.helper values the include replaces (the stock keyring helper, and the bare
# git-credential-oauth that scm-oauth guards); removed and recorded like the owned ones, so a
# leftover 'libsecret' never runs next to 'scm' and a bare 'oauth' never opens browser tabs for
# background callers
SCM_AUTH_GIT_LEGACY_HELPERS=(libsecret oauth)
# order in which dedupe removes and records top-level helpers (chain order), so clean restores e.g.
# libsecret->oauth or scm->oauth in their original order
SCM_AUTH_GIT_DEDUPE_ORDER=(libsecret scm oauth scm-oauth)
# multi-valued marker in <home>/.gitconfig recording exactly which top-level helpers dedupe removed
# (in chain order), so -cc restores those and nothing else
SCM_AUTH_GIT_MARKER='scm-auth.removedhelper'
# keep this line literal: ssh expands '~' itself, so it stays valid when copied via /etc/skel
# shellcheck disable=SC2088
SCM_AUTH_SSH_INCLUDE='Include ~/.ssh/config.d/*.conf'
# marker line in the first lines of shims (bin/hf); a file without it at the destination is a
# real binary and is never overwritten or removed
SCM_AUTH_SHIM_MARKER='# scm-auth shim'
# git-credential-scm: Zig sources (overridable for tests), binary name and required zig series
SCM_AUTH_HELPER_NAME=git-credential-scm
SCM_AUTH_HELPER_SRC_DIR="${SCM_AUTH_HELPER_SRC_DIR:-$SCM_AUTH_INSTALL_DIR/git-credential-scm}"
SCM_AUTH_ZIG_SERIES=0.17
# set once the helper is built/verified (or cleaned) in this run, so users mode does it only once
declare -gi SCM_AUTH_HELPER_READY=0
declare -gi SCM_AUTH_HELPER_CLEANED=0

pkg_define git-credential-oauth apt=git-credential-oauth pacman=git-credential-oauth
pkg_define libsecret-tools apt=libsecret-tools pacman=libsecret

# libsecret-tools (secret-tool): scm-auth-migrate clears the non-git 'SSH gitlab_ed25519' keyring item
# with it, and it is the generic way to inspect items ('secret-tool search --all application
# scm-auth'); git credentials themselves go through git-credential-scm. zig is not a package here:
# it comes from mise ('mise use -g zig@0.17') and is checked by scm_auth_zig_version
family_requires scm-auth git git-credential-oauth libsecret-tools

# prints the given file with every Include line owned by this family removed
# (surrounding whitespace and CRLF endings are tolerated)
function scm_auth_strip_include() {
    awk -v include_line="$SCM_AUTH_SSH_INCLUDE" '
        { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
        line == include_line { next }
        { print }
    ' "$1"
}

# counts the Include lines owned by this family in the given file
function scm_auth_count_include() {
    awk -v include_line="$SCM_AUTH_SSH_INCLUDE" '
        { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
        line == include_line { count++ }
        END { print count + 0 }
    ' "$1"
}

# makes the Include line the single, first line of <home>/.ssh/config; creates the file (0600)
# when absent, preserves all other content and the existing file mode/owner, rewrites nothing
# when already correct. Runs in a subshell so the EXIT trap only covers its own scratch dir
function scm_auth_ssh_include_ensure() (
    local target_home="$1" as_root="${2:-0}"
    local ssh_dir="$1/.ssh" config="$1/.ssh/config" work_dir="" first_line=""
    trap '[[ -z "$work_dir" ]] || rm -rf -- "$work_dir"' EXIT
    work_dir="$(mktemp -d /tmp/linux-configs-scm-auth.XXXXXX)"

    if ! run_as "$as_root" test -e "$config"; then
        log_info "Creating '$config' with the scm-auth Include line"
        printf '%s\n' "$SCM_AUTH_SSH_INCLUDE" > "$work_dir/config"
        run_as "$as_root" mkdir -p -m 0700 "$ssh_dir"
        run_as "$as_root" install -m 0600 "$work_dir/config" "$config"
        return 0
    fi

    run_as "$as_root" cat -- "$config" > "$work_dir/current"
    IFS= read -r first_line < "$work_dir/current" || true
    first_line="${first_line%$'\r'}"
    if [[ "$first_line" == "$SCM_AUTH_SSH_INCLUDE" ]] \
        && (( $(scm_auth_count_include "$work_dir/current") == 1 )); then
        log_info "'$config' already includes the scm-auth drop-ins"
        return 0
    fi

    log_info "Adding the scm-auth Include line as the first line of '$config'"
    {
        printf '%s\n' "$SCM_AUTH_SSH_INCLUDE"
        scm_auth_strip_include "$work_dir/current"
    } > "$work_dir/config"
    # cp onto the existing file keeps its mode and owner
    run_as "$as_root" cp -- "$work_dir/config" "$config"
)

# removes every Include line owned by this family from <home>/.ssh/config; leaves the rest alone
function scm_auth_ssh_include_remove() (
    local config="$1/.ssh/config" as_root="${2:-0}" work_dir=""
    trap '[[ -z "$work_dir" ]] || rm -rf -- "$work_dir"' EXIT
    run_as "$as_root" test -f "$config" || return 0
    work_dir="$(mktemp -d /tmp/linux-configs-scm-auth.XXXXXX)"

    run_as "$as_root" cat -- "$config" > "$work_dir/current"
    (( $(scm_auth_count_include "$work_dir/current") > 0 )) || return 0
    log_info "Removing the scm-auth Include line from '$config'"
    scm_auth_strip_include "$work_dir/current" > "$work_dir/config"
    run_as "$as_root" cp -- "$work_dir/config" "$config"
)

# git config against <home>/.gitconfig only (never the invoking user's global config)
function scm_auth_git_config() {
    local target_home="$1" as_root="$2"
    shift 2
    run_as "$as_root" env GIT_CONFIG_NOSYSTEM=1 git config --file "$target_home/.gitconfig" "$@"
}

# prints every value of <key> in <home>/.gitconfig, one per line (nothing when unset/absent)
function scm_auth_git_get_all() {
    scm_auth_git_config "$1" "$2" --get-all "$3" 2>/dev/null || true
}

# installs the credential include into <home>/.config/git, adds include.path once and, only then,
# drops top-level credential.helper entries the include already provides; differing helpers are
# kept and reported. Writes nothing when everything is already in place
function scm_auth_git_include_ensure() {
    local target_home="$1" as_root="${2:-0}"
    local destination="$1/$SCM_AUTH_GIT_REL" helper value
    local -a remaining=()
    if ! command -v git &>/dev/null; then
        log_notice "'git' not found; skipping the scm-auth git credential include"
        return 0
    fi
    if run_as "$as_root" cmp -s -- "$SCM_AUTH_GIT_SRC" "$destination"; then
        log_info "'$destination' is up to date"
    else
        install_file "$as_root" "$SCM_AUTH_GIT_SRC" "$destination"
        run_as "$as_root" chmod 0644 "$destination"
    fi

    if grep -qxF -- "$SCM_AUTH_GIT_INCLUDE" <(scm_auth_git_get_all "$target_home" "$as_root" include.path); then
        log_info "'$target_home/.gitconfig' already includes '$SCM_AUTH_GIT_INCLUDE'"
    else
        log_info "Adding include.path '$SCM_AUTH_GIT_INCLUDE' to '$target_home/.gitconfig'"
        scm_auth_git_config "$target_home" "$as_root" --add include.path "$SCM_AUTH_GIT_INCLUDE"
    fi

    # chain order, so the marker keeps it for clean
    for helper in "${SCM_AUTH_GIT_DEDUPE_ORDER[@]}"; do
        grep -qxF -- "$helper" <(scm_auth_git_get_all "$target_home" "$as_root" credential.helper) || continue
        # record before removing, once per value, so clean can put back exactly what was there
        if ! grep -qxF -- "$helper" <(scm_auth_git_get_all "$target_home" "$as_root" "$SCM_AUTH_GIT_MARKER"); then
            scm_auth_git_config "$target_home" "$as_root" --add "$SCM_AUTH_GIT_MARKER" "$helper"
        fi
        if scm_auth_is_legacy_helper "$helper"; then
            log_info "Removing legacy top-level credential.helper '$helper' from '$target_home/.gitconfig' (replaced by the scm-auth include: ${SCM_AUTH_GIT_HELPERS[*]})"
        else
            log_info "Removing top-level credential.helper '$helper' from '$target_home/.gitconfig' (provided by the scm-auth include)"
        fi
        scm_auth_git_config "$target_home" "$as_root" --fixed-value --unset-all credential.helper "$helper"
    done
    mapfile -t remaining < <(scm_auth_git_get_all "$target_home" "$as_root" credential.helper)
    for value in "${remaining[@]}"; do
        log_notice "'$target_home/.gitconfig' keeps its own credential.helper '${value:-<empty: resets the list>}'; it runs in addition to the scm-auth chain (${SCM_AUTH_GIT_HELPERS[*]}), review it"
    done
    return 0
}

# true when <helper> is a stock helper the include replaces
function scm_auth_is_legacy_helper() {
    local legacy
    for legacy in "${SCM_AUTH_GIT_LEGACY_HELPERS[@]}"; do
        [[ "$legacy" == "$1" ]] && return 0
    done
    return 1
}

# removes the include.path entry and the installed include, then restores exactly the top-level
# helpers dedupe recorded in the marker (appended in recorded order, so libsecret->oauth is kept;
# their position relative to other kept helpers is not) and deletes the marker. Helpers that were
# never removed are never written
function scm_auth_git_include_remove() {
    local target_home="$1" as_root="${2:-0}" helper
    local -a recorded=()
    run_as "$as_root" rm -f -- "$target_home/$SCM_AUTH_GIT_REL"
    command -v git &>/dev/null || return 0
    run_as "$as_root" test -f "$target_home/.gitconfig" || return 0

    if grep -qxF -- "$SCM_AUTH_GIT_INCLUDE" <(scm_auth_git_get_all "$target_home" "$as_root" include.path); then
        log_info "Removing include.path '$SCM_AUTH_GIT_INCLUDE' from '$target_home/.gitconfig'"
        scm_auth_git_config "$target_home" "$as_root" --fixed-value --unset-all include.path "$SCM_AUTH_GIT_INCLUDE"
        if [[ -z "$(scm_auth_git_config "$target_home" "$as_root" --get-regexp '^include\.' 2>/dev/null || true)" ]]; then
            scm_auth_git_config "$target_home" "$as_root" --remove-section include 2>/dev/null || true
        fi
    fi

    mapfile -t recorded < <(scm_auth_git_get_all "$target_home" "$as_root" "$SCM_AUTH_GIT_MARKER")
    (( ${#recorded[@]} > 0 )) || return 0
    for helper in "${recorded[@]}"; do
        [[ -n "$helper" ]] || continue
        grep -qxF -- "$helper" <(scm_auth_git_get_all "$target_home" "$as_root" credential.helper) && continue
        log_info "Restoring top-level credential.helper '$helper' in '$target_home/.gitconfig'"
        scm_auth_git_config "$target_home" "$as_root" --add credential.helper "$helper"
    done
    scm_auth_git_config "$target_home" "$as_root" --unset-all "$SCM_AUTH_GIT_MARKER" 2>/dev/null || true
    if [[ -z "$(scm_auth_git_config "$target_home" "$as_root" --get-regexp '^scm-auth\.' 2>/dev/null || true)" ]]; then
        scm_auth_git_config "$target_home" "$as_root" --remove-section scm-auth 2>/dev/null || true
    fi
    return 0
}

function scm_auth_install_deps() {
    local tool
    for tool in git git-credential-oauth secret-tool; do
        command -v "$tool" >/dev/null || log_notice "'$tool' not found on PATH; scm-auth credential helpers will not work until it is installed"
    done
    return 0
}

# 1 when the scoped bin dir needs sudo (system install mode as a regular user), else 0
function scm_auth_bin_as_root() {
    if [[ "$RESOLVED_INSTALL_MODE" == system ]] && (( EUID != 0 )); then echo 1; else echo 0; fi
}

# true when <file> carries the scm-auth shim marker within its first lines
function scm_auth_is_shim() {
    head -n 5 -- "$1" 2>/dev/null | grep -qxF -- "$SCM_AUTH_SHIM_MARKER"
}

# destination dir of a helper: shims honour SCM_AUTH_HF_SHIM_DIR (a dir earlier on PATH than the
# real CLI), everything else goes to scoped_bin_dir()
function scm_auth_bin_dest_dir() {
    if scm_auth_is_shim "$1" && [[ -n "${SCM_AUTH_HF_SHIM_DIR:-}" ]]; then
        printf '%s\n' "$SCM_AUTH_HF_SHIM_DIR"
    else
        scoped_bin_dir
    fi
}

# installs the helper scripts (scm-auth-migrate, scm-auth-status, git-credential-token,
# scm-auth-login, forge-gist, hf shim) into scoped_bin_dir() with mode 0755, rewriting only
# changed files; a shim never replaces a foreign file (e.g. a real hf). They are never run here,
# so the installer itself never calls systemctl or secret-tool in any config mode
function scm_auth_bin_install() {
    local bin_as_root bin_dir script destination
    bin_as_root="$(scm_auth_bin_as_root)"
    for script in "$SCM_AUTH_BIN_SRC_DIR"/*; do
        bin_dir="$(scm_auth_bin_dest_dir "$script")"
        destination="$bin_dir/${script##*/}"
        if run_as "$bin_as_root" cmp -s -- "$script" "$destination"; then
            log_info "'$destination' is up to date"
            continue
        fi
        if scm_auth_is_shim "$script" && run_as "$bin_as_root" test -e "$destination" \
            && ! scm_auth_is_shim "$destination"; then
            log_notice "'$destination' exists and is not the scm-auth shim; leaving it alone. Set SCM_AUTH_HF_SHIM_DIR to a directory earlier on PATH than it and re-run to install the ${script##*/} shim there"
            continue
        fi
        run_as "$bin_as_root" mkdir -p "$bin_dir"
        run_as "$bin_as_root" install -m 0755 -- "$script" "$destination"
    done
}

# removes the installed helpers; a shim destination is only removed when it is our shim
function scm_auth_bin_remove() {
    local bin_as_root script destination
    bin_as_root="$(scm_auth_bin_as_root)"
    for script in "$SCM_AUTH_BIN_SRC_DIR"/*; do
        destination="$(scm_auth_bin_dest_dir "$script")/${script##*/}"
        if scm_auth_is_shim "$script"; then
            run_as "$bin_as_root" test -e "$destination" || continue
            scm_auth_is_shim "$destination" || continue
        fi
        run_as "$bin_as_root" rm -f -- "$destination"
    done
}

# the invoking user's scm-auth cache dir: the helper's per-destination stamps and the zig build cache
function scm_auth_cache_dir() {
    printf '%s/scm-auth\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# prints the version of the zig on PATH; fails with a clear error unless it is the pinned series
function scm_auth_zig_version() {
    local version=""
    if ! command -v zig &>/dev/null; then
        log_error "'zig' ${SCM_AUTH_ZIG_SERIES}.x is required to build $SCM_AUTH_HELPER_NAME but is not on PATH (e.g. 'mise use -g zig@${SCM_AUTH_ZIG_SERIES}')"
        return 1
    fi
    version="$(zig version 2>/dev/null)" || version=""
    if [[ "$version" != "$SCM_AUTH_ZIG_SERIES".* ]]; then
        log_error "$SCM_AUTH_HELPER_NAME needs zig ${SCM_AUTH_ZIG_SERIES}.x, found '${version:-unknown}' at '$(command -v zig)' (e.g. 'mise use -g zig@${SCM_AUTH_ZIG_SERIES}')"
        return 1
    fi
    printf '%s\n' "$version"
}

# sha256 over the zig version and every helper source (build.zig, build.zig.zon, src/**/*.zig):
# sorted relative names plus content hashes, so it is stable across checkouts
function scm_auth_helper_source_hash() {
    local zig_version="$1"
    {
        printf 'zig %s\n' "$zig_version"
        (cd "$SCM_AUTH_HELPER_SRC_DIR" && find build.zig build.zig.zon src -type f \( -name '*.zig' -o -name '*.zon' \) -print0 \
            | LC_ALL=C sort -z | xargs -0 -r sha256sum --)
    } | sha256sum | cut -d ' ' -f 1
}

# builds the helper (ReleaseSafe) into a scratch prefix and installs it as <destination> (0755):
# staged next to it and renamed over it, so a failed build or copy never leaves a partial binary.
# Runs in a subshell so the EXIT trap only covers its own scratch dir
function scm_auth_helper_build_install() (
    local destination="$1" bin_as_root="$2" cache_dir="$3" zig_version="$4" work_dir="" built
    trap '[[ -z "$work_dir" ]] || rm -rf -- "$work_dir"' EXIT
    work_dir="$(mktemp -d /tmp/linux-configs-scm-auth-build.XXXXXX)"
    built="$work_dir/prefix/bin/$SCM_AUTH_HELPER_NAME"
    mkdir -p "$cache_dir" || return 1
    log_info "Building $SCM_AUTH_HELPER_NAME with zig $zig_version (ReleaseSafe; a cold build cache takes a few minutes)"
    if ! (cd "$SCM_AUTH_HELPER_SRC_DIR" && zig build -Doptimize=ReleaseSafe --prefix "$work_dir/prefix" --cache-dir "$cache_dir/zig"); then
        log_error "zig build of $SCM_AUTH_HELPER_NAME failed; '$destination' was not changed"
        return 1
    fi
    if [[ ! -f "$built" ]]; then
        log_error "zig build did not produce '$built'; '$destination' was not changed"
        return 1
    fi
    if ! { install_file "$bin_as_root" "$built" "$destination.new" \
        && run_as "$bin_as_root" chmod 0755 "$destination.new" \
        && run_as "$bin_as_root" mv -f -- "$destination.new" "$destination"; }; then
        run_as "$bin_as_root" rm -f -- "$destination.new" || true
        log_error "could not install '$destination'"
        return 1
    fi
    log_info "Installed '$destination'"
)

# per-destination stamp: <cache>/stamps/<sha256 of the destination path>.sha256 holds
# '<source hash> <sha256 of the installed binary>', so every install target keeps its own record
function scm_auth_helper_stamp() {
    local key
    key="$(printf '%s' "$1" | sha256sum | cut -d ' ' -f 1)"
    printf '%s/stamps/%s.sha256\n' "$(scm_auth_cache_dir)" "$key"
}

# prints the sha256 of the binary installed at <destination>; empty when it is not installed
function scm_auth_helper_installed_sha() {
    local bin_as_root="$1" destination="$2"
    run_as "$bin_as_root" test -f "$destination" || return 0
    run_as "$bin_as_root" sha256sum -- "$destination" | cut -d ' ' -f 1
}

# builds and installs git-credential-scm into scoped_bin_dir(). Skipped only when this destination's
# stamp holds the current source hash AND the installed binary still has the recorded sha256 (so a
# binary replaced out of band is reinstalled). Done once per run: users mode visits many homes, all
# of which share the one scoped bin dir
function scm_auth_build_helper() {
    local bin_as_root destination cache_dir stamp zig_version hash="" installed=""
    local recorded_hash="" recorded_bin=""
    (( SCM_AUTH_HELPER_READY == 0 )) || return 0
    bin_as_root="$(scm_auth_bin_as_root)"
    destination="$(scoped_bin_dir)/$SCM_AUTH_HELPER_NAME"
    cache_dir="$(scm_auth_cache_dir)"
    stamp="$(scm_auth_helper_stamp "$destination")"
    if [[ ! -f "$SCM_AUTH_HELPER_SRC_DIR/build.zig" ]]; then
        log_error "$SCM_AUTH_HELPER_NAME sources not found in '$SCM_AUTH_HELPER_SRC_DIR'"
        return 1
    fi
    zig_version="$(scm_auth_zig_version)" || return 1
    hash="$(scm_auth_helper_source_hash "$zig_version")" || hash=""
    if [[ ! "$hash" =~ ^[0-9a-f]{64}$ ]]; then
        log_error "could not hash the $SCM_AUTH_HELPER_NAME sources in '$SCM_AUTH_HELPER_SRC_DIR'"
        return 1
    fi
    installed="$(scm_auth_helper_installed_sha "$bin_as_root" "$destination")"
    if [[ -f "$stamp" ]]; then
        read -r recorded_hash recorded_bin < "$stamp" || true
    fi
    if [[ -n "$installed" && "$recorded_hash" == "$hash" && "$recorded_bin" == "$installed" ]]; then
        log_info "'$destination' is up to date (sources and installed binary unchanged)"
        SCM_AUTH_HELPER_READY=1
        return 0
    fi
    if [[ -z "$installed" ]]; then
        log_info "'$destination' is not installed; building it"
    elif [[ "$recorded_hash" != "$hash" ]]; then
        log_info "sources or zig changed since '$destination' was built; rebuilding"
    else
        log_info "'$destination' was replaced outside the installer or has no stamp; rebuilding"
    fi
    scm_auth_helper_build_install "$destination" "$bin_as_root" "$cache_dir" "$zig_version" || return 1
    installed="$(scm_auth_helper_installed_sha "$bin_as_root" "$destination")"
    [[ -n "$installed" ]] || { log_error "could not read back '$destination' after installing it"; return 1; }
    mkdir -p "${stamp%/*}" || { log_error "could not create '${stamp%/*}'"; return 1; }
    printf '%s %s\n' "$hash" "$installed" > "$stamp" || { log_error "could not write '$stamp'"; return 1; }
    SCM_AUTH_HELPER_READY=1
}

# removes the installed git-credential-scm, the stamp of its destination (and the single stamp of
# older installs), the zig build cache and the cache dirs it leaves empty. Once per run, and never
# right after this run built it: users mode cleans every home after the first configure
function scm_auth_helper_remove() {
    local bin_as_root destination cache_dir stamp
    (( SCM_AUTH_HELPER_CLEANED == 0 && SCM_AUTH_HELPER_READY == 0 )) || return 0
    SCM_AUTH_HELPER_CLEANED=1
    bin_as_root="$(scm_auth_bin_as_root)"
    destination="$(scoped_bin_dir)/$SCM_AUTH_HELPER_NAME"
    cache_dir="$(scm_auth_cache_dir)"
    stamp="$(scm_auth_helper_stamp "$destination")"
    run_as "$bin_as_root" rm -f -- "$destination" "$destination.new"
    rm -f -- "$stamp" "$cache_dir/$SCM_AUTH_HELPER_NAME.sha256"
    rm -rf -- "$cache_dir/zig"
    if [[ -d "${stamp%/*}" ]]; then
        rmdir --ignore-fail-on-non-empty -- "${stamp%/*}"
    fi
    if [[ -d "$cache_dir" ]]; then
        rmdir --ignore-fail-on-non-empty -- "$cache_dir"
    fi
    return 0
}

# every gcli on PATH plus copies in the scoped/user bin dirs, one path per line
function scm_auth_gcli_paths() {
    local path
    type -aP gcli || true
    for path in "$(scoped_bin_dir)/gcli" "$HOME/.local/bin/gcli"; do
        [[ ! -e "$path" ]] || printf '%s\n' "$path"
    done
}

# retires gcli (replaced by 'forge api' and forge-gist). Only the exact copies this family may
# own are removed: the scoped bin dir and ~/.local/bin (as the invoking user) and /usr/local/bin
# (via run_priv). Every other gcli on PATH (package manager, homebrew, mise shims, nix, cargo,
# /usr/bin, ...) is only reported, and the invoking user's gcli config is removed
function scm_auth_clean_packages() {
    local path config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gcli"
    local -A seen=()
    local -A removable=(
        ["$(scoped_bin_dir)/gcli"]=user
        ["$HOME/.local/bin/gcli"]=user
        [/usr/local/bin/gcli]=priv
    )
    while IFS= read -r path; do
        [[ -n "$path" && -z "${seen[$path]:-}" ]] || continue
        seen[$path]=1
        case "${removable[$path]:-}" in
        user)
            log_info "Removing gcli '$path' (replaced by 'forge api' / forge-gist)"
            rm -f -- "$path"
            ;;
        priv)
            log_info "Removing gcli '$path' (replaced by 'forge api' / forge-gist)"
            run_priv rm -f -- "$path"
            ;;
        *)
            log_notice "gcli at '$path' is outside the paths scm-auth removes; remove it with the tool that installed it (system package: 'sudo apt remove gcli' / 'sudo pacman -R gcli'; mise, brew, nix, cargo: their own uninstall)"
            ;;
        esac
    done < <(scm_auth_gcli_paths)
    if [[ -d "$config_dir" ]]; then
        log_info "Removing the gcli config '$config_dir'"
        rm -rf -- "$config_dir"
    fi
    return 0
}

# installs the SSH drop-ins, ensures ~/.ssh/config includes them, installs the git credential
# include (+ include.path in ~/.gitconfig), the helper scripts and the built git-credential-scm;
# as_root=1 uses sudo
function scm_auth_configure_home() {
    local target_home="$1" as_root="${2:-0}"
    local drop_in destination
    scm_auth_bin_install
    scm_auth_build_helper || return 1
    run_as "$as_root" mkdir -p -m 0700 "$target_home/.ssh"
    for drop_in in "$SCM_AUTH_SSH_SRC_DIR"/*.conf; do
        destination="$target_home/.ssh/config.d/${drop_in##*/}"
        if run_as "$as_root" cmp -s -- "$drop_in" "$destination"; then
            log_info "'$destination' is up to date"
            continue
        fi
        install_file "$as_root" "$drop_in" "$destination"
        run_as "$as_root" chmod 0644 "$destination"
    done
    scm_auth_ssh_include_ensure "$target_home" "$as_root"
    scm_auth_git_include_ensure "$target_home" "$as_root"
    return 0
}

# removes only the drop-ins shipped here, the Include line and the git include; the user's own
# ~/.ssh/config / ~/.gitconfig content and foreign drop-ins are kept
function scm_auth_clean_home() {
    local target_home="$1" as_root="${2:-0}" drop_in
    scm_auth_bin_remove
    scm_auth_helper_remove
    for drop_in in "$SCM_AUTH_SSH_SRC_DIR"/*.conf; do
        run_as "$as_root" rm -f -- "$target_home/.ssh/config.d/${drop_in##*/}"
    done
    if run_as "$as_root" test -d "$target_home/.ssh/config.d"; then
        run_as "$as_root" rmdir --ignore-fail-on-non-empty -- "$target_home/.ssh/config.d"
    fi
    scm_auth_ssh_include_remove "$target_home" "$as_root"
    scm_auth_git_include_remove "$target_home" "$as_root"
    scm_auth_hf_token_remove "$target_home" "$as_root"
    return 0
}

# drops the plaintext hf token file <home>/.cache/huggingface/token; the hf shim exports HF_TOKEN
# from the keyring instead ('scm-auth-login hf' stores it there). stored_tokens may hold other named
# hf accounts that are not in the keyring, so it is left for the user to review
function scm_auth_hf_token_remove() {
    local target_home="$1" as_root="${2:-0}" path="$1/.cache/huggingface/token"
    run_as "$as_root" test -e "$path" || return 0
    log_info "Removing plaintext hf token file '$path' (store it with 'scm-auth-login hf')"
    run_as "$as_root" rm -f -- "$path"
    if run_as "$as_root" test -e "$target_home/.cache/huggingface/stored_tokens"; then
        log_notice "hf keeps '$target_home/.cache/huggingface/stored_tokens'; review it and delete it by hand if it is not needed"
    fi
    return 0
}

# the migration touches the running user session (systemd --user, keyring), so it is only
# suggested in local mode and always left to the user to run
function scm_auth_post_install() {
    [[ "$RESOLVED_CONFIG_MODE" == local ]] || return 0
    log_info "scm-auth: point forge at the keyring token with 'scm-auth-login github.com' (per forge domain) and store the Hugging Face token with 'scm-auth-login hf'."
    log_info "scm-auth: SCM hosts use \$SSH_AUTH_SOCK (gcr-ssh-agent). Review 'scm-auth-migrate --dry-run', then run 'scm-auth-migrate --apply' to retire IdentityAgent pins, the plain ssh-agent and the ssh-add-gitlab workaround; check with 'scm-auth-status'."
}

# standalone entrypoint: only runs when invoked directly, not when sourced by the root installer
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    setup_install "$@"
    run_install scm-auth
fi
