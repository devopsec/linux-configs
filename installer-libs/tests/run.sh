#!/usr/bin/env bash
# Focused contract tests for package batching, family hooks and shared CLI validation.

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
REPO_ROOT="$(realpath -m "$TESTS_DIR/../..")"
CALL_LOG=""
OUTPUT_LOG=""
WORK=""
OVERALL_RESULT=0

function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT

WORK="$(mktemp -d /tmp/linux-configs-installer-test.XXXXXX)"
CALL_LOG="$WORK/package-calls.log"
OUTPUT_LOG="$WORK/output.log"
: > "$CALL_LOG"

NO_COLOR=1
source "$REPO_ROOT/installer-libs/common.sh"

declare -ga INSTALLED_PACKAGES=(present)

# shellcheck disable=SC2329
function apt-get() {
    printf 'apt-get %s\n' "$*" >> "$CALL_LOG"
}

function apt-cache() {
    [[ "${1:-}" == show && ( "${2:-}" == available || "${2:-}" == present ) ]]
}

function dpkg-query() {
    local package="" argument
    for argument in "$@"; do package="$argument"; done
    for argument in "${INSTALLED_PACKAGES[@]}"; do
        if [[ "$argument" == "$package" ]]; then
            printf '%s\n' 'install ok installed'
            return 0
        fi
    done
    printf '%s\n' 'deinstall ok config-files'
    return 1
}

function sudo() {
    printf 'sudo %s\n' "$*" >> "$CALL_LOG"
    "$@"
}

FLATPAK_TEST_LOCATION=""
TEST_MAN_NAME=""

# shellcheck disable=SC2329
function flatpak() {
    local argument
    for argument in "$@"; do
        if [[ "$argument" == --show-location ]]; then
            printf '%s\n' "$FLATPAK_TEST_LOCATION"
            return 0
        fi
    done
    return 0
}

# shellcheck disable=SC2329
function curl() {
    local output_file="" argument
    while (( $# > 0 )); do
        case "$1" in
        --output)
            output_file="$2"
            shift 2
            ;;
        *) shift ;;
        esac
    done
    [[ -n "$output_file" ]] || return 2
    printf '.TH %s 1\n' "$TEST_MAN_NAME" > "$output_file"
}

# shellcheck disable=SC2329
function fake_completion_generator() {
    printf '# %s completion\n' "${3:-unknown}"
}

function assert() {
    local description="$1"
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description"
        OVERALL_RESULT=1
    fi
}

pkg_define test-present apt=present
pkg_define test-available apt=available
pkg_define test-available-alias apt=available
pkg_define test-unavailable apt=unavailable
register_family test-family test-app test-other-app

RESOLVED_INSTALL_MODE=system
SUDO_GRANTED=1
SYS_PKG_MANAGER=""
sys_pkgs_ensure test-present test-available test-available-alias test-unavailable test-unmapped > "$OUTPUT_LOG" 2>&1
assert "package requirements are installed in one apt transaction" grep -Fxq 'apt-get install -y available' "$CALL_LOG"
assert "duplicate package names are batched once" test "$(grep -c '^apt-get install -y available$' "$CALL_LOG")" -eq 1
assert "apt metadata is refreshed once before the batch" test "$(grep -c '^apt-get update -y$' "$CALL_LOG")" -eq 1
assert "unavailable and unmapped requirements are notices" grep -q 'unavailable' "$OUTPUT_LOG"
assert "unmapped requirement is skipped" grep -q "No 'apt' package mapping for requirement 'test-unmapped'" "$OUTPUT_LOG"

: > "$CALL_LOG"
: > "$OUTPUT_LOG"
RESOLVED_INSTALL_MODE=user
SUDO_GRANTED=0
INSTALLED_PACKAGES=()
sys_pkgs_ensure test-available > "$OUTPUT_LOG" 2>&1
assert "no-sudo path reports only missing package names" grep -q 'Missing system packages (not installed without sudo): available' "$OUTPUT_LOG"
assert "no-sudo path never calls apt-get" test ! -s "$CALL_LOG"

family_hook test-family missing_optional_hook
assert "undefined family hooks are optional" test "$?" -eq 0

APPS=()
if setup_install invalid-app > "$OUTPUT_LOG" 2>&1; then
    assert "invalid apps are rejected" false
else
    assert "invalid apps are rejected with status 2" test "$?" -eq 2
fi

APPS=()
if setup_install -sp -sc -im user -cm local test-app test-app > "$OUTPUT_LOG" 2>&1; then
    assert "duplicate apps are rejected" false
else
    assert "duplicate apps are rejected with status 2" test "$?" -eq 2
fi

APPS=()
setup_install -sp -sc -im user -cm local test-other-app
assert "valid app and scope options are accepted" test "${APPS[*]}" = test-other-app

