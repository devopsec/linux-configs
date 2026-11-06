#!/usr/bin/env bash
#
# Offline test for the scm-auth family installer: runs scm-auth/install.sh in a temporary HOME
# (no network, no sudo, never the real HOME) and asserts the SSH drop-in, the Include line in
# ~/.ssh/config, idempotency, preservation of user content, clean (-cc) handling and the
# git-credential-scm build (stub zig: version check, source stamp, rebuilds, failures, clean).

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
INSTALLER="$TESTS_DIR/../install.sh"
ROOT_INSTALLER="$TESTS_DIR/../../install.sh"
DROP_IN_SRC="$TESTS_DIR/../ssh/config.d/10-scm-auth.conf"
INCLUDE_LINE='Include ~/.ssh/config.d/*.conf'
ZIG_DIR="$TESTS_DIR/fixtures"
HELPER_SRC="$TESTS_DIR/../git-credential-scm"

declare -i OVERALL_RESULT=0
WORK=""
# shellcheck disable=SC2329
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
WORK="$(mktemp -d /tmp/linux-configs-scm-auth-test.XXXXXX)"
TEST_HOME="$WORK/home"
SSH_CONFIG="$TEST_HOME/.ssh/config"
DROP_IN="$TEST_HOME/.ssh/config.d/10-scm-auth.conf"
# the stamp and zig cache must never land in the real cache dir
export XDG_CACHE_HOME="$WORK/cache"
export ZIG_STUB_LOG="$WORK/zig.log"
unset ZIG_STUB_VERSION ZIG_STUB_FAIL SCM_AUTH_HELPER_SRC_DIR
CACHE_DIR="$XDG_CACHE_HOME/scm-auth"

# per-destination stamp, as scm_auth_helper_stamp names it: sha256 of the destination path
function stamp_path() {
    printf '%s/stamps/%s.sha256\n' "$CACHE_DIR" "$(printf '%s' "$1" | sha256sum | cut -d ' ' -f 1)"
}

# scratch dir of the first zig build in the stub log (its --prefix is <scratch>/prefix); callers
# reset ZIG_STUB_LOG before the run they inspect, so it is that run's build
function zig_scratch_dir() {
    grep -oE -- '--prefix [^ ]+' "$ZIG_STUB_LOG" 2>/dev/null | head -n 1 | cut -d ' ' -f 2 | sed 's|/prefix$||'
}

