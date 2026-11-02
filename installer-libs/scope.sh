# shellcheck shell=bash
# Install/config scope resolution and privilege-aware command execution.

declare -ga VALID_INSTALL_MODES=(system user auto)
declare -ga VALID_CONFIG_MODES=(global users local auto)
declare -g INSTALL_MODE="auto"
declare -g CONFIG_MODE="auto"
declare -g RESOLVED_INSTALL_MODE=""
declare -g RESOLVED_CONFIG_MODE=""
declare -gi SUDO_GRANTED=0

function is_valid_install_mode() {
    local mode="$1" candidate
    for candidate in "${VALID_INSTALL_MODES[@]}"; do
        [[ "$candidate" == "$mode" ]] && return 0
    done
    return 1
}

function is_valid_config_mode() {
    local mode="$1" candidate
    for candidate in "${VALID_CONFIG_MODES[@]}"; do
        [[ "$candidate" == "$mode" ]] && return 0
    done
    return 1
}

function resolve_scope() {
    if [[ "$INSTALL_MODE" == "auto" ]]; then
        if (( EUID == 0 )); then RESOLVED_INSTALL_MODE="system"; else RESOLVED_INSTALL_MODE="user"; fi
    else
        RESOLVED_INSTALL_MODE="$INSTALL_MODE"
    fi

    if [[ "$CONFIG_MODE" == "auto" ]]; then
        if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then RESOLVED_CONFIG_MODE="users"; else RESOLVED_CONFIG_MODE="local"; fi
    else
        RESOLVED_CONFIG_MODE="$CONFIG_MODE"
    fi
}

# shellcheck disable=SC2154
function prompt_sudo() {
    local answer needs_root=0 why=""

    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        needs_root=1
        why="'-im system'"
    elif (( SKIP_CONFIGS != 1 )) && [[ "$RESOLVED_CONFIG_MODE" != "local" ]]; then
        needs_root=1
        why="'-cm ${RESOLVED_CONFIG_MODE}'"
    fi

    (( EUID == 0 )) && return 0
    if (( needs_root == 0 && SKIP_PACKAGES == 1 )); then return 0; fi
    if ! command -v sudo &>/dev/null || [[ ! -t 0 ]]; then
        if (( needs_root == 1 )); then
            log_error "$why requires root (EUID=0) or an interactive sudo"
            return 1
        fi
        return 0
    fi

    if (( needs_root == 1 )); then
        log_notice "$why requires root privileges; sudo is needed"
        answer="y"
    else
        read -r -p "$(tag PROMPT) Use sudo to install system dependencies and packages? [y/N] " answer
    fi
    case "$answer" in
    y|Y|yes|YES)
        if sudo -v; then SUDO_GRANTED=1; else log_warn "sudo authentication failed; continuing without sudo"; fi
        ;;
    esac

    if (( needs_root == 1 && SUDO_GRANTED != 1 )); then
        log_error "$why requires root privileges and sudo was not granted"
        return 1
    fi
}

function can_use_sudo() {
    [[ "$RESOLVED_INSTALL_MODE" == "system" ]] || (( SUDO_GRANTED == 1 ))
}

function run_priv() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        log_error "sudo is required to run: $*"
        return 127
    fi
}

function run_as() {
    local as_root="$1"
    shift
    if (( as_root == 1 )); then run_priv "$@"; else "$@"; fi
}

function run_scoped() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then run_priv "$@"; else "$@"; fi
}

function scoped_bin_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then printf '%s\n' /usr/local/bin; else printf '%s\n' "$HOME/.local/bin"; fi
}

function scoped_data_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then printf '%s\n' /usr/share/binpak; else printf '%s\n' "$HOME/.local/share/binpak"; fi
}

function resolved_bin_dir() { scoped_bin_dir; }
function bin_pkgmgr_target_dir() { scoped_data_dir; }