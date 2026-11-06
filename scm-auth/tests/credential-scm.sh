#!/usr/bin/env bash
#
# Offline integration test for git-credential-scm against a real gnome-keyring on a private
# D-Bus session (dbus-run-session) with a temporary HOME and a throwaway keyring password. It
# never talks to the user's session bus or login keyring. Covers the store/get round trip,
# two-way compatibility with the stock git-credential-libsecret, legacy duplicate removal,
# erase semantics, retag preview vs --apply, tool attribution, bad bus addresses and a
# dismissed unlock prompt.

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
SELF="$TESTS_DIR/$(basename "${BASH_SOURCE[0]}")"
PROJECT_DIR="$TESTS_DIR/../git-credential-scm"
LIBSECRET_HELPER=/usr/bin/git-credential-libsecret
KEYRING_PASSWORD='throwaway-test-keyring-password'
COLLECTION=/org/freedesktop/secrets/collection/login
FAR_FUTURE=4000000000

declare -i OVERALL_RESULT=0
WORK=""
KEYRING_PID=""

function usage() {
    cat <<EOF
usage: ${0##*/} [-h]

Runs git-credential-scm against a private gnome-keyring (dbus-run-session, temp HOME).
Set SCM_BIN=/path/to/git-credential-scm to test a prebuilt binary; otherwise the helper is
built with 'zig build' from $PROJECT_DIR. Skips (exit 0) when dbus-run-session,
gnome-keyring-daemon, secret-tool, busctl or $LIBSECRET_HELPER is missing.
EOF
}

function check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        OVERALL_RESULT=1
    fi
}

function skip() {
    echo "SKIP: $*"
    exit 0
}

# shellcheck disable=SC2329 # invoked by trap
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}

# shellcheck disable=SC2329 # invoked by trap
function stop_keyring() {
    [[ -z "$KEYRING_PID" ]] || kill "$KEYRING_PID" 2>/dev/null || true
}

# ------------------------------------------------------------------ helpers (inner session)

# credential request on stdin: one key=value per argument, then a blank line
function request() {
    printf '%s\n' "$@"
    printf '\n'
}

function scm() {
    "$SCM_BIN" "$@"
}

function libsecret() {
    "$LIBSECRET_HELPER" "$@"
}

# number of items whose attributes include the given attribute/value pairs
function item_count() {
    local n
    n="$(secret-tool search --all "$@" 2>/dev/null | grep -c '^\[' || true)"
    printf '%s\n' "${n:-0}"
}

# attributes of matching items (secret-tool prints them on stderr), one "attribute.k = v" per line
function item_attrs() {
    secret-tool search --all "$@" 2>&1 >/dev/null | grep '^attribute\.' || true
}

# labels of matching items (stdout carries labels and secrets; only labels are kept)
function item_labels() {
    secret-tool search --all "$@" 2>/dev/null | sed -n 's/^label = //p' || true
}

function lookup_secret() {
    secret-tool lookup "$@" 2>/dev/null || true
}

function equals() {
    [[ "$1" == "$2" ]] || {
        printf '  expected: %q\n  actual:   %q\n' "$2" "$1"
        return 1
    }
}

function contains_line() {
    grep -qxF -- "$2" <<<"$1" || {
        printf '  missing line: %q\n' "$2"
        return 1
    }
}

function has() {
    grep -qF -- "$2" <<<"$1"
}

function lacks() {
    ! grep -qF -- "$2" <<<"$1"
}

# matches <text> <extended-regex>
function matches() {
    grep -qE -- "$2" <<<"$1" || {
        printf '  no match for %q in %q\n' "$2" "$1"
        return 1
    }
}

function legacy_item() {
    # legacy_item <label> <secret> <attr> <value>...: an org.git.Password item without tags
    local label="$1" secret="$2"
    shift 2
    printf '%s' "$secret" | secret-tool store --label="$label" xdg:schema org.git.Password "$@"
}

# ------------------------------------------------------------------ scenarios

