# shellcheck shell=bash
# Privilege-aware filesystem primitives shared by family installers.

function install_tree() {
    local as_root="$1" source_path="$2" destination="$3"
    shift 3
    run_as "$as_root" mkdir -p "$destination"
    run_as "$as_root" cp "$@" "$source_path" "$destination"
}

function install_file() {
    local as_root="$1" source_path="$2" destination="$3"
    shift 3
    local parent_dir="${destination%/*}"
    [[ "$parent_dir" == "$destination" ]] || run_as "$as_root" mkdir -p "$parent_dir"
    run_as "$as_root" cp "$@" "$source_path" "$destination"
}

function remove_paths() {
    local as_root="$1"
    shift
    (( $# == 0 )) && return 0
    run_as "$as_root" rm -rf -- "$@"
}

function link_path() {
    local as_root="$1" target="$2" link="$3" parent_dir="${3%/*}"
    [[ "$parent_dir" == "$link" ]] || run_as "$as_root" mkdir -p "$parent_dir"
    run_as "$as_root" ln -sfn -- "$target" "$link"
}