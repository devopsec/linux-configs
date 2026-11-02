# shellcheck shell=bash
# Shared command-line parsing for root and family installer entrypoints.

# shellcheck disable=SC2154
function print_usage() {
    cat <<EOF
Summary:
    Installer for Linux configs (${ALL_APPS[*]})
Usage:
    ${0##*/} [-h] [-cc] [-cp] [-sp] [-sc] [-im INSTALL_MODE] [-cm CONFIG_MODE] [APP...]
Options:
    -h      help                - show installer documentation
    -cc     clean configs       - remove existing editor configurations, then reinstall them
    -cp     clean packages      - remove installed packages/binaries for selected apps, then reinstall
    -sp     skip packages       - skip package dependencies
    -sc     skip configs        - skip configuration installation
    -im     install mode        - system, user, auto (default: auto)
    -cm     config mode         - global, users, local, auto (default: auto)
Arguments:
    APP     app(s) to install   - one or more of: ${ALL_APPS[*]}
                                - defaults to all ${#ALL_APPS[@]} apps when none are given
EOF
}

# shellcheck disable=SC2034
function setup_install() {
    local app
    while (( $# > 0 )); do
        case "$1" in
        -h) print_usage; exit 0 ;;
        -cc) CLEAN_CONFIGS=1; shift ;;
        -cp) CLEAN_PACKAGES=1; shift ;;
        -sp) SKIP_PACKAGES=1; shift ;;
        -sc) SKIP_CONFIGS=1; shift ;;
        -im)
            if (( $# < 2 )) || ! is_valid_install_mode "$2"; then
                log_error "'-im' requires one of: ${VALID_INSTALL_MODES[*]}"
                print_usage >&2
                return 2
            fi
            INSTALL_MODE="$2"
            shift 2
            ;;
        -cm)
            if (( $# < 2 )) || ! is_valid_config_mode "$2"; then
                log_error "'-cm' requires one of: ${VALID_CONFIG_MODES[*]}"
                print_usage >&2
                return 2
            fi
            CONFIG_MODE="$2"
            shift 2
            ;;
        -*)
            log_error "Invalid argument '$1'"
            print_usage >&2
            return 2
            ;;
        *)
            app="$1"
            if ! is_valid_app "$app"; then
                log_error "Invalid app '$app'"
                print_usage >&2
                return 2
            fi
            if app_selected "$app"; then
                log_error "Duplicate app '$app'"
                print_usage >&2
                return 2
            fi
            APPS+=("$app")
            shift
            ;;
        esac
    done

    (( ${#APPS[@]} > 0 )) || APPS=("${ALL_APPS[@]}")
    resolve_scope
    prompt_sudo
}