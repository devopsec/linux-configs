# shellcheck shell=bash
# Family hook dispatch and install orchestration.

# shellcheck disable=SC2154
function configure_apps() {
    local family home_dir
    local -a families=("$@")

    if [[ "$RESOLVED_CONFIG_MODE" != local ]] && (( EUID != 0 && SUDO_GRANTED != 1 )); then
        log_error "'-cm ${RESOLVED_CONFIG_MODE}' requires running as root (EUID=0)"
        return 1
    fi

    case "$RESOLVED_CONFIG_MODE" in
    global)
        log_info "Installing global configurations"
        for family in "${families[@]}"; do
            if (( CLEAN_CONFIGS == 1 )); then family_hook "$family" clean_global; fi
            family_hook "$family" configure_global
        done
        ;;
    users)
        log_info "Installing default configurations to /etc/skel"
        run_priv mkdir -p /etc/skel
        for family in "${families[@]}"; do
            if (( CLEAN_CONFIGS == 1 )); then family_hook "$family" clean_home /etc/skel 1; fi
            family_hook "$family" configure_home /etc/skel 1
        done
        if (( CLEAN_CONFIGS == 1 )); then
            for home_dir in /home/*/; do
                home_dir="${home_dir%/}"
                [[ -d "$home_dir" ]] || continue
                log_info "Refreshing configs for $home_dir"
                for family in "${families[@]}"; do
                    family_hook "$family" clean_home "$home_dir" 1
                    family_hook "$family" configure_home "$home_dir" 1
                done
                run_priv chown -R --reference="$home_dir" "$home_dir"
            done
        fi
        ;;
    local)
        log_info "Configuring apps for user ${USER:-$HOME} (local scope)"
        for family in "${families[@]}"; do
            if (( CLEAN_CONFIGS == 1 )); then family_hook "$family" clean_home "$HOME" 0; fi
            family_hook "$family" configure_home "$HOME" 0
        done
        ;;
    esac
}

# shellcheck disable=SC2154
function run_install() {
    local family requirement
    local -a families=() requirements=() family_requirements=()
    local -A requirement_seen=()

    for family in "$@"; do family_selected "$family" && families+=("$family"); done
    log_info "Starting linux-configs installation for: ${families[*]}"

    if (( CLEAN_PACKAGES == 1 )); then
        for family in "${families[@]}"; do family_hook "$family" clean_packages; done
    fi

    if (( SKIP_PACKAGES != 1 )); then
        log_info "Installing app dependencies (install mode: $RESOLVED_INSTALL_MODE)"
        for family in "${families[@]}"; do
            family_requirements=()
            read -r -a family_requirements <<< "${FAMILY_REQUIRES[$family]:-}"
            for requirement in "${family_requirements[@]}"; do
                [[ -n "$requirement" && -n "${requirement_seen[$requirement]:-}" ]] && continue
                [[ -z "$requirement" ]] && continue
                requirement_seen["$requirement"]=1
                requirements+=("$requirement")
            done
        done
        sys_pkgs_ensure "${requirements[@]}"
        for family in "${families[@]}"; do family_hook "$family" install_deps; done
        log_info "Finished installing app dependencies"
    fi

    if (( SKIP_CONFIGS != 1 )); then
        configure_apps "${families[@]}"
        if [[ "$RESOLVED_CONFIG_MODE" == local ]]; then
            for family in "${families[@]}"; do family_hook "$family" install_plugins; done
        else
            log_notice "Skipping per-user plugin sync for config mode '$RESOLVED_CONFIG_MODE'"
        fi
    else
        log_notice "Skipping config installation and plugin sync ('-sc')"
    fi

    log_info "Completed linux-configs installation"
    for family in "${families[@]}"; do family_hook "$family" post_install; done
}