function test_round_trip() {
    local out
    request protocol=https host=example.test username=alice password=pw-round \
        "password_expiry_utc=$FAR_FUTURE" oauth_refresh_token=rt-round | scm store
    out="$(request protocol=https host=example.test | scm get)"
    check "round trip: get returns what store wrote" equals "$out" \
        "$(printf 'username=alice\npassword=pw-round\npassword_expiry_utc=%s\noauth_refresh_token=rt-round' "$FAR_FUTURE")"
    out="$(item_attrs server example.test)"
    check "round trip: item tagged application=scm-auth" contains_line "$out" 'attribute.application = scm-auth'
    check "round trip: item tagged tool=git" contains_line "$out" 'attribute.tool = git'
    check "round trip: stock attributes kept" contains_line "$out" 'attribute.user = alice'
    check "round trip: label" equals "$(item_labels server example.test)" 'scm-auth: https://example.test/'
    check "round trip: schema org.git.Password" equals \
        "$(secret-tool search --all server example.test 2>/dev/null | sed -n 's/^schema = //p')" 'org.git.Password'
    out="$(request protocol=https host=nothing.test | scm get)"
    check "get without a match prints nothing" equals "$out" ''
}

function test_git_invocation() {
    local out
    command -v git &>/dev/null || {
        echo "SKIP: git not found (git credential fill)"
        return 0
    }
    out="$(request protocol=https host=example.test |
        GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c "credential.helper=$SCM_BIN --tool=git" credential fill)"
    check "git credential fill through the helper" contains_line "$out" 'password=pw-round'
}

function test_compat() {
    local out
    request protocol=https host=compat1.test username=bob password=pw-from-libsecret | libsecret store >/dev/null
    out="$(request protocol=https host=compat1.test | scm get)"
    check "libsecret store -> scm get" equals "$out" $'username=bob\npassword=pw-from-libsecret'

    request protocol=https host=compat2.test username=carol password=pw-from-scm \
        "password_expiry_utc=$FAR_FUTURE" oauth_refresh_token=rt-scm | scm store
    out="$(request protocol=https host=compat2.test | libsecret get)"
    check "scm store -> libsecret get: password" contains_line "$out" 'password=pw-from-scm'
    check "scm store -> libsecret get: username" contains_line "$out" 'username=carol'
    check "scm store -> libsecret get: expiry" contains_line "$out" "password_expiry_utc=$FAR_FUTURE"
    check "scm store -> libsecret get: refresh token" contains_line "$out" 'oauth_refresh_token=rt-scm'
}

function test_store_replaces_legacy() {
    request protocol=https host=dup.test username=dave password=old-legacy | libsecret store >/dev/null
    legacy_item 'Git: https://dup.test/o/r.git' other-object protocol https server dup.test user dave object o/r.git
    request protocol=https host=dup.test username=dave password=new-scm | scm store
    check "store over a legacy item: tagged item plus the other-object item remain" equals \
        "$(item_count server dup.test)" 2
    check "store over a legacy item: exactly one tagged item" equals \
        "$(item_count server dup.test user dave application scm-auth)" 1
    check "store over a legacy item: no untagged duplicate" equals \
        "$(item_labels server dup.test user dave | grep -c '^Git: https://dup.test/$' || true)" 0
    check "store keeps items with other stock attributes" equals \
        "$(lookup_secret server dup.test object o/r.git)" other-object
    check "store over a legacy item: new secret" equals \
        "$(request protocol=https host=dup.test username=dave | scm get)" $'username=dave\npassword=new-scm'
}

function test_erase() {
    request protocol=https host=erase.test username=erin password=right | scm store
    request protocol=https host=erase.test username=erin password=wrong | scm erase
    check "erase with a non-matching password keeps the item" equals "$(item_count server erase.test)" 1
    request protocol=https host=erase.test username=erin password=right | scm erase
    check "erase with the matching password removes the item" equals "$(item_count server erase.test)" 0

    request protocol=https host=erase2.test username=erin password=a | libsecret store >/dev/null
    request protocol=https host=erase2.test username=erin password=b | scm store
    legacy_item 'Git: https://erase2.test/' c protocol https server erase2.test user erin mark 1
    request protocol=https host=erase2.test | scm erase
    check "erase without a password removes legacy and tagged items" equals "$(item_count server erase2.test)" 0
}

function test_tool() {
    request protocol=https host=tool.test username=frank password=t | scm --tool=forge store
    check "--tool=forge recorded on store" contains_line "$(item_attrs server tool.test)" 'attribute.tool = forge'
}

