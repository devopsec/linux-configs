# shellcheck shell=bash
# marcosnils/bin release-binary backend.

# shellcheck disable=SC2154
function install_via_bin_pkgmgr() {
    local dep="$1" command_name="$2" version="${3:-latest}"
    local repo asset install_ref target_dir link_dir link_as_root=0
    local -a bin_command=()

    repo="${BIN_GH_REPO[$dep]:-}"
    [[ -n "$repo" ]] && command -v bin &>/dev/null || return 1
    asset="${BIN_ASSET_GLOB[$dep]:-}"
    install_ref="github.com/$repo"
    [[ "$version" == latest ]] || install_ref="$install_ref/releases/tag/$version"
    target_dir="$(scoped_data_dir)"
    link_dir="$(scoped_bin_dir)"

    bin_command=(bin install --force "$install_ref")
    [[ -z "$asset" ]] || bin_command+=(-n "$asset")
    bin_command+=("$target_dir/$command_name")

    run_scoped mkdir -p "$target_dir" "$link_dir" || return 1
    run_scoped "${bin_command[@]}" || return 1
    [[ "$RESOLVED_INSTALL_MODE" == system && $EUID != 0 ]] && link_as_root=1
    link_path "$link_as_root" "$target_dir/$command_name" "$link_dir/$command_name" || return 1
    return 0
}

function is_installed_via_bin_pkgmgr() {
    local dep="$1" command_name="$2"
    [[ -n "${BIN_GH_REPO[$dep]:-}" && -e "$(scoped_data_dir)/$command_name" ]]
}