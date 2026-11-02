# shellcheck shell=bash
# Optional man-page and shell-completion support for non-system app backends.

declare -gA DOCS_NAMES=()
declare -gA DOCS_MAN_URL=()
declare -gA DOCS_COMPLETION_CMD=()

# shellcheck disable=SC2154
function scoped_share_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == system ]]; then
        printf '%s\n' /usr/local/share
    else
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
    fi
}

function docs_completion_path() {
    local share_dir="$1" shell_name="$2" command_name="$3"
    case "$shell_name" in
    bash) printf '%s/bash-completion/completions/%s\n' "$share_dir" "$command_name" ;;
    zsh) printf '%s/zsh/site-functions/_%s\n' "$share_dir" "$command_name" ;;
    fish) printf '%s/fish/vendor_completions.d/%s.fish\n' "$share_dir" "$command_name" ;;
    *) return 1 ;;
    esac
}

function docs_system_man_exists() {
    local command_name="$1" page
    for page in /usr/share/man/man[1-9]/"$command_name".[1-9]* /usr/share/man/*/man[1-9]/"$command_name".[1-9]*; do
        [[ -e "$page" || -L "$page" ]] && return 0
    done
    return 1
}

function docs_system_completion_exists() {
    local shell_name="$1" command_name="$2" path
    local -a paths=()

    case "$shell_name" in
    bash)
        paths=("/usr/share/bash-completion/completions/$command_name"
            "/usr/share/bash-completion/completions/$command_name.bash")
        ;;
    zsh)
        paths=("/usr/share/zsh/site-functions/_$command_name"
            "/usr/share/zsh/vendor-completions/_$command_name"
            "/usr/share/zsh/functions/Completion/Unix/_$command_name")
        ;;
    fish)
        paths=("/usr/share/fish/vendor_completions.d/$command_name.fish"
            "/usr/share/fish/completions/$command_name.fish")
        ;;
    *) return 1 ;;
    esac

    for path in "${paths[@]}"; do
        [[ -e "$path" || -L "$path" ]] && return 0
    done
    return 1
}

function docs_manifest_record() {
    local manifest="$1" path="$2"
    if [[ -f "$manifest" ]] && grep -Fqx -- "$path" "$manifest"; then
        return 0
    fi
    if ! run_scoped mkdir -p "${manifest%/*}" || ! printf '%s\n' "$path" | run_scoped tee -a "$manifest" >/dev/null; then
        log_notice "Could not record installed documentation path '$path'"
        return 1
    fi
    return 0
}

function docs_copy_file() {
    local source="$1" destination="$2" manifest="$3"
    local parent_dir="${destination%/*}"

    [[ -f "$source" || -L "$source" ]] || return 1
    [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
    if ! run_scoped mkdir -p "$parent_dir" || ! run_scoped cp --update=none -- "$source" "$destination"; then
        log_notice "Could not install documentation file '$destination'"
        return 1
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then
        docs_manifest_record "$manifest" "$destination" || true
        return 0
    fi
    return 1
}

function docs_flatpak_copy_man() {
    local flatpak_share="$1" share_dir="$2" manifest="$3" command_name="$4" file relative_path
    local found=0
    local -a files=()

    [[ -d "$flatpak_share/man" ]] || return 1
    mapfile -d '' -t files < <(find "$flatpak_share/man" \( -type f -o -type l \) -name "$command_name.[1-9]*" -print0 2>/dev/null)
    for file in "${files[@]}"; do
        relative_path="${file#"$flatpak_share/"}"
        docs_copy_file "$file" "$share_dir/$relative_path" "$manifest" || true
        found=1
    done
    (( found == 1 ))
}

function docs_flatpak_copy_completion() {
    local flatpak_share="$1" share_dir="$2" manifest="$3" shell_name="$4" command_name="$5" source
    local destination
    local -a sources=()

    docs_system_completion_exists "$shell_name" "$command_name" && return 0
    destination="$(docs_completion_path "$share_dir" "$shell_name" "$command_name")" || return 1
    case "$shell_name" in
    bash)
        sources=("$flatpak_share/bash-completion/completions/$command_name"
            "$flatpak_share/bash-completion/completions/$command_name.bash")
        ;;
    zsh) sources=("$flatpak_share/zsh/site-functions/_$command_name") ;;
    fish)
        sources=("$flatpak_share/fish/vendor_completions.d/$command_name.fish"
            "$flatpak_share/fish/completions/$command_name.fish")
        ;;
    *) return 1 ;;
    esac

    for source in "${sources[@]}"; do
        if [[ -f "$source" || -L "$source" ]]; then
            docs_copy_file "$source" "$destination" "$manifest" || true
            return 0
        fi
    done
    return 1
}

function docs_download_man() {
    local url="$1" command_name="$2" share_dir="$3" manifest="$4" temp_file destination

    [[ -n "$url" ]] || return 1
    docs_system_man_exists "$command_name" && return 0
    destination="$share_dir/man/man1/$command_name.1"
    [[ ! -e "$destination" && ! -L "$destination" ]] || return 0
    if ! command -v curl &>/dev/null; then
        log_notice "Cannot download the '$command_name' man page; curl is unavailable"
        return 1
    fi
    temp_file="$(mktemp /tmp/linux-configs-man.XXXXXX)" || {
        log_notice "Cannot create a temporary file for the '$command_name' man page"
        return 1
    }
    if curl --fail --silent --show-error --location --output "$temp_file" "$url"; then
        docs_copy_file "$temp_file" "$destination" "$manifest" || true
    else
        log_notice "Could not download the '$command_name' man page from '$url'"
    fi
    rm -f -- "$temp_file"
}

function docs_generate_completions() {
    local dep="$1" command_name="$2" share_dir="$3" manifest="$4" shell_name output temp_file destination part
    local -a generator=() names=() shell_generator=()

    [[ -n "${DOCS_COMPLETION_CMD[$dep]:-}" ]] || return 0
    read -r -a generator <<< "${DOCS_COMPLETION_CMD[$dep]}"
    [[ ${#generator[@]} -gt 0 ]] || return 0
    read -r -a names <<< "${DOCS_NAMES[$dep]:-$command_name}"

    for shell_name in bash zsh fish; do
        for command_name in "${names[@]}"; do
            docs_system_completion_exists "$shell_name" "$command_name" && continue
            destination="$(docs_completion_path "$share_dir" "$shell_name" "$command_name")" || continue
            [[ ! -e "$destination" && ! -L "$destination" ]] || continue
            shell_generator=("${generator[@]}")
            for part in "${!shell_generator[@]}"; do
                shell_generator[part]="${shell_generator[part]//\{shell\}/$shell_name}"
            done
            if ! output="$("${shell_generator[@]}" 2>/dev/null)"; then
                log_notice "Could not generate the $shell_name completion for '$command_name'"
                continue
            fi
            if [[ -z "$output" ]]; then
                log_notice "The $shell_name completion generator returned no output for '$command_name'"
                continue
            fi
            temp_file="$(mktemp /tmp/linux-configs-completion.XXXXXX)" || {
                log_notice "Cannot create a temporary file for the $shell_name completion"
                continue
            }
            printf '%s\n' "$output" > "$temp_file"
            docs_copy_file "$temp_file" "$destination" "$manifest" || true
            rm -f -- "$temp_file"
        done
    done
}

function docs_install() {
    local dep="$1" command_name="$2" backend="$3"
    local share_dir manifest app_id scope_flag=--user location="" flatpak_share="" candidate found_man=0
    local shell_name name
    local -a names=()

    share_dir="$(scoped_share_dir)"
    manifest="$share_dir/linux-configs/docs/$dep.list"
    read -r -a names <<< "${DOCS_NAMES[$dep]:-$command_name}"

    if [[ "$backend" == flatpak ]]; then
        app_id="${FLATPAK_APP_ID[$dep]:-}"
        if [[ -n "$app_id" ]] && command -v flatpak &>/dev/null; then
            [[ "$RESOLVED_INSTALL_MODE" == system ]] && scope_flag=--system
            if location="$(flatpak info "$scope_flag" --show-location "$app_id" 2>/dev/null)"; then
                for candidate in "$location/files/share" "$location/share"; do
                    if [[ -d "$candidate" ]]; then
                        flatpak_share="$candidate"
                        break
                    fi
                done
            fi
            if [[ -n "$flatpak_share" ]]; then
                for name in "${names[@]}"; do
                    if docs_flatpak_copy_man "$flatpak_share" "$share_dir" "$manifest" "$name"; then
                        found_man=1
                    fi
                    for shell_name in bash zsh fish; do
                        docs_flatpak_copy_completion "$flatpak_share" "$share_dir" "$manifest" "$shell_name" "$name" || true
                    done
                done
            else
                log_notice "Could not locate Flatpak documentation files for '$dep'"
            fi
        fi
    fi

    if [[ "$backend" == bin_pkgmgr || ( "$backend" == flatpak && $found_man == 0 ) ]]; then
        docs_download_man "${DOCS_MAN_URL[$dep]:-}" "$command_name" "$share_dir" "$manifest" || true
    fi
    docs_generate_completions "$dep" "$command_name" "$share_dir" "$manifest"
    return 0
}

function docs_uninstall() {
    local dep="$1" share_dir manifest path

    share_dir="$(scoped_share_dir)"
    manifest="$share_dir/linux-configs/docs/$dep.list"
    [[ -f "$manifest" ]] || return 0
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -n "$path" ]] || continue
        if [[ "$path" != "$share_dir/"* || "$path" == *"/../"* || "$path" == */.. ]]; then
            log_notice "Ignoring unsafe documentation manifest entry '$path'"
            continue
        fi
        run_scoped rm -f -- "$path" || log_notice "Could not remove documentation file '$path'"
    done < "$manifest"
    run_scoped rm -f -- "$manifest" || log_notice "Could not remove documentation manifest '$manifest'"
    return 0
}