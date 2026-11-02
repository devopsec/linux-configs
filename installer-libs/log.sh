# shellcheck shell=bash
# Shared logging primitives for installer entrypoints and family modules.

declare -gr COLOR_RESET='\033[0m'
declare -gr COLOR_RED='\033[0;31m'
declare -gr COLOR_GREEN='\033[0;32m'
declare -gr COLOR_YELLOW='\033[0;33m'
declare -gr COLOR_BLUE='\033[0;34m'
declare -gr COLOR_MAGENTA='\033[0;35m'
declare -gr COLOR_CYAN='\033[0;36m'
declare -gi USE_COLOR=0
if [[ -z "${NO_COLOR:-}" ]] && { [[ -t 1 ]] || [[ -t 2 ]]; }; then
    USE_COLOR=1
fi

function tag() {
    local level="$1" color=""

    case "$level" in
    INFO) color="$COLOR_GREEN" ;;
    WARN) color="$COLOR_YELLOW" ;;
    ERROR) color="$COLOR_RED" ;;
    NOTICE) color="$COLOR_CYAN" ;;
    DEBUG) color="$COLOR_MAGENTA" ;;
    PROMPT) color="$COLOR_BLUE" ;;
    esac

    if (( USE_COLOR == 1 )); then
        printf '%b[%s]%b' "$color" "$level" "$COLOR_RESET"
    else
        printf '[%s]' "$level"
    fi
}

function log_info() { printf '%s %s\n' "$(tag INFO)" "$*"; }
function log_notice() { printf '%s %s\n' "$(tag NOTICE)" "$*" >&2; }
function log_warn() { printf '%s %s\n' "$(tag WARN)" "$*" >&2; }
function log_error() { printf '%s %s\n' "$(tag ERROR)" "$*" >&2; }