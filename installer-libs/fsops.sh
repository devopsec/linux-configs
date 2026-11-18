# shellcheck shell=bash
# Privilege-aware filesystem primitives shared by family installers.

function install_tree() {
    local as_root="$1" source_path="$2" destination="$3"
    shift 3
    run_as "$as_root" mkdir -p "$destination"
    run_as "$as_root" cp "$@" "$source_path" "$destination"
}

# root's default umask: login.defs UMASK, 022 when unset
function root_umask() {
    local value
    value="$(awk '$1 == "UMASK" { print $2; exit }' /etc/login.defs 2>/dev/null)" || value=""
    printf '%s\n' "${value:-022}"
}

# copies a file to a new destination file (replacing any file or symlink there) with the default
# (umask) permissions of the account installing it, executable when the source is: the caller's,
# or root's for as_root=1 (sudo would keep the caller's umask when it is stricter); extra
# arguments are cp options
function install_file() {
    local as_root="$1" source_path="$2" destination="$3" mask
    shift 3
    local parent_dir="${destination%/*}"
    [[ "$parent_dir" == "$destination" ]] && parent_dir=""
    mask="$(umask)"
    if (( as_root == 1 && EUID != 0 )); then mask="$(root_umask)"; fi
    # shellcheck disable=SC2016
    run_as "$as_root" sh -c '
        umask "$1" || exit
        parent_dir="$2" source_path="$3" destination="$4"
        shift 4
        if [ -n "$parent_dir" ]; then mkdir -p -- "$parent_dir" || exit; fi
        cp --remove-destination --no-preserve=mode "$@" -- "$source_path" "$destination" || exit
        if [ -x "$source_path" ]; then chmod +x -- "$destination"; fi
    ' sh "$mask" "$parent_dir" "$source_path" "$destination" "$@"
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