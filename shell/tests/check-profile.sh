#!/usr/bin/env bash
# Checks a ~/.profile and its environment.d/60-xdg-dirs.conf outside the login path, so a
# mistake fails here instead of in a login: syntax, shellcheck, strict (set -eu)
# interactive and non-interactive logins in each POSIX shell, and the same XDG values as
# the systemd user manager.
# Everything runs against a scratch home; the real ~/.profile is only read.

usage() {
    cat <<'EOF'
Usage: check-profile.sh [-h] [--installed | PROFILE CONF]

Without arguments, checks the repo copies (../home/profile and
../home/config/environment.d/60-xdg-dirs.conf), plus path-helpers.sh and its tests next to
this script. --installed checks ~/.profile and ~/.config/environment.d/60-xdg-dirs.conf.
Exits 1 when a check fails.

Requires dash and bash. Uses ksh, shellcheck and the systemd environment-d generator
when they are installed and skips their checks otherwise.
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

src="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
repo_home="$(dirname "$src")/home"
gen=/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator
fails=0
home=

function pass() { printf 'ok    %s\n' "$1"; }
function fail() {
    printf 'FAIL  %s\n' "$1"
    fails=$((fails + 1))
}
function skip() { printf 'skip  %s\n' "$1"; }

# Run "$@" and report it as check "$1"; its output is shown only when it fails.
function check() {
    local name="$1" out
    shift
    if out="$("$@" 2>&1)"; then
        pass "$name"
    else
        fail "$name"
        [[ -z "$out" ]] || printf '%s\n' "$out" | sed 's/^/      /'
    fi
}

# Source the profile like a login of shell "$1" under set -eu, with the minimal
# environment PAM gives a TTY login. "$2" is "i" for an interactive (TTY/ssh) login, or
# "n" for the non-interactive `$SHELL -l -c` a graphical session starts with. Saves the
# resulting environment; any stderr output counts as a failure because the profile only
# writes warnings there, and so does an environment without EDITOR, the sign that the
# profile returned early. Without a terminal, +m keeps dash and ksh quiet about job
# control; bash still warns, so its two job-control lines are dropped.
function strict_login() {
    local sh="$1" mode="$2" err="$home/err.$1.$2" env_out rc=0
    local -a cmd flags=(-eu)
    [[ "$mode" == i ]] && flags=(+m -i -eu)
    case "$sh" in
        bash) cmd=(bash --norc --noprofile "${flags[@]}" -c) ;;
        *) cmd=("$sh" "${flags[@]}" -c) ;;
    esac
    # shellcheck disable=SC2016 # $HOME expands in the login shell, not here
    env_out="$(env -i HOME="$home" USER="$USER" LOGNAME="$USER" TERM=dumb \
        PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="/run/user/$(id -u)" \
        "${cmd[@]}" '. "$HOME/.profile"; env' </dev/null 2>"$err")" || rc=$?
    sed -i -e '/^bash: cannot set terminal process group/d' \
        -e '/^bash: no job control in this shell$/d' "$err"
    if ((rc != 0)) || [[ -s "$err" ]]; then
        cat -- "$err"
        return 1
    fi
    [[ $'\n'"$env_out" == *$'\nEDITOR='* ]] || {
        echo 'EDITOR is not set: the profile returned before setting up the environment'
        return 1
    }
    [[ "$mode" == i ]] && printf '%s\n' "$env_out" >"$home/env.$sh"
    return 0
}

# From the scratch home, so the profile's source-path directives resolve as once installed.
function shellcheck_profile() {
    (cd "$home" && shellcheck --norc -x .profile)
}

# Compare the variables the .conf file sets with what the systemd generator gives the
# desktop for the same scratch home.
function desktop_parity() {
    local names
    names="$(grep -o '^[A-Za-z_][A-Za-z0-9_]*=' "$home/.config/environment.d/60-xdg-dirs.conf" |
        sed 's/=$//' | sort -u | paste -sd '|')"
    [[ -n "$names" ]] || return 1
    env -i HOME="$home" PATH=/usr/bin:/bin "$gen" | grep -E "^($names)=" | sort >"$home/gen.env"
    grep -E "^($names)=" "$home/env.dash" | sort >"$home/profile.env"
    diff -U0 --label desktop --label profile "$home/gen.env" "$home/profile.env"
}