XDG_DATA_HOME="$WORK/user-data"
export XDG_DATA_HOME
RESOLVED_INSTALL_MODE=user
FLATPAK_TEST_LOCATION="$WORK/flatpak/org.example.Test/x86_64/stable/active"
TEST_FLATPAK_NAME="lc-docs-flatpak-$BASHPID"
mkdir -p "$FLATPAK_TEST_LOCATION/files/share/man/man1" \
    "$FLATPAK_TEST_LOCATION/files/share/bash-completion/completions" \
    "$FLATPAK_TEST_LOCATION/files/share/zsh/site-functions" \
    "$FLATPAK_TEST_LOCATION/files/share/fish/completions"
printf 'man page\n' > "$FLATPAK_TEST_LOCATION/files/share/man/man1/$TEST_FLATPAK_NAME.1.gz"
printf 'bash completion\n' > "$FLATPAK_TEST_LOCATION/files/share/bash-completion/completions/$TEST_FLATPAK_NAME"
printf 'zsh completion\n' > "$FLATPAK_TEST_LOCATION/files/share/zsh/site-functions/_$TEST_FLATPAK_NAME"
printf 'fish completion\n' > "$FLATPAK_TEST_LOCATION/files/share/fish/completions/$TEST_FLATPAK_NAME.fish"
DOCS_NAMES[test-flatpak]="$TEST_FLATPAK_NAME"
FLATPAK_APP_ID[test-flatpak]="org.example.Test"
app_pkg_install test-flatpak "$TEST_FLATPAK_NAME" > "$OUTPUT_LOG" 2>&1
assert "Flatpak man pages and completions are copied to user data" \
    test -f "$XDG_DATA_HOME/man/man1/$TEST_FLATPAK_NAME.1.gz" \
        -a -f "$XDG_DATA_HOME/bash-completion/completions/$TEST_FLATPAK_NAME" \
        -a -f "$XDG_DATA_HOME/zsh/site-functions/_$TEST_FLATPAK_NAME" \
        -a -f "$XDG_DATA_HOME/fish/vendor_completions.d/$TEST_FLATPAK_NAME.fish"
assert "Flatpak documentation paths are tracked in an uninstall manifest" \
    grep -q "$XDG_DATA_HOME/man/man1/$TEST_FLATPAK_NAME.1.gz" \
        "$XDG_DATA_HOME/linux-configs/docs/test-flatpak.list"
printf 'foreign page\n' > "$XDG_DATA_HOME/man/man1/foreign-page.1"
docs_uninstall test-flatpak
assert "docs uninstall removes owned files and preserves foreign files" \
    test ! -e "$XDG_DATA_HOME/man/man1/$TEST_FLATPAK_NAME.1.gz" \
        -a ! -e "$XDG_DATA_HOME/bash-completion/completions/$TEST_FLATPAK_NAME" \
        -a ! -e "$XDG_DATA_HOME/zsh/site-functions/_$TEST_FLATPAK_NAME" \
        -a ! -e "$XDG_DATA_HOME/fish/vendor_completions.d/$TEST_FLATPAK_NAME.fish" \
        -a -f "$XDG_DATA_HOME/man/man1/foreign-page.1"

TEST_MAN_NAME="lc-docs-man-$BASHPID"
DOCS_NAMES[test-man-url]="$TEST_MAN_NAME"
DOCS_MAN_URL[test-man-url]="https://example.invalid/$TEST_MAN_NAME.1"
docs_install test-man-url "$TEST_MAN_NAME" bin_pkgmgr
assert "release-binary backend installs a configured man-page fallback" \
    test -f "$XDG_DATA_HOME/man/man1/$TEST_MAN_NAME.1"

TEST_COMPLETION_NAME="lc-docs-completion-$BASHPID"
DOCS_NAMES[test-generator]="$TEST_COMPLETION_NAME"
DOCS_COMPLETION_CMD[test-generator]="fake_completion_generator --shell {shell}"
docs_install test-generator "$TEST_COMPLETION_NAME" sys_pkg_mgr
assert "configured generator creates bash, zsh and fish completions" \
    test -f "$XDG_DATA_HOME/bash-completion/completions/$TEST_COMPLETION_NAME" \
        -a -f "$XDG_DATA_HOME/zsh/site-functions/_$TEST_COMPLETION_NAME" \
        -a -f "$XDG_DATA_HOME/fish/vendor_completions.d/$TEST_COMPLETION_NAME.fish"

DOCS_NAMES[test-system]="lc-docs-system-$BASHPID"
docs_install test-system "${DOCS_NAMES[test-system]}" sys_pkg_mgr
assert "system-package docs without a generator do not create local files" \
    test ! -e "$XDG_DATA_HOME/linux-configs/docs/test-system.list" \
        -a ! -e "$XDG_DATA_HOME/man/man1/${DOCS_NAMES[test-system]}.1"

bash "$REPO_ROOT/install.sh" -h > "$OUTPUT_LOG" 2>&1
assert "root help lists the registered families' apps" grep -q 'fonts vim vimpager nvim nvimgit nvimpager' "$OUTPUT_LOG"

if (( OVERALL_RESULT == 0 )); then
    printf 'All installer library tests passed\n'
else
    printf 'Some installer library tests FAILED\n'
fi
exit "$OVERALL_RESULT"