# shellcheck shell=bash
# App-level package orchestration over the flatpak, bin and system backends.

# shellcheck disable=SC2154
function active_backend_order() {
    if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then
        printf '%s\n' sys_pkg_mgr
    else
        printf '%s\n' "${BACKEND_ORDER[@]}"
    fi
}

function detect_installed_backend() {
    local dep="$1" command_name="$2" backend
    local -a order=()
    mapfile -t order < <(active_backend_order)
    for backend in "${order[@]}"; do
        case "$backend" in
        sys_pkg_mgr) sys_pkg_installed "$dep" && { printf '%s\n' "$backend"; return 0; } ;;
        flatpak) is_installed_via_flatpak "$dep" && { printf '%s\n' "$backend"; return 0; } ;;
        bin_pkgmgr) is_installed_via_bin_pkgmgr "$dep" "$command_name" && { printf '%s\n' "$backend"; return 0; } ;;
        esac
    done
    return 1
}

# shellcheck disable=SC2154
function install_via_sys_pkg_mgr() {
    local dep="$1" version="${2:-latest}" deb_name deb_path

    if [[ "$(sys_pkg_manager)" == apt && -n "${LOCAL_DEB_RESOURCE[$dep]:-}" ]]; then
        deb_name="${LOCAL_DEB_RESOURCE[$dep]}"
        deb_path="$SCRIPT_DIR/resources/$deb_name"
        if [[ -f "$deb_path" ]]; then
            run_priv dpkg -i "$deb_path" || run_priv apt-get install -y -f || return 1
            return 0
        fi
    fi
    sys_pkg_install "$dep" "$version"
}

function app_pkg_install() {
    local dep="$1" command_name="${2:-$1}" backend version="latest" existing_backend
    local -a order=()

    if existing_backend="$(detect_installed_backend "$dep" "$command_name")"; then
        log_info "'$dep' is already installed via $existing_backend; using the existing installation"
        docs_install "$dep" "$command_name" "$existing_backend"
        return 0
    fi
    mapfile -t order < <(active_backend_order)

    for backend in "${order[@]}"; do
        case "$backend" in
        sys_pkg_mgr)
            log_info "Installing '$dep' ($version) via system package manager"
            if install_via_sys_pkg_mgr "$dep" "$version"; then
                log_info "Installed '$dep' via system package manager"
                docs_install "$dep" "$command_name" "$backend"
                return 0
            fi
            ;;
        flatpak)
            log_info "Installing '$dep' ($version) via flatpak"
            if install_via_flatpak "$dep" "$command_name" "$version"; then
                log_info "Installed '$dep' via flatpak"
                docs_install "$dep" "$command_name" "$backend"
                return 0
            fi
            ;;
        bin_pkgmgr)
            log_info "Installing '$dep' ($version) via bin package manager"
            if install_via_bin_pkgmgr "$dep" "$command_name" "$version"; then
                log_info "Installed '$dep' via bin package manager"
                docs_install "$dep" "$command_name" "$backend"
                return 0
            fi
            ;;
        esac
        log_warn "Backend '$backend' could not provide '$dep', trying next backend"
    done

    if [[ "$version" == latest ]] && command -v "$command_name" &>/dev/null; then
        log_info "Using already-installed '$command_name' at $(command -v "$command_name") for '$dep'"
        docs_install "$dep" "$command_name" sys_pkg_mgr
        return 0
    fi
    log_error "Failed to install '$dep' via any available backend"
    return 1
}

function app_pkg_uninstall() {
    local dep="$1" command_name="${2:-$1}" target_dir link_dir package_name stale
    local scope_flag=--user as_root=0

    docs_uninstall "$dep"

    if [[ -n "${FLATPAK_APP_ID[$dep]:-}" ]] && command -v flatpak &>/dev/null; then
        if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then scope_flag=--system; as_root=1; fi
        flatpak_purge_stale_deploy "${FLATPAK_APP_ID[$dep]}" "$scope_flag"
        if is_installed_via_flatpak "$dep"; then
            run_as "$as_root" flatpak uninstall -y --noninteractive "$scope_flag" "${FLATPAK_APP_ID[$dep]}" &>/dev/null || true
            flatpak_purge_stale_deploy "${FLATPAK_APP_ID[$dep]}" "$scope_flag"
        fi
    fi

    if is_installed_via_bin_pkgmgr "$dep" "$command_name"; then
        target_dir="$(scoped_data_dir)/$command_name"
        link_dir="$(scoped_bin_dir)"
        if [[ "$(readlink "$link_dir/$command_name" 2>/dev/null)" == "$target_dir" ]]; then
            run_scoped rm -f "$link_dir/$command_name"
        fi
        run_scoped rm -rf "$target_dir"
    fi

    if sys_pkg_installed "$dep"; then
        package_name="$(sys_pkg_name "$dep")"
        sys_pkg_remove "$dep" || true
        # Some prior installs used the raw package name as the dependency id.
        [[ -n "$package_name" ]] || log_notice "Could not resolve system package name for '$dep'"
    fi

    link_dir="$(scoped_bin_dir)"
    for stale in "$link_dir/$command_name" "$link_dir/$command_name-nvim"; do
        if [[ -L "$stale" ]] || { [[ -f "$stale" ]] && grep -q 'flatpak run' "$stale" 2>/dev/null && (( $(wc -c <"$stale") < 1024 )); }; then
            run_scoped rm -f "$stale"
        fi
    done
}

function app_pkg_via_flatpak() {
    is_installed_via_flatpak "$1"
}