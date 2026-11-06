#!/usr/bin/env bash
#
# Offline test for the scm-auth git credential wiring: the include file, include.path in
# ~/.gitconfig, deduplication/restoration of top-level credential.helper entries and the
# git-credential-token helper (stub git for the protocol contract, real git with a 'store'
# helper override for the end-to-end fill path). Temp HOME only; never the real HOME/keyring.

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
INSTALLER="$TESTS_DIR/../install.sh"
INCLUDE_SRC="$TESTS_DIR/../git/scm-auth.gitconfig"
TOKEN_CMD="$TESTS_DIR/../bin/git-credential-token"
STATUS="$TESTS_DIR/../bin/scm-auth-status"
# shellcheck disable=SC2088 # literal include.path value
INCLUDE_VALUE='~/.config/git/scm-auth.gitconfig'
SENTINEL='SCMAUTH-SENTINEL-TOKEN-0123456789'

declare -i OVERALL_RESULT=0
WORK=""
# shellcheck disable=SC2329
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
WORK="$(mktemp -d /tmp/linux-configs-scm-auth-git-test.XXXXXX)"
TEST_HOME="$WORK/home"
GITCONFIG="$TEST_HOME/.gitconfig"
INCLUDE_DST="$TEST_HOME/.config/git/scm-auth.gitconfig"
# keep every git call away from the real user/system config
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT SCM_AUTH_TOOL SCM_AUTH_CREDENTIAL_HELPER SCM_AUTH_HELPER_SRC_DIR
export GIT_CONFIG_NOSYSTEM=1
# the installer builds git-credential-scm with the stub zig; stamp/cache stay in the temp dir
ZIG_DIR="$TESTS_DIR/fixtures"
export XDG_CACHE_HOME="$WORK/cache"

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

function run_clean_hook() {
    PATH="$WORK/bin:$PATH" HOME="$TEST_HOME" bash -c 'source "$1"; scm_auth_clean_home "$2" 0' _ "$INSTALLER" "$TEST_HOME" > "$WORK/out.log" 2>&1
}

# values of <key> in the test ~/.gitconfig itself (no includes), comma separated
function file_values() {
    git config --file "$GITCONFIG" --get-all "$1" 2>/dev/null | paste -sd ',' - || true
}

# effective credential.helper chain as git sees it for the test HOME (includes followed)
function effective_helpers() {
    HOME="$TEST_HOME" git config --global --includes --get-all credential.helper 2>/dev/null | paste -sd ',' - || true
}

function mode_of() {
    stat -c '%a' "$1"
}

# shellcheck disable=SC2329 # invoked indirectly through check
function no_sentinel() {
    ! grep -qF -- "$SENTINEL" "$@"
}