# runs the installer for user mode in an arbitrary home (shared XDG cache, same zig stub)
function run_installer_in() {
    local home_dir="$1"
    shift
    PATH="$ZIG_DIR:$WORK/bin:$PATH" HOME="$home_dir" bash "$INSTALLER" -im user -cm local "$@" scm-auth > "$WORK/out.log" 2>&1
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

function run_installer() {
    PATH="$ZIG_DIR:$WORK/bin:$PATH" HOME="$TEST_HOME" bash "$INSTALLER" -im user -cm local "$@" scm-auth > "$WORK/out.log" 2>&1
}

# number of 'zig build' calls logged by the stub
function zig_builds() {
    grep -c ' build ' "$ZIG_STUB_LOG" 2>/dev/null || true
}

# runs only the clean hook, as -cc would before reinstalling
function run_clean_hook() {
    HOME="$TEST_HOME" bash -c 'source "$1"; scm_auth_clean_home "$2" 0' _ "$INSTALLER" "$TEST_HOME" > "$WORK/out.log" 2>&1
}

function include_count() {
    grep -cxF -- "$INCLUDE_LINE" "$SSH_CONFIG" || true
}

# shellcheck disable=SC2329 # invoked indirectly through check
function first_line_is_include() {
    [[ "$(head -n 1 "$SSH_CONFIG")" == "$INCLUDE_LINE" ]]
}

function mode_of() {
    stat -c '%a' "$1"
}

mkdir -p "$TEST_HOME" "$WORK/bin"
printf '#!/usr/bin/env bash\nprintf "install ok installed\\n"\n' > "$WORK/bin/dpkg-query"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/apt-cache"
# session-state tools must never be called by the installer: the stubs log their argv
STUB_LOG="$WORK/stub.log"
for tool in systemctl secret-tool; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s"\n' "$tool" "$STUB_LOG" > "$WORK/bin/$tool"
done
chmod +x "$WORK/bin/dpkg-query" "$WORK/bin/apt-cache" "$WORK/bin/systemctl" "$WORK/bin/secret-tool"
: > "$STUB_LOG"
BIN_DIR="$TEST_HOME/.local/bin"

# runs clean_home + configure_home + post_install for <config-mode> against <target-home>,
# as configure_apps would (users/global need root, so the hooks are driven directly)
function run_hooks_in_mode() {
    PATH="$ZIG_DIR:$WORK/bin:$PATH" HOME="$TEST_HOME" bash -c '
        source "$1"
        RESOLVED_INSTALL_MODE=user RESOLVED_CONFIG_MODE="$2"
        for hook in clean_global configure_global; do family_hook scm-auth "$hook"; done
        family_hook scm-auth clean_home "$3" 0
        family_hook scm-auth configure_home "$3" 0
        family_hook scm-auth post_install
    ' _ "$INSTALLER" "$1" "$2" > "$WORK/out.log" 2>&1
}

# drop-in contract
check "drop-in matches the scm tag on the final pass" grep -qx 'Match final tagged scm' "$DROP_IN_SRC"
check "drop-in sets no IdentityAgent" test -z "$(grep -iE '^[[:space:]]*IdentityAgent' "$DROP_IN_SRC" || true)"
for option in 'IdentitiesOnly yes' 'AddKeysToAgent no' 'GSSAPIAuthentication no' 'PreferredAuthentications publickey' 'BatchMode yes'; do
    check "drop-in sets '$option'" grep -qE "^[[:space:]]+$option\$" "$DROP_IN_SRC"
done

# fresh HOME: config created 0600 with only the Include, drop-in installed
run_installer
check "fresh install exits 0" test $? -eq 0
check "drop-in installed" cmp -s "$DROP_IN_SRC" "$DROP_IN"
check "drop-in mode is 0644" test "$(mode_of "$DROP_IN")" = 644
check "HOME/.ssh mode is 0700" test "$(mode_of "$TEST_HOME/.ssh")" = 700
check "HOME/.ssh/config created with mode 0600" test "$(mode_of "$SSH_CONFIG")" = 600
check "HOME/.ssh/config holds only the Include line" test "$(cat "$SSH_CONFIG")" = "$INCLUDE_LINE"
for script in scm-auth-migrate scm-auth-status; do
    check "$script installed to the scoped bin dir" cmp -s "$TESTS_DIR/../bin/$script" "$BIN_DIR/$script"
    check "$script mode is 0755" test "$(mode_of "$BIN_DIR/$script")" = 755
done
check "local install hints at scm-auth-migrate --apply" grep -q "scm-auth-migrate --apply" "$WORK/out.log"
HELPER="$BIN_DIR/git-credential-scm"
STAMP="$(stamp_path "$HELPER")"
check "git-credential-scm built and installed" grep -qx 'fake git-credential-scm get' <("$HELPER" get 2>/dev/null)
check "git-credential-scm mode is 0755" test "$(mode_of "$HELPER")" = 755
check "no staged .new copy left" test ! -e "$HELPER.new"
check "zig build ran once" test "$(zig_builds)" -eq 1
check "zig build: ReleaseSafe, scratch prefix, cache under XDG_CACHE_HOME, from the source dir" \
    grep -qE "^$(realpath "$HELPER_SRC") build -Doptimize=ReleaseSafe --prefix /tmp/linux-configs-scm-auth-build\.[^ ]+/prefix --cache-dir $CACHE_DIR/zig\$" "$ZIG_STUB_LOG"
scratch_dir="$(zig_scratch_dir)"
check "zig scratch dir removed (from the stub log)" bash -c '[[ -n "$1" && ! -e "$1" ]]' _ "$scratch_dir"
check "source stamp written: '<source hash> <binary sha256>'" grep -qxE '[0-9a-f]{64} [0-9a-f]{64}' "$(stamp_path "$HELPER")"
check "install never calls systemctl or secret-tool" test ! -s "$STUB_LOG"

# idempotency: nothing rewritten
CONFIG_MTIME="$(stat -c '%y' "$SSH_CONFIG")"
DROP_IN_MTIME="$(stat -c '%y' "$DROP_IN")"
MIGRATE_MTIME="$(stat -c '%y' "$BIN_DIR/scm-auth-migrate")"
run_installer
check "second run exits 0" test $? -eq 0
check "second run keeps a single Include" test "$(include_count)" -eq 1
check "second run leaves HOME/.ssh/config untouched" test "$(stat -c '%y' "$SSH_CONFIG")" = "$CONFIG_MTIME"
check "second run leaves the drop-in untouched" test "$(stat -c '%y' "$DROP_IN")" = "$DROP_IN_MTIME"
check "second run leaves the helpers untouched" test "$(stat -c '%y' "$BIN_DIR/scm-auth-migrate")" = "$MIGRATE_MTIME"
check "second run reports up-to-date files" grep -q 'already includes the scm-auth drop-ins' "$WORK/out.log"
check "second run: no rebuild (stamp matches)" test "$(zig_builds)" -eq 1
check "second run: helper reported up to date" grep -qF "'$HELPER' is up to date (sources and installed binary unchanged)" "$WORK/out.log"

# existing user config: Include prepended, misplaced/duplicate Include moved, content and mode kept
cat > "$SSH_CONFIG" <<'EOF'
Host github.com
    Tag scm
    IdentityFile ~/.ssh/github_ed25519
  Include ~/.ssh/config.d/*.conf

Host *
    ServerAliveInterval 30
EOF
chmod 0640 "$SSH_CONFIG"
grep -vxF '  Include ~/.ssh/config.d/*.conf' "$SSH_CONFIG" > "$WORK/user-content"
run_installer
check "existing config: Include is the first line" first_line_is_include
check "existing config: exactly one Include" test "$(include_count)" -eq 1
check "existing config: user content preserved in order" diff -q <(tail -n +2 "$SSH_CONFIG") "$WORK/user-content"
check "existing config: file mode preserved" test "$(mode_of "$SSH_CONFIG")" = 640
run_installer
check "existing config: re-run keeps one Include" test "$(include_count)" -eq 1

# ssh resolves the tagged host through the drop-in (ssh expands '~' from the passwd entry,
# so point a copy of the config at the test drop-in directly)
if command -v ssh >/dev/null; then
    sed "s|^Include ~/.ssh/config.d/\\*.conf\$|Include $TEST_HOME/.ssh/config.d/*.conf|" "$SSH_CONFIG" > "$WORK/ssh-config"
    ssh -G -F "$WORK/ssh-config" github.com > "$WORK/ssh-g.github" 2>/dev/null
    ssh -G -F "$WORK/ssh-config" example.org > "$WORK/ssh-g.other" 2>/dev/null
    check "ssh -G: tagged host gets IdentitiesOnly yes" grep -qx 'identitiesonly yes' "$WORK/ssh-g.github"
    check "ssh -G: tagged host gets BatchMode yes" grep -qx 'batchmode yes' "$WORK/ssh-g.github"
    check "ssh -G: tagged host has no IdentityAgent" test -z "$(grep -i '^identityagent' "$WORK/ssh-g.github" || true)"
    check "ssh -G: untagged host is unaffected" grep -qx 'batchmode no' "$WORK/ssh-g.other"
else
    echo "SKIP: ssh not installed; ssh -G resolution checks skipped"
fi

# -cc: clean then reinstall; user content and foreign drop-ins survive
echo 'Host foreign' > "$TEST_HOME/.ssh/config.d/90-foreign.conf"
echo 'stale' > "$DROP_IN"
run_installer -cc
check "-cc exits 0" test $? -eq 0
check "-cc reinstalls the drop-in" cmp -s "$DROP_IN_SRC" "$DROP_IN"
check "-cc keeps foreign drop-ins" test -f "$TEST_HOME/.ssh/config.d/90-foreign.conf"
check "-cc keeps one Include" test "$(include_count)" -eq 1
check "-cc keeps the Include as first line" first_line_is_include
check "-cc preserves user content" diff -q <(tail -n +2 "$SSH_CONFIG") "$WORK/user-content"
check "-cc reinstalls the helpers" test -x "$BIN_DIR/scm-auth-migrate" -a -x "$BIN_DIR/scm-auth-status"
BUILDS_BEFORE="$(zig_builds)"
check "-cc never calls systemctl or secret-tool" test ! -s "$STUB_LOG"

# clean hook alone: drop-in and Include removed, everything else kept
run_clean_hook
check "clean removes the drop-in" test ! -e "$DROP_IN"
check "clean removes the helpers" test ! -e "$BIN_DIR/scm-auth-migrate" -a ! -e "$BIN_DIR/scm-auth-status"
check "clean removes git-credential-scm" test ! -e "$HELPER"
check "clean removes the source stamp" test ! -e "$STAMP"
check "clean removes the zig build cache" test ! -e "$CACHE_DIR/zig"
check "clean removes the empty scm-auth cache dir" test ! -e "$CACHE_DIR"
check "clean keeps foreign drop-ins" test -f "$TEST_HOME/.ssh/config.d/90-foreign.conf"
check "clean removes the Include line" test "$(include_count)" -eq 0
check "clean preserves user content exactly" diff -q "$SSH_CONFIG" "$WORK/user-content"
rm -f "$TEST_HOME/.ssh/config.d/90-foreign.conf"
run_clean_hook
check "clean removes an empty config.d" test ! -e "$TEST_HOME/.ssh/config.d"
check "clean is a no-op when nothing is installed" diff -q "$SSH_CONFIG" "$WORK/user-content"

# users/global config modes: no session-state tools, no migrate hint
for mode in users global; do
    : > "$STUB_LOG"
    mkdir -p "$WORK/skel-$mode"
    run_hooks_in_mode "$mode" "$WORK/skel-$mode"
    check "$mode mode: hooks exit 0" test $? -eq 0
    check "$mode mode: no systemctl/secret-tool calls" test ! -s "$STUB_LOG"
    check "$mode mode: no migrate hint" bash -c '! grep -qF -- "scm-auth-migrate --apply" "$1"' _ "$WORK/out.log"
    check "$mode mode: drop-in installed into the target home" test -f "$WORK/skel-$mode/.ssh/config.d/10-scm-auth.conf"
    check "$mode mode: git include installed into the target home" test -f "$WORK/skel-$mode/.config/git/scm-auth.gitconfig"
    check "$mode mode: target ~/.gitconfig includes it" grep -qF 'path = ~/.config/git/scm-auth.gitconfig' "$WORK/skel-$mode/.gitconfig"
done

# ---------------------------------------------------------------- git-credential-scm build
# -cc rebuilt the helper from a clean cache (clean ran before configure)
check "-cc rebuilt the helper" test "$BUILDS_BEFORE" -ge 2
run_clean_hook
: > "$ZIG_STUB_LOG"
run_installer
check "reinstall after clean builds again" test "$(zig_builds)" -eq 1 -a -x "$HELPER"

# a missing binary is rebuilt even with a matching stamp
rm -f "$HELPER"
run_installer
check "missing binary: rebuilt" test "$(zig_builds)" -eq 2 -a -x "$HELPER"

# identical sources elsewhere hash the same (relative names), a changed source rebuilds
SRC_COPY="$WORK/src-copy"
mkdir -p "$SRC_COPY"
cp -r "$HELPER_SRC/build.zig" "$HELPER_SRC/build.zig.zon" "$HELPER_SRC/src" "$SRC_COPY/"
SCM_AUTH_HELPER_SRC_DIR="$SRC_COPY" run_installer
check "copied sources: same stamp, no rebuild" test "$(zig_builds)" -eq 2
STAMP_BEFORE="$(cat "$STAMP")"
printf '\n// changed\n' >> "$SRC_COPY/src/main.zig"
SCM_AUTH_HELPER_SRC_DIR="$SRC_COPY" run_installer
check "changed source: rebuilt" test "$(zig_builds)" -eq 3
check "changed source: built in the overridden source dir" grep -qE "^$SRC_COPY build " "$ZIG_STUB_LOG"
check "changed source: stamp updated" test "$(cat "$STAMP")" != "$STAMP_BEFORE"
printf 'x\n' > "$SRC_COPY/src/new-file.txt"
SCM_AUTH_HELPER_SRC_DIR="$SRC_COPY" run_installer
check "non-zig file: no rebuild" test "$(zig_builds)" -eq 3
# a zig upgrade within the series rebuilds
ZIG_STUB_VERSION=0.17.1 run_installer
check "zig 0.17.1: rebuilt" test "$(zig_builds)" -eq 4
run_installer
check "back on 0.17.0: rebuilt" test "$(zig_builds)" -eq 5

# failures never leave a partial binary and exit non-zero
FAIL_HOME="$WORK/fail-home"
FAIL_BIN="$FAIL_HOME/.local/bin"
function run_fail_installer() {
    local path="$1"
    shift
    rm -rf -- "$FAIL_HOME" "$WORK/fail-cache"
    mkdir -p "$FAIL_HOME"
    : > "$ZIG_STUB_LOG"
    env "$@" PATH="$path" HOME="$FAIL_HOME" XDG_CACHE_HOME="$WORK/fail-cache" \
        bash "$INSTALLER" -im user -cm local scm-auth > "$WORK/out.log" 2>&1
}
run_fail_installer "$WORK/bin:/usr/bin:/bin" && rc=0 || rc=$?
check "zig missing: exits non-zero" test "$rc" -ne 0
check "zig missing: clear error" grep -qF "'zig' 0.17.x is required to build git-credential-scm but is not on PATH" "$WORK/out.log"
check "zig missing: no binary" test ! -e "$FAIL_BIN/git-credential-scm" -a ! -e "$FAIL_BIN/git-credential-scm.new"
run_fail_installer "$ZIG_DIR:$WORK/bin:/usr/bin:/bin" ZIG_STUB_VERSION=0.16.0 && rc=0 || rc=$?
check "zig 0.16: exits non-zero" test "$rc" -ne 0
check "zig 0.16: clear error" grep -qF "git-credential-scm needs zig 0.17.x, found '0.16.0'" "$WORK/out.log"
check "zig 0.16: never builds" test "$(zig_builds)" -eq 0
check "zig 0.16: no binary" test ! -e "$FAIL_BIN/git-credential-scm"
run_fail_installer "$ZIG_DIR:$WORK/bin:/usr/bin:/bin" ZIG_STUB_VERSION=0.170.0 && rc=0 || rc=$?
check "zig 0.170: wrong series refused" test "$rc" -ne 0 -a ! -e "$FAIL_BIN/git-credential-scm"
run_fail_installer "$ZIG_DIR:$WORK/bin:/usr/bin:/bin" ZIG_STUB_FAIL=1 && rc=0 || rc=$?
check "build failure: exits non-zero" test "$rc" -ne 0
check "build failure: reported" grep -qF 'zig build of git-credential-scm failed' "$WORK/out.log"
check "build failure: no binary, no staged copy" test ! -e "$FAIL_BIN/git-credential-scm" -a ! -e "$FAIL_BIN/git-credential-scm.new"
check "build failure: no stamp written" test ! -e "$WORK/fail-cache/scm-auth/stamps"
# a failed rebuild keeps the previously installed binary
printf '\n// changed again\n' >> "$SRC_COPY/src/main.zig"
cp "$HELPER" "$WORK/helper-before"
ZIG_STUB_FAIL=1 SCM_AUTH_HELPER_SRC_DIR="$SRC_COPY" run_installer && rc=0 || rc=$?
check "failed rebuild: exits non-zero" test "$rc" -ne 0
check "failed rebuild: previous binary kept" cmp -s "$HELPER" "$WORK/helper-before"
rm -rf -- "$WORK/fail-home" "$WORK/fail-cache"

# users mode with -cc semantics: helper cleaned and built once although several homes are visited
: > "$ZIG_STUB_LOG"
mkdir -p "$WORK/skel-a" "$WORK/skel-b"
PATH="$ZIG_DIR:$WORK/bin:$PATH" HOME="$TEST_HOME" bash -c '
    source "$1"
    RESOLVED_INSTALL_MODE=user RESOLVED_CONFIG_MODE=users
    for target in "$2" "$3"; do
        family_hook scm-auth clean_home "$target" 0
        family_hook scm-auth configure_home "$target" 0
    done
' _ "$INSTALLER" "$WORK/skel-a" "$WORK/skel-b" > "$WORK/out.log" 2>&1
check "several homes: hooks exit 0" test $? -eq 0
check "several homes: built exactly once" test "$(zig_builds)" -eq 1 -a -x "$HELPER"

# two destinations sharing one zig cache: a rebuild for home B must never make home A look up to date
HOME_A="$WORK/home-a"
HOME_B="$WORK/home-b"
BIN_A="$HOME_A/.local/bin/git-credential-scm"
BIN_B="$HOME_B/.local/bin/git-credential-scm"
TWO_SRC="$WORK/two-src"
mkdir -p "$HOME_A" "$HOME_B" "$TWO_SRC"
cp -r "$HELPER_SRC/build.zig" "$HELPER_SRC/build.zig.zon" "$HELPER_SRC/src" "$TWO_SRC/"
: > "$ZIG_STUB_LOG"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_A"
check "two destinations: home A built once" test "$(zig_builds)" -eq 1 -a -x "$BIN_A"
printf '\n// edited for home B\n' >> "$TWO_SRC/src/main.zig"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_B"
check "two destinations: home B rebuilt with the edited sources" test "$(zig_builds)" -eq 2 -a -x "$BIN_B"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_A"
check "two destinations: home A rebuilt (not reported up to date after B's build)" test "$(zig_builds)" -eq 3
check "two destinations: home A never reports a stale up-to-date helper" bash -c '! grep -qF "'"'"'$1'"'"' is up to date" "$2"' _ "$BIN_A" "$WORK/out.log"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_A"
check "two destinations: home A third run is a no-op" test "$(zig_builds)" -eq 3
check "two destinations: no-op reported for home A" grep -qF "'$BIN_A' is up to date" "$WORK/out.log"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_B"
check "two destinations: home B now a no-op too" test "$(zig_builds)" -eq 3

# out-of-band replacement: a binary whose sha256 no longer matches the stamp is reinstalled
printf '#!/bin/sh\necho tampered\n' > "$BIN_A"
chmod 0755 "$BIN_A"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_A"
check "out-of-band: replaced binary rebuilt" test "$(zig_builds)" -eq 4
check "out-of-band: binary restored from the build" grep -qx 'fake git-credential-scm get' <("$BIN_A" get 2>/dev/null)
check "out-of-band: reinstall reason logged" grep -qF "replaced outside the installer" "$WORK/out.log"
SCM_AUTH_HELPER_SRC_DIR="$TWO_SRC" run_installer_in "$HOME_A"
check "out-of-band: next run is a no-op again" test "$(zig_builds)" -eq 4

# root installer registers the family
check "root installer lists scm-auth" grep -q 'scm-auth' <(HOME="$TEST_HOME" bash "$ROOT_INSTALLER" -h)

(( OVERALL_RESULT == 0 )) && echo "All scm-auth tests passed" || echo "Some scm-auth tests FAILED"
exit "$OVERALL_RESULT"
