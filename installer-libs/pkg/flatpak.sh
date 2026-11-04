# shellcheck shell=bash
# Flatpak backend, sandbox integration, and the man AppArmor compatibility hook.

# shellcheck disable=SC2034
declare -ga BACKEND_ORDER=(flatpak bin_pkgmgr sys_pkg_mgr)

# shellcheck disable=SC2154
function ensure_man_apparmor_userns() {
    local local_file="/etc/apparmor.d/local/usr.bin.man" profile="/etc/apparmor.d/usr.bin.man"
    local marker="# linux-configs: allow flatpak (bwrap) pagers under man"
    local as_root=0

    [[ -f "$profile" ]] || return 0
    command -v apparmor_parser &>/dev/null || return 0
    grep -qsF "$marker" "$local_file" && return 0
    if (( EUID != 0 )); then
        if (( SUDO_GRANTED != 1 )); then
            log_notice "No sudo; add 'userns,' to $local_file by hand so flatpak pagers work under man"
            return 0
        fi
        as_root=1
    fi

    run_as "$as_root" mkdir -p "${local_file%/*}"
    printf '%s\nuserns,\n' "$marker" | run_as "$as_root" tee -a "$local_file" >/dev/null
    if ! run_as "$as_root" apparmor_parser -r "$profile"; then
        log_warn "Could not reload the man AppArmor profile; reverting the userns override"
        run_as "$as_root" sed -i -e "\|$marker|,+1d" "$local_file"
        return 0
    fi
    log_info "Allowed user namespaces for man in AppArmor ($local_file)"
}

function flatpak_purge_stale_deploy() {
    local app_id="$1" scope_flag="$2" app_dir removed_dir as_root=0

    if [[ "$scope_flag" == --system ]]; then
        app_dir="/var/lib/flatpak/app/$app_id"
        removed_dir="/var/lib/flatpak/.removed"
        as_root=1
    else
        app_dir="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/app/$app_id"
        removed_dir="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/.removed"
    fi

    if [[ -d "$removed_dir" ]]; then
        run_as "$as_root" rm -rf -- "$removed_dir/$app_id"-* 2>/dev/null || true
    fi
    flatpak info "$scope_flag" "$app_id" &>/dev/null && return 0
    [[ ! -d "$app_dir" ]] || run_as "$as_root" rm -rf -- "$app_dir"
}

# shellcheck disable=SC2154
function install_via_flatpak() {
    local dep="$1" cmd_name="$2" version="${3:-latest}"
    local app_id scope_flag bundle base_id install_ref export_bin target_dir as_root=0
    local -a fs_overrides=() xdg_appnames=()

    app_id="${FLATPAK_APP_ID[$dep]:-}"
    [[ -n "$app_id" ]] && command -v flatpak &>/dev/null || return 1
    if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then scope_flag=--system; as_root=1; else scope_flag=--user; fi
    flatpak_purge_stale_deploy "$app_id" "$scope_flag"

    if [[ -n "${LOCAL_FLATPAK_RESOURCE[$dep]:-}" ]]; then
        [[ "$version" == latest ]] || return 1
        bundle="$SCRIPT_DIR/resources/flatpaks/${LOCAL_FLATPAK_RESOURCE[$dep]}"
        [[ -f "$bundle" ]] || return 1
        base_id="${FLATPAK_BASE_APP_ID[$dep]:-}"
        [[ -n "$base_id" ]] || return 1
        flatpak info "$scope_flag" "$base_id" &>/dev/null || run_as "$as_root" flatpak install --noninteractive --assumeyes "$scope_flag" flathub "$base_id" || return 1
        run_as "$as_root" flatpak install --noninteractive --assumeyes "$scope_flag" "$bundle" || return 1
    else
        install_ref="$app_id"
        [[ "$version" == latest ]] || install_ref="$app_id//$version"
        run_as "$as_root" flatpak install --noninteractive --assumeyes "$scope_flag" flathub "$install_ref" || return 1
    fi

    run_as "$as_root" flatpak info "$scope_flag" "$app_id" &>/dev/null || return 1
    configure_flatpak_app "$dep" "$app_id" || return 1
    ensure_man_apparmor_userns

    if (( as_root == 1 )); then export_bin="/var/lib/flatpak/exports/bin/$app_id"; else export_bin="$HOME/.local/share/flatpak/exports/bin/$app_id"; fi
    target_dir="$(scoped_bin_dir)"
    run_as "$as_root" mkdir -p "$target_dir"
    if [[ -n "${FLATPAK_RUN_FLAGS[$dep]:-}" ]]; then
        run_as "$as_root" rm -f "$target_dir/$cmd_name"
        printf '#!/bin/sh\nexec flatpak run %s %s "$@"\n' "${FLATPAK_RUN_FLAGS[$dep]}" "$app_id" | run_as "$as_root" tee "$target_dir/$cmd_name" >/dev/null
        run_as "$as_root" chmod +x "$target_dir/$cmd_name"
    else
        run_as "$as_root" ln -sfn "$export_bin" "$target_dir/$cmd_name"
    fi
}