mkdir -p "$TEST_HOME" "$WORK/bin" "$WORK/stub"
printf '#!/usr/bin/env bash\nprintf "install ok installed\\n"\n' > "$WORK/bin/dpkg-query"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/apt-cache"
STUB_LOG="$WORK/stub.log"
for tool in systemctl secret-tool ssh ssh-add gpgconf journalctl; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s"\n' "$tool" "$STUB_LOG" > "$WORK/bin/$tool"
done
chmod +x "$WORK/bin"/*
: > "$STUB_LOG"

# include contract
check "include: scm is the first helper, scm-oauth the second" \
    test "$(git config --file "$INCLUDE_SRC" --get-all credential.helper | paste -sd ',' -)" = scm,scm-oauth
check "include: no empty helper (it would reset the chain)" \
    test -z "$(git config --file "$INCLUDE_SRC" --get-all credential.helper | grep -x '' || true)"
check "include: no forced gitlab.com username (a mismatch misses the keyring)" test -z "$(git config --file "$INCLUDE_SRC" credential.https://gitlab.com.username || true)"
check "include: huggingface.co username hf" test "$(git config --file "$INCLUDE_SRC" credential.https://huggingface.co.username)" = hf
check "include: useHttpPath false" test "$(git config --file "$INCLUDE_SRC" --type=bool credential.useHttpPath)" = false
check "include: holds no password/token" test -z "$(grep -iE 'password|token *=' "$INCLUDE_SRC" || true)"

# fresh HOME: include installed, include.path added, chain comes from the include
run_installer
check "fresh install exits 0" test $? -eq 0
check "include installed" cmp -s "$INCLUDE_SRC" "$INCLUDE_DST"
check "include mode is 0644" test "$(mode_of "$INCLUDE_DST")" = 644
check "include.path added once" test "$(file_values include.path)" = "$INCLUDE_VALUE"
check "no top-level helpers needed" test -z "$(file_values credential.helper)"
check "effective chain is scm,scm-oauth" test "$(effective_helpers)" = scm,scm-oauth
check "git-credential-token installed" test -x "$TEST_HOME/.local/bin/git-credential-token"
check "git-credential-scm installed" test -x "$TEST_HOME/.local/bin/git-credential-scm"
check "git-credential-scm-oauth installed" test -x "$TEST_HOME/.local/bin/git-credential-scm-oauth"
check "install never calls systemctl or secret-tool" test ! -s "$STUB_LOG"

# idempotency
GITCONFIG_MTIME="$(stat -c '%y' "$GITCONFIG")"
INCLUDE_MTIME="$(stat -c '%y' "$INCLUDE_DST")"
run_installer
check "second run exits 0" test $? -eq 0
check "second run keeps a single include.path" test "$(file_values include.path)" = "$INCLUDE_VALUE"
check "second run leaves ~/.gitconfig untouched" test "$(stat -c '%y' "$GITCONFIG")" = "$GITCONFIG_MTIME"
check "second run leaves the include untouched" test "$(stat -c '%y' "$INCLUDE_DST")" = "$INCLUDE_MTIME"

check "fresh install records no removed helper" test -z "$(file_values scm-auth.removedhelper)"

# fresh install then clean writes no helpers and leaves no marker
run_clean_hook
check "fresh clean: no credential.helper written" test -z "$(file_values credential.helper)"
check "fresh clean: no [scm-auth] marker section" test -z "$(grep -F '[scm-auth]' "$GITCONFIG" || true)"
check "fresh clean: include.path removed" test -z "$(file_values include.path)"

# existing config with the live helpers: identical ones deduped, user content kept
rm -f "$GITCONFIG"
cat > "$GITCONFIG" <<'EOF'
[user]
	name = Tester
[credential]
	helper = libsecret
	helper = oauth
[includeIf "gitdir:~/work/"]
	path = ~/.gitconfig-work
EOF
run_installer
check "dedupe: install exits 0" test $? -eq 0
check "dedupe: identical top-level helpers removed" test -z "$(file_values credential.helper)"
check "dedupe: include.path added" test "$(file_values include.path)" = "$INCLUDE_VALUE"
check "dedupe: effective chain is scm,scm-oauth (no duplicates, no libsecret, no bare oauth)" test "$(effective_helpers)" = scm,scm-oauth
check "dedupe: legacy libsecret reported" grep -qF "Removing legacy top-level credential.helper 'libsecret'" "$WORK/out.log"
check "dedupe: user settings kept" test "$(file_values user.name)" = Tester
# shellcheck disable=SC2088 # literal config value
check "dedupe: includeIf kept" test "$(file_values includeif.gitdir:~/work/.path)" = '~/.gitconfig-work'
check "dedupe: removed helpers recorded in order" test "$(file_values scm-auth.removedhelper)" = libsecret,oauth
# a second install (also after the user re-added a helper) records nothing twice
git config --file "$GITCONFIG" --add credential.helper oauth
run_installer
check "dedupe twice: re-added helper removed again" test -z "$(file_values credential.helper)"
check "dedupe twice: marker not duplicated" test "$(file_values scm-auth.removedhelper)" = libsecret,oauth

# clean restores the helpers the dedupe removed
run_clean_hook
check "clean: include file removed" test ! -e "$INCLUDE_DST"
check "clean: include.path removed" test -z "$(file_values include.path)"
check "clean: empty [include] section dropped" test -z "$(grep -x '\[include\]' "$GITCONFIG" || true)"
check "clean: top-level helpers restored in order" test "$(file_values credential.helper)" = libsecret,oauth
check "clean: effective chain libsecret,oauth" test "$(effective_helpers)" = libsecret,oauth
check "clean: user settings kept" test "$(file_values user.name)" = Tester
check "clean: marker removed" test -z "$(file_values scm-auth.removedhelper)"
check "clean: no [scm-auth] section left" test -z "$(grep -F '[scm-auth]' "$GITCONFIG" || true)"
GITCONFIG_MTIME="$(stat -c '%y' "$GITCONFIG")"
run_clean_hook
check "clean twice: no change" test "$(stat -c '%y' "$GITCONFIG")" = "$GITCONFIG_MTIME"
check "clean twice: helpers not duplicated" test "$(file_values credential.helper)" = libsecret,oauth

# top-level scm + oauth (already the new chain): deduped and restored like the old pair
git config --file "$GITCONFIG" --unset-all credential.helper
for helper in scm oauth; do
    git config --file "$GITCONFIG" --add credential.helper "$helper"
done
run_installer
check "scm pair: install exits 0" test $? -eq 0
check "scm pair: top-level helpers removed" test -z "$(file_values credential.helper)"
check "scm pair: effective chain scm,scm-oauth" test "$(effective_helpers)" = scm,scm-oauth
check "scm pair: recorded in order" test "$(file_values scm-auth.removedhelper)" = scm,oauth
run_clean_hook
check "scm pair: clean restores scm,oauth" test "$(file_values credential.helper)" = scm,oauth

# a lone leftover libsecret is replaced by the include's chain and restored by clean
git config --file "$GITCONFIG" --unset-all credential.helper
git config --file "$GITCONFIG" --add credential.helper libsecret
run_installer
check "leftover libsecret: removed" test -z "$(file_values credential.helper)"
check "leftover libsecret: effective chain scm,scm-oauth" test "$(effective_helpers)" = scm,scm-oauth
check "leftover libsecret: not reported as an own helper" bash -c '! grep -qF "keeps its own credential.helper" "$1"' _ "$WORK/out.log"
run_clean_hook
check "leftover libsecret: clean restores it alone" test "$(file_values credential.helper)" = libsecret
check "leftover libsecret: marker removed" test -z "$(file_values scm-auth.removedhelper)"

# cache + libsecret + oauth: the differing helper is left and reported; clean restores the two
# removed ones after it (chain order libsecret->oauth kept, position relative to cache not)
git config --file "$GITCONFIG" --unset-all credential.helper
for helper in 'cache --timeout=60' libsecret oauth; do
    git config --file "$GITCONFIG" --add credential.helper "$helper"
done
run_installer
check "differing: install exits 0" test $? -eq 0
check "differing: own helper kept, identical ones removed" test "$(file_values credential.helper)" = 'cache --timeout=60'
check "differing: own helper reported" grep -qF "keeps its own credential.helper 'cache --timeout=60'" "$WORK/out.log"
run_clean_hook
check "differing: clean restores all three" test "$(file_values credential.helper)" = 'cache --timeout=60,libsecret,oauth'
check "differing: marker removed" test -z "$(file_values scm-auth.removedhelper)"
git config --file "$GITCONFIG" --unset-all credential.helper
git config --file "$GITCONFIG" --add credential.helper 'cache --timeout=60'

# -cc: clean + reinstall ends in the installed state
run_installer -cc
check "-cc exits 0" test $? -eq 0
check "-cc: one include.path" test "$(file_values include.path)" = "$INCLUDE_VALUE"
check "-cc: include reinstalled" cmp -s "$INCLUDE_SRC" "$INCLUDE_DST"
check "-cc: no systemctl/secret-tool calls" test ! -s "$STUB_LOG"
check "-cc: no helper added next to the own one" test "$(file_values credential.helper)" = 'cache --timeout=60'

# -cc on a fresh home never writes helpers
run_clean_hook
rm -f "$GITCONFIG"
run_installer -cc
check "-cc fresh: exits 0" test $? -eq 0
check "-cc fresh: no credential.helper written" test -z "$(file_values credential.helper)"
check "-cc fresh: no marker" test -z "$(file_values scm-auth.removedhelper)"

# clean without any ~/.gitconfig creates none
run_clean_hook
rm -f "$GITCONFIG"
run_clean_hook
check "clean without ~/.gitconfig creates none" test ! -e "$GITCONFIG"

# git-credential-token contract with a stub git (logs argv, env and stdin)
cat > "$WORK/stub/git" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/git.argv"
printf 'GIT_TERMINAL_PROMPT=%s GIT_ASKPASS=%s\n' "\${GIT_TERMINAL_PROMPT:-}" "\${GIT_ASKPASS:-}" > "$WORK/git.env"
cat > "$WORK/git.stdin"
printf 'stub stderr %s\n' "\${STUB_PASSWORD:-}" >&2
printf 'protocol=https\nhost=example\nusername=someone\n'
[[ -z "\${STUB_PASSWORD+x}" ]] || printf 'password=%s\n' "\$STUB_PASSWORD"
printf 'password=second-ignored\n'
EOF
chmod +x "$WORK/stub/git"
# no user bin dirs: a real git-credential-scm on PATH would change the helper string
STUB_PATH="$WORK/stub:/usr/bin:/bin"

PATH="$STUB_PATH" STUB_PASSWORD="$SENTINEL" bash "$TOKEN_CMD" gitlab.com oauth2 > "$WORK/token.out" 2> "$WORK/token.err"
check "token: exits 0 when a password is returned" test $? -eq 0
check "token: stdout is exactly the first password" test "$(cat "$WORK/token.out")" = "$SENTINEL"
check "token: stdout is a single line" test "$(wc -l < "$WORK/token.out")" -eq 1
check "token: stderr carries nothing secret" no_sentinel "$WORK/token.err"
check "token: token never on git argv" no_sentinel "$WORK/git.argv"
check "token: resets helpers, then asks scm only (tool git by default)" \
    test "$(paste -sd '|' "$WORK/git.argv")" = '-c|credential.helper=|-c|credential.helper=scm --tool=git|credential|fill'
check "token: prompts disabled" grep -qx 'GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true' "$WORK/git.env"
check "token: request names protocol, host and user only" \
    test "$(paste -sd ' ' "$WORK/git.stdin")" = 'protocol=https host=gitlab.com username=oauth2'

PATH="$STUB_PATH" bash "$TOKEN_CMD" github.com > "$WORK/token.out" 2> "$WORK/token.err"
check "token: no username line without a username" test "$(paste -sd ' ' "$WORK/git.stdin")" = 'protocol=https host=github.com'

# tool attribution: SCM_AUTH_TOOL becomes --tool=<name>; anything else is refused before git runs
for tool in forge hf; do
    PATH="$STUB_PATH" SCM_AUTH_TOOL="$tool" bash "$TOKEN_CMD" github.com > /dev/null 2>&1
    check "token: SCM_AUTH_TOOL=$tool passes --tool=$tool" grep -qxF "credential.helper=scm --tool=$tool" "$WORK/git.argv"
done
for bad in 'a b' 'Forge' 'x;y' "\$(id)" '' "$(printf 'x%.0s' {1..33})"; do
    rm -f "$WORK/git.argv"
    PATH="$STUB_PATH" SCM_AUTH_TOOL="$bad" bash "$TOKEN_CMD" github.com > "$WORK/token.out" 2> "$WORK/token.err" && rc=0 || rc=$?
    if [[ -z "$bad" ]]; then
        check "token: empty SCM_AUTH_TOOL falls back to git" grep -qxF 'credential.helper=scm --tool=git' "$WORK/git.argv"
    else
        check "token: rejects SCM_AUTH_TOOL '${bad:0:12}' with exit 2 and no git call" \
            test "$rc" -eq 2 -a ! -s "$WORK/token.out" -a ! -e "$WORK/git.argv"
    fi
done
# an installed git-credential-scm is called by absolute path (forge runs token-cmd with a minimal PATH)
mkdir -p "$WORK/scm-bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/scm-bin/git-credential-scm"
chmod +x "$WORK/scm-bin/git-credential-scm"
PATH="$WORK/stub:$WORK/scm-bin:/usr/bin:/bin" SCM_AUTH_TOOL=forge bash "$TOKEN_CMD" github.com > /dev/null 2>&1
check "token: installed helper used by absolute path" \
    grep -qxF "credential.helper=$WORK/scm-bin/git-credential-scm --tool=forge" "$WORK/git.argv"
# the copy next to git-credential-token wins over PATH
mkdir -p "$WORK/side"
cp "$TOKEN_CMD" "$WORK/side/git-credential-token"
cp "$WORK/scm-bin/git-credential-scm" "$WORK/side/git-credential-scm"
PATH="$WORK/stub:$WORK/scm-bin:/usr/bin:/bin" bash "$WORK/side/git-credential-token" github.com > /dev/null 2>&1
check "token: sibling git-credential-scm preferred" \
    grep -qxF "credential.helper=$WORK/side/git-credential-scm --tool=git" "$WORK/git.argv"

PATH="$STUB_PATH" STUB_PASSWORD='' bash "$TOKEN_CMD" github.com > "$WORK/token.out" 2>&1 && rc=0 || rc=$?
check "token: empty password exits 1" test "$rc" -eq 1
check "token: empty password prints nothing" test ! -s "$WORK/token.out"

for bad in 'a/b' 'a b' 'a=b' $'a\nb' '' '-x' 'https://github.com' 'host.' 'x;y'; do
    rm -f "$WORK/git.argv"
    PATH="$STUB_PATH" bash "$TOKEN_CMD" "$bad" > "$WORK/token.out" 2>/dev/null && rc=0 || rc=$?
    check "token: rejects host '${bad//$'\n'/\\n}' with exit 2 and no git call" \
        test "$rc" -eq 2 -a ! -s "$WORK/token.out" -a ! -e "$WORK/git.argv"
done
for bad in $'oauth2\nhost=evil' 'a=b' 'a b'; do
    PATH="$STUB_PATH" bash "$TOKEN_CMD" github.com "$bad" > /dev/null 2>&1 && rc=0 || rc=$?
    check "token: rejects username '${bad//$'\n'/\\n}'" test "$rc" -eq 2
done
PATH="$STUB_PATH" bash "$TOKEN_CMD" a b c > /dev/null 2>&1 && rc=0 || rc=$?
check "token: rejects extra arguments" test "$rc" -eq 2
check "token: --help exits 0" bash -c '"$1" --help > /dev/null' _ "$TOKEN_CMD"

# end to end with the real git: 'store' helper override, configured helpers never consulted
TOKEN_HOME="$WORK/token-home"
mkdir -p "$TOKEN_HOME"
printf 'https://oauth2:%s@example.test\n' "$SENTINEL" > "$WORK/creds"
chmod 0600 "$WORK/creds"
printf '[credential]\n\thelper = "!f() { touch %s/oauth-called; }; f"\n' "$WORK" > "$TOKEN_HOME/.gitconfig"
function real_token() {
    HOME="$TOKEN_HOME" SCM_AUTH_CREDENTIAL_HELPER="store --file $WORK/creds" bash "$TOKEN_CMD" "$@"
}
real_token example.test > "$WORK/token.out" 2> "$WORK/token.err"
check "real git: stored token returned" test "$(cat "$WORK/token.out")" = "$SENTINEL"
check "real git: stderr empty" test ! -s "$WORK/token.err"
real_token example.test oauth2 > "$WORK/token.out" 2>/dev/null
check "real git: matching username returns the token" test "$(cat "$WORK/token.out")" = "$SENTINEL"
real_token example.test someone-else > "$WORK/token.out" 2>/dev/null && rc=0 || rc=$?
check "real git: other username exits 1 without output" test "$rc" -eq 1 -a ! -s "$WORK/token.out"
real_token missing.test > "$WORK/token.out" 2>/dev/null < /dev/null && rc=0 || rc=$?
check "real git: unknown host exits 1 without output (no prompt)" test "$rc" -eq 1 -a ! -s "$WORK/token.out"
check "real git: user-configured helpers (oauth) never run" test ! -e "$WORK/oauth-called"

# tracing never leaks the token: DEBUG is ignored, inherited xtrace (SHELLOPTS, bash -x) is off
DEBUG=1 real_token example.test > "$WORK/token.out" 2> "$WORK/token.err"
check "trace: DEBUG=1 still returns the token" test "$(cat "$WORK/token.out")" = "$SENTINEL"
check "trace: DEBUG=1 stderr has no token" no_sentinel "$WORK/token.err"
# SHELLOPTS is readonly in this shell, so it is passed through env
env SHELLOPTS=xtrace BASH_XTRACEFD=2 DEBUG=1 HOME="$TOKEN_HOME" SCM_AUTH_CREDENTIAL_HELPER="store --file $WORK/creds" \
    bash "$TOKEN_CMD" example.test > "$WORK/token.out" 2> "$WORK/token.err"
check "trace: SHELLOPTS=xtrace stdout is the token only" test "$(cat "$WORK/token.out")" = "$SENTINEL"
check "trace: SHELLOPTS=xtrace stderr has no token" no_sentinel "$WORK/token.err"
HOME="$TOKEN_HOME" SCM_AUTH_CREDENTIAL_HELPER="store --file $WORK/creds" \
    bash -x "$TOKEN_CMD" example.test > "$WORK/token.out" 2> "$WORK/token.err"
check "trace: bash -x stderr has no token" no_sentinel "$WORK/token.err"

# scm-auth-status: git include, effective helper chain, mise use_git_credentials, token presence
STATUS_HOME="$WORK/status-home"
mkdir -p "$STATUS_HOME/.config/git" "$STATUS_HOME/.config/mise"
cp "$INCLUDE_SRC" "$STATUS_HOME/.config/git/scm-auth.gitconfig"
printf '[include]\n\tpath = %s\n' "$INCLUDE_VALUE" > "$STATUS_HOME/.gitconfig"
cat > "$STATUS_HOME/.config/mise/config.toml" <<'EOF'
[settings]
gitlab.use_git_credentials = true
[settings.github]
use_git_credentials = true # comment
[settings.forgejo]
use_git_credentials = false
EOF
function run_status() {
    PATH="$WORK/bin:$PATH" HOME="$STATUS_HOME" XDG_CONFIG_HOME='' XDG_RUNTIME_DIR="$WORK/run" SSH_AUTH_SOCK='' \
        SCM_AUTH_HELPER="$WORK/no-such/git-credential-scm" \
        SCM_AUTH_CREDENTIAL_HELPER="store --file $WORK/creds" LC_ALL=C bash "$STATUS" --no-network "$@" > "$WORK/status.log" 2>&1
}
run_status --credentials example.test missing.test
check "status: include.path found" grep -qxE "  \+ include +$INCLUDE_VALUE" "$WORK/status.log"
check "status: effective chain from the include" grep -qxE '  \+ helper chain +scm -> scm-oauth' "$WORK/status.log"
check "status: OAuth guard reported" grep -qE '^  \+ oauth fallback +terminal only  ' "$WORK/status.log"
check "status: mise github table form" grep -qxE '  \+ mise github +use_git_credentials' "$WORK/status.log"
check "status: mise gitlab dotted form" grep -qxE '  \+ mise gitlab +use_git_credentials' "$WORK/status.log"
check "status: mise forgejo false is reported unset" grep -qxE '  x mise forgejo +use_git_credentials unset' "$WORK/status.log"
check "status: stored token reported without value" grep -qxE '  \+ example.test +token stored' "$WORK/status.log"
check "status: missing token reported" grep -qxE '  - missing.test +token none' "$WORK/status.log"
check "status: never prints the token" no_sentinel "$WORK/status.log"
DEBUG=1 run_status --credentials example.test
check "status: DEBUG=1 still reports the token as stored" grep -qxE '  \+ example.test +token stored' "$WORK/status.log"
check "status: DEBUG=1 trace never contains the token" no_sentinel "$WORK/status.log"
rm -f "$STATUS_HOME/.gitconfig" "$STATUS_HOME/.config/mise/config.toml"
run_status example.test
check "status: missing include flagged" grep -qE '^  x include +missing ' "$WORK/status.log"
check "status: missing mise config skipped" grep -qE '^  - mise +config not found ' "$WORK/status.log"
check "status: token checks only on request" bash -c '! grep -qE "token (stored|none)" "$1"' _ "$WORK/status.log"
SCM_AUTH_OAUTH=always run_status example.test
check "status: SCM_AUTH_OAUTH=always is a warning" grep -qE '^  ! oauth fallback +SCM_AUTH_OAUTH=always  ' "$WORK/status.log"

# git-credential-scm-oauth: runs git-credential-oauth only for an interactive git
GUARD="$TESTS_DIR/../bin/git-credential-scm-oauth"
OAUTH_LOG="$WORK/oauth.log"
export OAUTH_LOG
cat > "$WORK/stub/git-credential-oauth" <<'STUB'
#!/usr/bin/env bash
printf 'argv: %s\n' "$*" >> "$OAUTH_LOG"
[[ "${!#}" != get ]] || { sed 's/^/stdin: /' >> "$OAUTH_LOG"; printf 'username=oauth2\npassword=from-oauth\n'; }
STUB
printf '#!/usr/bin/env bash\nprintf "logger %%s\\n" "$*" >> "%s"\n' "$STUB_LOG" > "$WORK/stub/logger"
chmod +x "$WORK/stub/git-credential-oauth" "$WORK/stub/logger"
# run_guard [env...] -- <args...>: no controlling terminal (setsid), like an IDE or cron job
function run_guard() {
    local -a envs=()
    while [[ "$1" != -- ]]; do
        envs+=("$1")
        shift
    done
    shift
    : > "$OAUTH_LOG"
    : > "$STUB_LOG"
    printf 'protocol=https\nhost=gitlab.com\nwwwauth[]=Bearer realm="x"\n\n' |
        env PATH="$WORK/stub:$PATH" SCM_AUTH_OAUTH_BIN="$WORK/stub/git-credential-oauth" "${envs[@]}" \
            setsid -w bash "$GUARD" "$@" > "$WORK/guard.out" 2> "$WORK/guard.err"
}
# runs the guard on a pseudo terminal (script(1)), like git in an interactive shell
function run_guard_tty() {
    : > "$OAUTH_LOG"
    printf 'protocol=https\nhost=gitlab.com\n\n' > "$WORK/guard.in"
    # an inherited GIT_TERMINAL_PROMPT=0 (CI) would mask the terminal; tests pass it explicitly
    env -u GIT_TERMINAL_PROMPT PATH="$WORK/stub:$PATH" SCM_AUTH_OAUTH_BIN="$WORK/stub/git-credential-oauth" "$@" \
        script -qec "bash '$GUARD' get < '$WORK/guard.in'" /dev/null > "$WORK/guard.out" 2>&1 </dev/null || true
}
if command -v setsid &>/dev/null; then
    run_guard -- get
    check "guard: exits 0 without a terminal" test $? -eq 0
    check "guard: no OAuth flow without a terminal" test ! -s "$OAUTH_LOG"
    check "guard: answers nothing without a terminal" test ! -s "$WORK/guard.out"
    check "guard: explains the skip on stderr" grep -q 'no keyring token for https://gitlab.com; not starting the OAuth browser flow for non-interactive caller ' "$WORK/guard.err"
    check "guard: logs the skip to the journal (tag scm-auth)" grep -q '^logger -t scm-auth -p user.notice -- no keyring token for https://gitlab.com' "$STUB_LOG"
    run_guard SCM_AUTH_OAUTH=device -- get
    check "guard: device mode also skips without a terminal" test ! -s "$OAUTH_LOG"
    run_guard SCM_AUTH_OAUTH=always -- -bearer get
    check "guard: SCM_AUTH_OAUTH=always runs git-credential-oauth" grep -qx 'argv: -bearer get' "$OAUTH_LOG"
    check "guard: passes git's request through unchanged" diff -u \
        <(printf 'stdin: protocol=https\nstdin: host=gitlab.com\nstdin: wwwauth[]=Bearer realm="x"\nstdin: \n') <(grep '^stdin: ' "$OAUTH_LOG")
    check "guard: returns git-credential-oauth's answer" grep -qx 'password=from-oauth' "$WORK/guard.out"
    run_guard SCM_AUTH_OAUTH=never -- get
    check "guard: SCM_AUTH_OAUTH=never never runs it" test ! -s "$OAUTH_LOG"
    rc=0
    run_guard SCM_AUTH_OAUTH=bogus -- get || rc=$?
    check "guard: rejects an invalid SCM_AUTH_OAUTH" test "$rc" -eq 2
    run_guard -- erase
    check "guard: store/erase pass through" grep -qx 'argv: erase' "$OAUTH_LOG"
else
    echo "SKIP: setsid not installed; guard checks skipped"
fi
if command -v script &>/dev/null; then
    run_guard_tty
    check "guard: runs git-credential-oauth with a terminal" grep -qx 'argv: get' "$OAUTH_LOG"
    run_guard_tty GIT_TERMINAL_PROMPT=0
    check "guard: GIT_TERMINAL_PROMPT=0 skips even with a terminal" test ! -s "$OAUTH_LOG"
else
    echo "SKIP: script(1) not installed; guard terminal checks skipped"
fi

(( OVERALL_RESULT == 0 )) && echo "All scm-auth git tests passed" || echo "Some scm-auth git tests FAILED"
exit "$OVERALL_RESULT"