# The helper block inside the profile must stay identical to path-helpers.sh, minus the
# first line of that file (its "shell=sh" directive).
function helpers_in_sync() {
    local body profile
    body="$(tail -n +2 -- "$1")"
    profile="$(<"$2")"
    [[ "$profile" == *"$body"* ]] || {
        echo "the Script Helper Functions block differs from $1"
        return 1
    }
}

function helper_tests() {
    local out
    out="$("$1" "$src/path-helpers.test.sh" "$src/path-helpers.sh" 2>&1)" || true
    [[ "$(tail -n 1 <<<"$out")" == 'fails=0' ]] || {
        printf '%s\n' "$out"
        return 1
    }
}

function main() {
    local profile conf sh
    case "${1-}" in
        -h | --help)
            usage
            return 0
            ;;
        --installed)
            (($# == 1)) || {
                usage >&2
                return 2
            }
            profile="$HOME/.profile"
            conf="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/60-xdg-dirs.conf"
            ;;
        '')
            profile="$repo_home/profile"
            conf="$repo_home/config/environment.d/60-xdg-dirs.conf"
            ;;
        *)
            (($# == 2)) || {
                usage >&2
                return 2
            }
            profile="$1"
            conf="$2"
            ;;
    esac
    for sh in dash bash; do
        command -v "$sh" &>/dev/null || {
            echo "missing dependency: $sh" >&2
            return 2
        }
    done
    [[ -r "$profile" && -r "$conf" ]] || {
        echo "cannot read $profile or $conf" >&2
        return 2
    }

    trap 'rm -rf -- "$home" || true' EXIT
    home="$(mktemp -d "${TMPDIR:-/tmp}/check-profile.XXXXXX")"
    mkdir -p -- "$home/.config/environment.d"
    cp -- "$profile" "$home/.profile"
    cp -- "$conf" "$home/.config/environment.d/60-xdg-dirs.conf"

    for sh in dash bash ksh; do
        if command -v "$sh" &>/dev/null; then
            check "$sh -n" "$sh" -n "$home/.profile"
        else
            skip "$sh -n: $sh is not installed"
        fi
    done
    check 'conf: sh -n' dash -n "$home/.config/environment.d/60-xdg-dirs.conf"

    # --norc: the directives in the files have to be enough on their own
    if command -v shellcheck &>/dev/null; then
        check 'shellcheck -x .profile' \
            shellcheck_profile
        check 'shellcheck conf' \
            shellcheck --norc -s sh "$home/.config/environment.d/60-xdg-dirs.conf"
    else
        skip 'shellcheck: not installed'
    fi

    for sh in dash bash ksh; do
        if command -v "$sh" &>/dev/null; then
            check "$sh -i -eu login, no stderr" strict_login "$sh" i
            check "$sh -eu non-interactive login (desktop), no stderr" strict_login "$sh" n
        else
            skip "$sh logins: $sh is not installed"
        fi
    done

    if [[ -x "$gen" && -s "$home/env.dash" ]]; then
        check 'XDG values match the systemd user manager' desktop_parity
    else
        skip 'XDG parity: no systemd generator, or the dash login failed'
    fi

    if [[ -z "${1-}" && -r "$src/path-helpers.sh" && -r "$src/path-helpers.test.sh" ]]; then
        check 'helper block == path-helpers.sh' helpers_in_sync "$src/path-helpers.sh" "$profile"
        for sh in dash bash ksh; do
            if command -v "$sh" &>/dev/null; then
                check "$sh path-helpers.test.sh" helper_tests "$sh"
            fi
        done
    fi

    ((fails == 0)) || {
        echo "$fails check(s) failed"
        return 1
    }
    echo 'all checks passed'
}

main "$@"
