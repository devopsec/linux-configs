# shellcheck shell=sh
#=============================================================================================
# Script Helper Functions
#=============================================================================================
# POSIX sh, builtins only (no forks), safe under `set -u`. Every PATH entry should be
# absolute: an empty, "." or relative entry makes command lookup depend on the current
# directory. Call __shell_path_clean once before the other helpers.

# Warn on stderr that PATH entry "$1" is skipped because of "$2". A value with
# non-printable characters is not printed, so it cannot send escape sequences to the
# terminal.
__shell_path_warn() {
    case $1 in
        *[![:print:]]*) set -- '<has non-printable characters>' "$2" ;;
        *) set -- "'$1'" "$2" ;;
    esac
    printf 'profile: skipping PATH entry %s: %s\n' "$1" "$2" >&2
}

# Succeed when "$1" can be a PATH entry: absolute and free of ":".
__shell_path_valid() {
    case ${1-} in
        '') __shell_path_warn '' 'empty' ;;
        *:*) __shell_path_warn "$1" 'contains ":"' ;;
        /*) return 0 ;;
        *) __shell_path_warn "$1" 'not an absolute path' ;;
    esac
    return 1
}

# Drop every PATH entry that is not an absolute path, with a warning for each.
__shell_path_clean() {
    case ":${PATH-}:" in
        *:[!/]*) ;;
        *) return 0 ;;
    esac
    __shell_path_rest="${PATH-}:"
    __shell_path_new=
    while [ -n "$__shell_path_rest" ]; do
        __shell_path_dir=${__shell_path_rest%%:*}
        __shell_path_rest=${__shell_path_rest#*:}
        case $__shell_path_dir in
            /*) __shell_path_new=${__shell_path_new:+$__shell_path_new:}$__shell_path_dir ;;
            '') __shell_path_warn '' 'empty' ;;
            *) __shell_path_warn "$__shell_path_dir" 'not an absolute path' ;;
        esac
    done
    PATH=$__shell_path_new
    unset __shell_path_rest __shell_path_new __shell_path_dir
}

# Remove every "$1" entry, with or without a trailing "/", from PATH. Other entries are
# kept as they are.
__shell_path_remove() {
    __shell_path_new=":${PATH-}:"
    while :; do
        case $__shell_path_new in
            *":$1:"*) __shell_path_new=${__shell_path_new%%":$1:"*}:${__shell_path_new#*":$1:"} ;;
            *":$1/:"*) __shell_path_new=${__shell_path_new%%":$1/:"*}:${__shell_path_new#*":$1/:"} ;;
            *) break ;;
        esac
    done
    __shell_path_new=${__shell_path_new#:}
    PATH=${__shell_path_new%:}
    unset __shell_path_new
}

# Put "$1" first in PATH, moving it there if it is already present.
__shell_path_prepend() {
    __shell_path_valid "${1-}" || return
    set -- "${1%"${1##*[!/]}"}"
    set -- "${1:-/}"
    case ":${PATH-}:" in
        *":$1:"* | *":$1/:"*) __shell_path_remove "$1" ;;
    esac
    PATH=$1${PATH:+:$PATH}
}

# Add "$1" last in PATH, unless it is already present anywhere.
# A caller may not use it (~/.profile only prepends today), so SC2329 is off for it.
# shellcheck disable=SC2329
__shell_path_append() {
    __shell_path_valid "${1-}" || return
    set -- "${1%"${1##*[!/]}"}"
    set -- "${1:-/}"
    case ":${PATH-}:" in
        *":$1:"* | *":$1/:"*) ;;
        *) PATH=${PATH:+$PATH:}$1 ;;
    esac
}