function test_list() {
    local out
    out="$(scm list)"
    check "list prints tagged items" contains_line "$(cut -f2 <<<"$out")" 'scm-auth: https://example.test/'
    check "list never prints secrets" lacks "$out" 'pw-'
    check "list omits untagged items" lacks "$out" 'compat1.test'
    out="$(scm --all list)"
    check "list --all includes legacy items" has "$out" 'Git: https://compat1.test/'
}

function test_retag() {
    local before after out
    legacy_item 'Git: https://retag.test/' dup-old protocol https server retag.test user gina mark 1
    sleep 1.1
    legacy_item 'Git: https://retag.test/' dup-new protocol https server retag.test user gina mark 2
    legacy_item 'forge: forge.test' forge-secret protocol https server forge.test user hank

    before="$(secret-tool search --all xdg:schema org.git.Password 2>&1 | grep -v '^secret = ' || true)"
    out="$(scm retag)"
    after="$(secret-tool search --all xdg:schema org.git.Password 2>&1 | grep -v '^secret = ' || true)"
    check "retag preview changes nothing" equals "$after" "$before"
    check "retag preview lists the forge item" contains_line "$out" \
        'retag   forge: forge.test -> scm-auth: https://forge.test/ (tool=forge)'
    check "retag preview lists the older duplicate" contains_line "$out" \
        'delete  Git: https://retag.test/ (older duplicate of scm-auth: https://retag.test/)'
    check "retag preview says so" matches "$(tail -n 1 <<<"$out")" '\(preview; run with --apply to change\)$'
    check "retag preview never prints secrets" lacks "$out" 'dup-'

    scm --apply retag >/dev/null
    check "retag --apply collapses duplicates" equals "$(item_count server retag.test)" 1
    check "retag --apply keeps the newest duplicate" equals "$(lookup_secret server retag.test)" dup-new
    check "retag --apply labels items" equals "$(item_labels server retag.test)" 'scm-auth: https://retag.test/'
    check "retag --apply gives forge items tool=forge" contains_line "$(item_attrs server forge.test)" \
        'attribute.tool = forge'
    check "retag --apply relabels forge items" equals "$(item_labels server forge.test)" 'scm-auth: https://forge.test/'
    check "retag --apply tags every org.git.Password item" equals \
        "$(item_count xdg:schema org.git.Password)" "$(item_count xdg:schema org.git.Password application scm-auth)"
    check "retag --apply leaves the libsecret item readable" equals \
        "$(request protocol=https host=compat1.test | libsecret get | grep -c '^password=pw-from-libsecret$' || true)" 1
    out="$(scm retag)"
    check "retag is idempotent" matches "$(tail -n 1 <<<"$out")" '^retag: 0 to update, 0 duplicate\(s\) to delete, '
}

function test_bad_bus() {
    local out rc
    rc=0
    out="$(request protocol=https host=example.test | env -u DBUS_SESSION_BUS_ADDRESS "$SCM_BIN" get 2>"$WORK/err")" || rc=$?
    check "unset bus address: non-zero exit" test "$rc" -ne 0
    check "unset bus address: no stdout" equals "$out" ''
    check "unset bus address: one stderr line" equals "$(wc -l <"$WORK/err")" 1
    # without DBUS_SESSION_BUS_ADDRESS the helper falls back to $XDG_RUNTIME_DIR/bus (cron, daemons)
    if [[ "$DBUS_SESSION_BUS_ADDRESS" =~ ^unix:path=([^,\;]+) ]]; then
        mkdir -p "$WORK/fallback-runtime"
        ln -sfn "${BASH_REMATCH[1]}" "$WORK/fallback-runtime/bus"
        rc=0
        out="$(request protocol=https host=example.test | env -u DBUS_SESSION_BUS_ADDRESS \
            XDG_RUNTIME_DIR="$WORK/fallback-runtime" "$SCM_BIN" get 2>"$WORK/err")" || rc=$?
        check "unset bus address: XDG_RUNTIME_DIR/bus fallback works" test "$rc" -eq 0
    fi
    rc=0
    out="$(request protocol=https host=example.test |
        DBUS_SESSION_BUS_ADDRESS=unix:abstract=/tmp/dbus-nope "$SCM_BIN" get 2>"$WORK/err")" || rc=$?
    check "unix:abstract address: non-zero exit" test "$rc" -ne 0
    check "unix:abstract address: no stdout" equals "$out" ''
    check "unix:abstract address: clear error" grep -q 'unsupported D-Bus address' "$WORK/err"
}