# shellcheck disable=SC2154
function configure_flatpak_app() {
    local dep="$1" app_id="$2" fs appname config_home sandbox_dir as_root=0
    local sandbox_path override_file
    local -a override_args=() fs_overrides=() xdg_appnames=()

    case "$RESOLVED_CONFIG_MODE" in
    local)
        config_home="$HOME"
        ;;
    users)
        config_home="/etc/skel"
        as_root=1
        ;;
    global)
        config_home=""
        as_root=1
        log_notice "Flatpak '$app_id' does not read host system-wide configs (/etc, /usr/share); only per-user configs are exposed"
        ;;
    *) return 0 ;;
    esac

    read -r -a fs_overrides <<< "${FLATPAK_FS_OVERRIDES[$dep]:-}"
    for fs in "${fs_overrides[@]}"; do
        if [[ "$fs" == '!'* ]]; then override_args+=("--nofilesystem=${fs#!}"); else override_args+=("--filesystem=$fs"); fi
    done
    read -r -a xdg_appnames <<< "${FLATPAK_XDG_APPNAMES[$dep]:-}"
    for appname in "${xdg_appnames[@]}"; do
        override_args+=("--filesystem=xdg-config/$appname" "--filesystem=xdg-data/$appname"
            "--filesystem=xdg-cache/$appname" "--filesystem=~/.local/state/$appname")
    done

    if [[ -n "${FLATPAK_PATH_EXPOSE[$dep]:-}" ]]; then
        if [[ "$RESOLVED_CONFIG_MODE" == local ]]; then
            override_file="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/overrides/$app_id"
        else
            override_file="/var/lib/flatpak/overrides/$app_id"
        fi
        if [[ -f "$override_file" ]]; then
            run_as "$as_root" sed -i -e '/^PATH=/d' -e '/^unset-environment=PATH;$/d' "$override_file"
        fi
        sandbox_path="$(flatpak run --command=printenv "$app_id" PATH)" || return 1
        if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then
            override_args+=("--env=PATH=$sandbox_path:/usr/local/bin")
        elif [[ "$RESOLVED_CONFIG_MODE" == local ]]; then
            override_args+=("--env=PATH=$sandbox_path:$HOME/.local/bin")
        else
            log_notice "User-scope tools in '$(scoped_bin_dir)' are not exposed to other users' '$app_id' sandbox"
        fi
    fi

    if (( ${#override_args[@]} > 0 )); then
        if (( as_root == 1 )); then run_priv flatpak override --system "${override_args[@]}" "$app_id" || return 1
        else flatpak override --user "${override_args[@]}" "$app_id" || return 1
        fi
    fi

    [[ -n "$config_home" ]] || return 0
    for appname in "${xdg_appnames[@]}"; do
        run_as "$as_root" mkdir -p "$config_home/.config/$appname" "$config_home/.local/share/$appname" \
            "$config_home/.cache/$appname" "$config_home/.local/state/$appname"
        sandbox_dir="$config_home/.var/app/$app_id/.local/state/$appname"
        run_as "$as_root" mkdir -p "${sandbox_dir%/*}"
        if [[ -d "$sandbox_dir" && ! -L "$sandbox_dir" ]]; then
            log_notice "Moving existing sandbox dir '$sandbox_dir' to '$sandbox_dir.bak'"
            run_as "$as_root" rm -rf "$sandbox_dir.bak"
            run_as "$as_root" mv "$sandbox_dir" "$sandbox_dir.bak"
        fi
        run_as "$as_root" ln -sfn "../../../../../.local/state/$appname" "$sandbox_dir"
    done
}

function is_installed_via_flatpak() {
    local dep="$1" app_id="${FLATPAK_APP_ID[$1]:-}" scope_flag=--user
    [[ -n "$app_id" ]] && command -v flatpak &>/dev/null || return 1
    [[ "$RESOLVED_INSTALL_MODE" != system ]] || scope_flag=--system
    flatpak info "$scope_flag" "$app_id" &>/dev/null
}