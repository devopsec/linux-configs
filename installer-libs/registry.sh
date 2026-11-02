# shellcheck shell=bash
# Registry contract shared by the root installer and independently sourced families.
# shellcheck disable=SC2034

declare -gi CLEAN_CONFIGS=0
declare -gi CLEAN_PACKAGES=0
declare -gi SKIP_PACKAGES=0
declare -gi SKIP_CONFIGS=0
declare -ga ALL_APPS=()
declare -ga APPS=()
declare -ga FAMILY_ORDER=()
declare -gA FAMILY_APPS=()
declare -gA FAMILY_REQUIRES=()

declare -gA FLATPAK_APP_ID=()
declare -gA FLATPAK_FS_OVERRIDES=()
declare -gA FLATPAK_RUN_FLAGS=()
declare -gA FLATPAK_XDG_APPNAMES=()
declare -gA FLATPAK_PATH_EXPOSE=()
declare -gA BIN_GH_REPO=()
declare -gA BIN_ASSET_GLOB=()
declare -gA LOCAL_DEB_RESOURCE=()
declare -gA LOCAL_FLATPAK_RESOURCE=()
declare -gA FLATPAK_BASE_APP_ID=()

function register_family() {
    local family="$1" app
    local -A seen=()
    shift

    [[ -n "$family" && $# -gt 0 ]] || {
        log_error "register_family requires a family name and at least one app"
        return 2
    }
    [[ -n "${FAMILY_APPS[$family]:-}" ]] && {
        log_error "Family '$family' is already registered"
        return 2
    }

    for app in "$@"; do
        if [[ -z "$app" || -n "${seen[$app]:-}" ]] || is_valid_app "$app"; then
            log_error "Invalid or duplicate app '$app' in family '$family'"
            return 2
        fi
        seen["$app"]=1
    done

    FAMILY_ORDER+=("$family")
    FAMILY_APPS["$family"]="$*"
    for app in "$@"; do
        ALL_APPS+=("$app")
    done
}

function family_requires() {
    local family="$1" requirement existing
    local -a requirements=()
    shift

    [[ -n "${FAMILY_APPS[$family]:-}" ]] || {
        log_error "Cannot declare requirements for unregistered family '$family'"
        return 2
    }
    read -r -a requirements <<< "${FAMILY_REQUIRES[$family]:-}"
    for requirement in "$@"; do
        for existing in "${requirements[@]}"; do
            [[ "$existing" == "$requirement" ]] && continue 2
        done
        requirements+=("$requirement")
    done
    FAMILY_REQUIRES["$family"]="${requirements[*]}"
}

function is_valid_app() {
    local app="$1" candidate
    for candidate in "${ALL_APPS[@]}"; do
        [[ "$candidate" == "$app" ]] && return 0
    done
    return 1
}

function app_selected() {
    local app="$1" candidate
    for candidate in "${APPS[@]}"; do
        [[ "$candidate" == "$app" ]] && return 0
    done
    return 1
}

function family_apps_selected() {
    local family="$1" app
    local -a family_apps=()
    read -r -a family_apps <<< "${FAMILY_APPS[$family]:-}"
    for app in "${family_apps[@]}"; do
        app_selected "$app" && return 0
    done
    return 1
}

function family_selected() {
    family_apps_selected "$1"
}

function family_hook() {
    local family="$1" hook="$2" function_name
    shift 2
    function_name="${family}_${hook}"
    declare -F "$function_name" >/dev/null || return 0
    "$function_name" "$@"
}