function test_locked_without_prompter() {
    local out rc
    busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.Secret.Service \
        Lock ao 1 "$COLLECTION" >/dev/null
    rc=0
    out="$(request protocol=https host=example.test | timeout 30 "$SCM_BIN" get 2>"$WORK/err")" || rc=$?
    check "locked collection, no prompter: non-zero exit" test "$rc" -ne 0
    check "locked collection, no prompter: no stdout" equals "$out" ''
    check "locked collection, no prompter: prompt dismissed" grep -q 'keyring prompt dismissed' "$WORK/err"
}

function inner_main() {
    local uid i
    uid="$(id -u)"
    # Hard guards: never the user's session bus, never the real HOME.
    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" || "$DBUS_SESSION_BUS_ADDRESS" == *"/run/user/$uid/bus"* ]]; then
        echo "FAIL: refusing to run on the user's session bus" >&2
        return 1
    fi
    WORK="${SCM_TEST_WORK:-}"
    if [[ "$HOME" != /tmp/* || "${XDG_RUNTIME_DIR:-}" != /tmp/* || "$WORK" != /tmp/* ]]; then
        echo "FAIL: HOME, XDG_RUNTIME_DIR and the work dir must be temporary" >&2
        return 1
    fi
    trap stop_keyring EXIT
    printf '%s' "$KEYRING_PASSWORD" | gnome-keyring-daemon --unlock --components=secrets >/dev/null
    for ((i = 0; i < 100; i++)); do
        busctl --user status org.freedesktop.secrets >/dev/null 2>&1 && break
        sleep 0.1
    done
    KEYRING_PID="$(busctl --user status org.freedesktop.secrets 2>/dev/null | sed -n 's/^PID=//p')"
    [[ -n "$KEYRING_PID" ]] || {
        echo "FAIL: gnome-keyring-daemon did not start" >&2
        return 1
    }

    test_round_trip
    test_git_invocation
    test_compat
    test_store_replaces_legacy
    test_erase
    test_tool
    test_list
    test_retag
    test_bad_bus
    test_locked_without_prompter
    return "$OVERALL_RESULT"
}

function main() {
    local tool
    case "${1:-}" in
        -h | --help)
            usage
            return 0
            ;;
        --inner)
            inner_main
            return
            ;;
        "") ;;
        *)
            usage >&2
            return 2
            ;;
    esac
    for tool in dbus-run-session gnome-keyring-daemon secret-tool busctl; do
        command -v "$tool" &>/dev/null || skip "missing dependency: $tool"
    done
    [[ -x "$LIBSECRET_HELPER" ]] || skip "missing $LIBSECRET_HELPER"

    trap cleanup EXIT
    WORK="$(mktemp -d /tmp/linux-configs-scm-credential-test.XXXXXX)"
    if [[ -z "${SCM_BIN:-}" ]]; then
        command -v zig &>/dev/null || skip "zig not found and SCM_BIN not set"
        # Built with the real HOME so the zig cache stays warm.
        env -C "$PROJECT_DIR" zig build --prefix "$WORK/zig-out" >"$WORK/build.log" 2>&1 || {
            echo "FAIL: zig build failed (see below)"
            cat "$WORK/build.log"
            return 1
        }
        SCM_BIN="$WORK/zig-out/bin/git-credential-scm"
    fi
    [[ -x "$SCM_BIN" ]] || {
        echo "FAIL: SCM_BIN is not executable: $SCM_BIN"
        return 1
    }
    SCM_BIN="$(realpath -m "$SCM_BIN")"
    mkdir -p "$WORK"/{home,data,config,cache,runtime}
    chmod 700 "$WORK/runtime"
    env -u GNOME_KEYRING_CONTROL -u SSH_AUTH_SOCK -u DISPLAY -u WAYLAND_DISPLAY \
        -u DBUS_SESSION_BUS_ADDRESS -u SCM_AUTH_ALLOW_PLAIN_SESSION \
        HOME="$WORK/home" XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/config" \
        XDG_CACHE_HOME="$WORK/cache" XDG_RUNTIME_DIR="$WORK/runtime" \
        SCM_BIN="$SCM_BIN" SCM_TEST_WORK="$WORK" \
        dbus-run-session -- bash "$SELF" --inner 2> >(grep -v -e 'Activat' -e 'gcr-prompter' -e '^$' >&2)
}

main "$@"
