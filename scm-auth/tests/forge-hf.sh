#!/usr/bin/env bash
#
# Offline test for the scm-auth client wiring: scm-auth-login (forge token-cmd + plaintext strip,
# hf token storage), the hf shim, forge-gist, the installer's shim guard / hf token cleanup /
# gcli retirement and the scm-auth-status client section. Uses a temp HOME, a 'store --file'
# credential helper instead of libsecret and stub forge/curl/hf binaries; never the real HOME,
# keyring, forge config or network.

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
INSTALLER="$TESTS_DIR/../install.sh"
SRC_BIN="$(realpath -m "$TESTS_DIR/../bin")"
LOGIN="$SRC_BIN/scm-auth-login"
SHIM="$SRC_BIN/hf"
GIST="$SRC_BIN/forge-gist"
STATUS="$SRC_BIN/scm-auth-status"
TOKEN_CMD="$SRC_BIN/git-credential-token"
SENTINEL='SCMAUTH-SENTINEL-TOKEN-0123456789'
OLD_SENTINEL='SCMAUTH-OLD-PLAINTEXT-TOKEN-987'

declare -i OVERALL_RESULT=0
WORK=""
# shellcheck disable=SC2329
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
WORK="$(mktemp -d /tmp/linux-configs-scm-auth-forge-test.XXXXXX)"
TEST_HOME="$WORK/home"
CREDS="$WORK/creds"
FORGE_CONFIG="$TEST_HOME/.config/forge/config"
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT HF_TOKEN HF_HOME HF_TOKEN_PATH GITHUB_TOKEN GH_TOKEN XDG_CONFIG_HOME XDG_CACHE_HOME
export GIT_CONFIG_NOSYSTEM=1
export HOME="$TEST_HOME"
export SCM_AUTH_CREDENTIAL_HELPER="store --file $CREDS"
# safety net: even a real curl could never reach GitHub from this test
export FORGE_GIST_API_URL=http://127.0.0.1:9
BASE_PATH=/usr/bin:/bin
STUB_PATH="$WORK/stub:$BASE_PATH"

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

# shellcheck disable=SC2329 # invoked indirectly through check
function no_sentinel() {
    local file
    for file in "$@"; do
        [[ ! -e "$file" ]] || ! grep -qF -e "$SENTINEL" -e "$OLD_SENTINEL" -- "$file" || return 1
    done
}

function mode_of() { stat -c '%a' "$1"; }

function stored_token() {
    bash "$TOKEN_CMD" "$@" 2>/dev/null || true
}

mkdir -p "$TEST_HOME" "$WORK/stub" "$WORK/realbin"
: > "$CREDS"
chmod 0600 "$CREDS"

# stub forge: logs argv; 'auth login' writes token-cmd into the config like an old forge that keeps
# a stale 'token =' (so the strip is exercised) and runs the token-cmd with a minimal PATH to
# prove it is self-contained; 'api' prints a canned response; 'auth status' prints sources
cat > "$WORK/stub/forge" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/forge.argv"
case "\$1 \${2:-}" in
'auth login')
    domain="" cmd=""
    while (( \$# > 0 )); do
        case "\$1" in
        --domain) domain="\$2"; shift ;;
        --token-cmd) cmd="\$2"; shift ;;
        esac
        shift
    done
    if [[ "\$(env PATH=/usr/bin:/bin sh -c "\$cmd" 2>/dev/null)" == "\${STUB_EXPECT_TOKEN:-}" ]]; then
        echo match > "$WORK/forge.tokencmd"
    else
        echo mismatch > "$WORK/forge.tokencmd"
    fi
    config="\$HOME/.config/forge/config"
    mkdir -p "\${config%/*}"
    touch "\$config"
    if grep -qxF "[\$domain]" "\$config"; then
        awk -v d="[\$domain]" -v c="token-cmd = \$cmd" '{ print } \$0 == d { print c }' "\$config" > "\$config.new"
        cat "\$config.new" > "\$config"
        rm -f "\$config.new"
    else
        printf '[%s]\ntoken-cmd = %s\n\n' "\$domain" "\$cmd" >> "\$config"
    fi
    echo "Stored token command for \$domain" >&2
    ;;
'auth status')
    echo 'github.com: token from config (cmd: git-credential-token github.com)'
    echo 'gitlab.com: no token'
    ;;
api*)
    cat "$WORK/forge.api-response"
    ;;
esac
EOF
# stub curl: logs argv, stdin (curl config with the header) and the posted body
cat > "$WORK/stub/curl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$WORK/curl.argv"
cat > "$WORK/curl.stdin"
for arg in "\$@"; do
    [[ "\$arg" != @* ]] || cp -- "\${arg#@}" "$WORK/curl.body"
done
if [[ -n "\${STUB_CURL_EXIT:-}" ]]; then
    echo '{"message":"Bad credentials"}'
    exit "\$STUB_CURL_EXIT"
fi
echo '{"html_url":"https://gist.github.com/abc123","id":"abc123"}'
EOF
# stub real hf: records whether HF_TOKEN is set and equals the sentinel (never the value)
cat > "$WORK/realbin/hf" <<EOF
#!/usr/bin/env bash
if [[ -z "\${HF_TOKEN+x}" ]]; then state=unset
elif [[ "\$HF_TOKEN" == "$SENTINEL" ]]; then state=sentinel
elif [[ "\$HF_TOKEN" == preset ]]; then state=preset
else state=other; fi
echo "\$state" > "$WORK/hf.env"
echo "\${SCM_AUTH_TOOL-unset}" > "$WORK/hf.tool"
printf '%s\n' "\$@" > "$WORK/hf.argv"
exit "\${STUB_HF_EXIT:-0}"
EOF
chmod +x "$WORK/stub/forge" "$WORK/stub/curl" "$WORK/realbin/hf"

# ---------------------------------------------------------------- scm-auth-login <forge-domain>
PATH="$STUB_PATH" bash "$LOGIN" github.com > "$WORK/login.out" 2> "$WORK/login.err" < /dev/null && rc=0 || rc=$?
check "login: no keyring token exits 1" test "$rc" -eq 1
check "login: no keyring token explains how to store one" grep -qF 'scm-auth-login --store-token github.com' "$WORK/login.err"
check "login: no keyring token never calls forge" test ! -e "$WORK/forge.argv"

PATH="$STUB_PATH" bash "$LOGIN" 'bad/domain' > /dev/null 2>&1 < /dev/null && rc=0 || rc=$?
check "login: invalid domain exits 2" test "$rc" -eq 2
PATH="$STUB_PATH" bash "$LOGIN" --user $'x\nhost=evil' github.com > /dev/null 2>&1 < /dev/null && rc=0 || rc=$?
check "login: invalid username exits 2" test "$rc" -eq 2
printf 'abc\nhost=evil\n' | PATH="$STUB_PATH" bash "$LOGIN" --store-token gitea.com > /dev/null 2>&1 && rc=0 || rc=$?
check "login: only the first stdin line is the token (no protocol injection)" test -z "$(grep -F evil "$CREDS" || true)"
: > "$CREDS"
printf 'a b=c\n' | PATH="$STUB_PATH" bash "$LOGIN" --store-token gitea.com > /dev/null 2>&1 && rc=0 || rc=$?
check "login: token with unexpected characters is refused" test "$rc" -eq 1 -a -z "$(grep -F gitea "$CREDS" || true)"
: > "$CREDS"

# existing forge config with plaintext tokens for two domains
mkdir -p "${FORGE_CONFIG%/*}"
printf '[default]\noutput = table\n\n[github.com]\ntoken = %s\n\n[gitlab.com]\ntoken = keep-me\n' "$OLD_SENTINEL" > "$FORGE_CONFIG"
chmod 0640 "$FORGE_CONFIG"
printf '%s\n' "$SENTINEL" | PATH="$STUB_PATH" STUB_EXPECT_TOKEN="$SENTINEL" \
    bash "$LOGIN" --store-token github.com > "$WORK/login.out" 2> "$WORK/login.err" && rc=0 || rc=$?
check "login --store-token: exits 0" test "$rc" -eq 0
check "login --store-token: token stored for github.com as oauth2" test "$(stored_token github.com oauth2)" = "$SENTINEL"
check "login: forge auth login argv" test "$(sed -n '1,4p' "$WORK/forge.argv" | paste -sd ' ')" = 'auth login --domain github.com'
check "login: token-cmd uses the absolute helper path, attributed to forge" \
    test "$(sed -n '5,6p' "$WORK/forge.argv" | paste -sd ' ')" = "--token-cmd SCM_AUTH_TOOL=forge '$TOKEN_CMD' github.com"
check "login: token-cmd yields the keyring token under a minimal PATH" grep -qx match "$WORK/forge.tokencmd"
check "login: token never on forge argv" no_sentinel "$WORK/forge.argv"
check "login: token never in stdout/stderr" no_sentinel "$WORK/login.out" "$WORK/login.err"
check "login: plaintext github token stripped" no_sentinel "$FORGE_CONFIG"
check "login: github section keeps token-cmd" grep -qxF "token-cmd = SCM_AUTH_TOOL=forge '$TOKEN_CMD' github.com" "$FORGE_CONFIG"
check "login: other domain's token untouched" grep -qx 'token = keep-me' "$FORGE_CONFIG"
check "login: other settings untouched" grep -qx 'output = table' "$FORGE_CONFIG"
check "login: forge config mode preserved" test "$(mode_of "$FORGE_CONFIG")" = 640
check "login: atomic write leaves no temp file next to the config" bash -c '! compgen -G "$1.tmp.*" > /dev/null' _ "$FORGE_CONFIG"
backups=("$FORGE_CONFIG".bak.*)
check "login: one backup written" test "${#backups[@]}" -eq 1
check "login: backup mode 0600" test "$(mode_of "${backups[0]}")" = 600
check "login: backup has every token redacted" no_sentinel "${backups[0]}"
check "login: backup marks redaction" grep -qx 'token = <redacted>' "${backups[0]}"
check "login: backup does not keep the other token either" test -z "$(grep -F keep-me "${backups[0]}" || true)"

PATH="$STUB_PATH" STUB_EXPECT_TOKEN="$SENTINEL" bash "$LOGIN" github.com > /dev/null 2> "$WORK/login.err" < /dev/null && rc=0 || rc=$?
backups=("$FORGE_CONFIG".bak.*)
check "login: re-run exits 0" test "$rc" -eq 0
check "login: re-run writes no new backup" test "${#backups[@]}" -eq 1
check "login: re-run reports nothing to strip" grep -qF 'no plaintext token for github.com' "$WORK/login.err"

# forge not installed: keyring token is enough, exit 0
PATH="$BASE_PATH" bash "$LOGIN" github.com > /dev/null 2> "$WORK/login.err" < /dev/null && rc=0 || rc=$?
check "login: forge missing exits 0" test "$rc" -eq 0
check "login: forge missing notice" grep -qF 'forge not installed' "$WORK/login.err"

# tracing never leaks the token
: > "$CREDS"
printf '%s\n' "$SENTINEL" | DEBUG=1 PATH="$STUB_PATH" bash "$LOGIN" --store-token codeberg.org > /dev/null 2> "$WORK/trace.err"
check "login trace: DEBUG=1 stderr has no token" no_sentinel "$WORK/trace.err"
printf '%s\n' "$SENTINEL" | env SHELLOPTS=xtrace BASH_XTRACEFD=2 DEBUG=1 PATH="$STUB_PATH" \
    bash "$LOGIN" --store-token codeberg.org > /dev/null 2> "$WORK/trace.err"
check "login trace: SHELLOPTS=xtrace stderr has no token" no_sentinel "$WORK/trace.err"
printf '%s\n' "$SENTINEL" | PATH="$STUB_PATH" bash -x "$LOGIN" --store-token codeberg.org > /dev/null 2> "$WORK/trace.err"
check "login trace: bash -x stderr has no token" no_sentinel "$WORK/trace.err"
check "login trace: token still stored" test "$(stored_token codeberg.org)" = "$SENTINEL"

# ---------------------------------------------------------------- scm-auth-login hf
: > "$CREDS"
mkdir -p "$TEST_HOME/.cache/huggingface"
echo "$OLD_SENTINEL" > "$TEST_HOME/.cache/huggingface/token"
echo "$OLD_SENTINEL" > "$TEST_HOME/.cache/huggingface/stored_tokens"
echo keep > "$TEST_HOME/.cache/huggingface/other"
printf '%s\n' "$SENTINEL" | PATH="$BASE_PATH" bash "$LOGIN" hf > "$WORK/login.out" 2> "$WORK/login.err" && rc=0 || rc=$?
check "login hf: exits 0" test "$rc" -eq 0
check "login hf: token stored for huggingface.co as hf" test "$(stored_token huggingface.co hf)" = "$SENTINEL"
check "login hf: plaintext token file deleted" test ! -e "$TEST_HOME/.cache/huggingface/token"
check "login hf: stored_tokens kept (other named accounts may live there)" test -f "$TEST_HOME/.cache/huggingface/stored_tokens"
check "login hf: stored_tokens reported for manual review" grep -qF 'review' "$WORK/login.err"
check "login hf: stored_tokens reported by path" grep -qF "$TEST_HOME/.cache/huggingface/stored_tokens" "$WORK/login.err"
check "login hf: other cache files kept" test -f "$TEST_HOME/.cache/huggingface/other"
check "login hf: token never in stdout/stderr" no_sentinel "$WORK/login.out" "$WORK/login.err"
printf '' | PATH="$BASE_PATH" bash "$LOGIN" hf > /dev/null 2>&1 && rc=0 || rc=$?
check "login hf: empty input exits 1" test "$rc" -eq 1
printf '%s\n' "$SENTINEL" | env SHELLOPTS=xtrace BASH_XTRACEFD=2 DEBUG=1 PATH="$BASE_PATH" bash "$LOGIN" hf > /dev/null 2> "$WORK/trace.err"
check "login hf trace: SHELLOPTS=xtrace stderr has no token" no_sentinel "$WORK/trace.err"
printf '%s\n' "$SENTINEL" | PATH="$BASE_PATH" bash -x "$LOGIN" hf > /dev/null 2> "$WORK/trace.err"
check "login hf trace: bash -x stderr has no token" no_sentinel "$WORK/trace.err"

# ---------------------------------------------------------------- tool attribution (default helper)
# without the test override every git call goes to 'scm --tool=<tool>'; a stub git appends each
# helper argument it gets (never stdin, so no token is recorded)
mkdir -p "$WORK/gitstub"
cat > "$WORK/gitstub/git" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
    [[ "\$arg" != credential.helper=?* ]] || printf '%s %s\n' "\${!#}" "\$arg" >> "$WORK/git-helpers.log"
done
cat > /dev/null
EOF
chmod +x "$WORK/gitstub/git"
GITSTUB_PATH="$WORK/gitstub:$BASE_PATH"
: > "$WORK/git-helpers.log"
printf '%s\n' "$SENTINEL" | env -u SCM_AUTH_CREDENTIAL_HELPER PATH="$GITSTUB_PATH" \
    bash "$LOGIN" --store-token github.com > /dev/null 2>&1 || true
check "tool: forge store goes to scm --tool=forge" grep -qxF 'approve credential.helper=scm --tool=forge' "$WORK/git-helpers.log"
: > "$WORK/git-helpers.log"
printf '%s\n' "$SENTINEL" | env -u SCM_AUTH_CREDENTIAL_HELPER PATH="$GITSTUB_PATH" bash "$LOGIN" hf > /dev/null 2>&1 || true
check "tool: hf store goes to scm --tool=hf" grep -qxF 'approve credential.helper=scm --tool=hf' "$WORK/git-helpers.log"
: > "$WORK/git-helpers.log"
env -u SCM_AUTH_CREDENTIAL_HELPER PATH="$SRC_BIN:$WORK/realbin:$GITSTUB_PATH" hf whoami > /dev/null 2>&1 || true
check "tool: hf shim lookup goes to scm --tool=hf" grep -qxF 'fill credential.helper=scm --tool=hf' "$WORK/git-helpers.log"
check "tool: no token recorded" no_sentinel "$WORK/git-helpers.log"

# ---------------------------------------------------------------- hf shim
SHIM_PATH="$SRC_BIN:$WORK/realbin:$BASE_PATH"
PATH="$SHIM_PATH" STUB_HF_EXIT=3 hf auth whoami --verbose > "$WORK/hf.out" 2> "$WORK/hf.err" && rc=0 || rc=$?
check "shim: exit code passed through" test "$rc" -eq 3
check "shim: real hf gets HF_TOKEN from the keyring" grep -qx sentinel "$WORK/hf.env"
check "shim: argv passed through" test "$(paste -sd ' ' "$WORK/hf.argv")" = 'auth whoami --verbose'
check "shim: token never printed" no_sentinel "$WORK/hf.out" "$WORK/hf.err"
check "shim: no token file written" test ! -e "$TEST_HOME/.cache/huggingface/token"
check "shim: HF_TOKEN not leaked into the caller" test -z "${HF_TOKEN:-}"
check "shim: real hf does NOT receive SCM_AUTH_TOOL (only the token helper gets hf)" grep -qx unset "$WORK/hf.tool"

PATH="$SHIM_PATH" HF_TOKEN=preset hf whoami > /dev/null 2>&1
check "shim: preset HF_TOKEN is kept" grep -qx preset "$WORK/hf.env"

mv "$CREDS" "$CREDS.saved"
: > "$CREDS"
PATH="$SHIM_PATH" hf --help > /dev/null 2>&1 && rc=0 || rc=$?
check "shim: no keyring token still runs hf" test "$rc" -eq 0
check "shim: no keyring token leaves HF_TOKEN unset" grep -qx unset "$WORK/hf.env"
mv "$CREDS.saved" "$CREDS"

PATH="$SRC_BIN:$BASE_PATH" hf whoami > /dev/null 2> "$WORK/hf.err" && rc=0 || rc=$?
check "shim: no real hf exits 127" test "$rc" -eq 127
check "shim: no real hf message" grep -qF 'real hf CLI was not found' "$WORK/hf.err"

# copies/symlinks of the shim earlier on PATH are skipped, no recursion
mkdir -p "$WORK/shim-copy" "$WORK/shim-link"
cp "$SHIM" "$WORK/shim-copy/hf"
ln -s "$SHIM" "$WORK/shim-link/hf"
rm -f "$WORK/hf.env"
PATH="$WORK/shim-copy:$WORK/shim-link:$SHIM_PATH" hf whoami > /dev/null 2>&1 && rc=0 || rc=$?
check "shim: copies and symlinks skipped, real hf reached" test "$rc" -eq 0 -a "$(cat "$WORK/hf.env" 2>/dev/null)" = sentinel

PATH="$SHIM_PATH" DEBUG=1 bash -x "$SHIM" whoami > /dev/null 2> "$WORK/trace.err"
check "shim trace: bash -x stderr has no token" no_sentinel "$WORK/trace.err"
env SHELLOPTS=xtrace BASH_XTRACEFD=2 PATH="$SHIM_PATH" bash "$SHIM" whoami > /dev/null 2> "$WORK/trace.err"
check "shim trace: SHELLOPTS=xtrace stderr has no token" no_sentinel "$WORK/trace.err"
check "shim trace: real hf still got the token" grep -qx sentinel "$WORK/hf.env"

# ---------------------------------------------------------------- forge-gist
printf '%s\n' "$SENTINEL" | PATH="$BASE_PATH" bash "$LOGIN" --store-token github.com > /dev/null 2>&1
cat > "$WORK/forge.api-response" <<'EOF'
[{"id":"abc123","public":false,"description":"notes"},{"id":"def456","public":true,"description":null}]
EOF
PATH="$STUB_PATH" bash "$GIST" list > "$WORK/gist.out" 2>&1 && rc=0 || rc=$?
check "gist list: exits 0" test "$rc" -eq 0
check "gist list: forge api argv" test "$(paste -sd ' ' "$WORK/forge.argv")" = 'api -R github.com/scm-auth/forge-gist /gists?per_page=30'
check "gist list: tsv summary" test "$(cat "$WORK/gist.out")" = "$(printf 'abc123\tsecret\tnotes\ndef456\tpublic\t')"
PATH="$STUB_PATH" bash "$GIST" list --limit 5 --json > "$WORK/gist.out" 2>&1
check "gist list --limit --json: raw output" cmp -s "$WORK/gist.out" "$WORK/forge.api-response"
check "gist list --limit: per_page" grep -qx '/gists?per_page=5' "$WORK/forge.argv"

echo '{"files":{"a.txt":{"filename":"a.txt","content":"hello"}}}' > "$WORK/forge.api-response"
PATH="$STUB_PATH" bash "$GIST" view abc123 > "$WORK/gist.out" 2>&1
check "gist view: forge api argv" test "$(paste -sd ' ' "$WORK/forge.argv")" = 'api -R github.com/scm-auth/forge-gist /gists/abc123'
check "gist view: prints the files" test "$(cat "$WORK/gist.out")" = "$(printf '==> a.txt <==\nhello')"
PATH="$STUB_PATH" bash "$GIST" view '../x' > /dev/null 2>&1 && rc=0 || rc=$?
check "gist view: invalid id exits 2" test "$rc" -eq 2

# FORGE_GIST_API_URL: only https:// or loopback http:// may receive the bearer token
printf 'url check\n' > "$WORK/url.txt"
for bad in http://evil.example http://127.0.0.1.evil.example http://localhost@evil.example ftp://127.0.0.1 'http://[::2]' \
    'http://127.0.0.1:9@evil.example' 'http://localhost:1@evil.example' 'http://[::1]:1@evil.example' 'http://127.0.0.1:9#@evil' \
    https://user@evil.example 'http://127.0.0.1:abc' 'http://127.0.0.1:9?@evil' https:// 'https://api.example.invalid@evil.example'; do
    rm -f "$WORK/curl.argv"
    FORGE_GIST_API_URL="$bad" GITHUB_TOKEN="$SENTINEL" PATH="$STUB_PATH" bash "$GIST" create "$WORK/url.txt" > "$WORK/gist.out" 2> "$WORK/gist.err" && rc=0 || rc=$?
    check "gist refuses $bad (exit 2, curl never run)" test "$rc" -eq 2 -a ! -e "$WORK/curl.argv"
    check "gist refuses $bad without printing the token" no_sentinel "$WORK/gist.out" "$WORK/gist.err"
done
FORGE_GIST_API_URL=https://api.example.invalid GITHUB_TOKEN="$SENTINEL" PATH="$STUB_PATH" bash "$GIST" create "$WORK/url.txt" > /dev/null 2>&1 && rc=0 || rc=$?
check "gist accepts https:// API URLs" test "$rc" -eq 0 -a "$(grep -cx 'https://api.example.invalid/gists' "$WORK/curl.argv")" -eq 1
FORGE_GIST_API_URL=http://localhost:9 GITHUB_TOKEN="$SENTINEL" PATH="$STUB_PATH" bash "$GIST" create "$WORK/url.txt" > /dev/null 2>&1 && rc=0 || rc=$?
check "gist accepts loopback http:// (tests) API URLs" test "$rc" -eq 0
FORGE_GIST_API_URL=http://127.0.0.1:9/x GITHUB_TOKEN="$SENTINEL" PATH="$STUB_PATH" bash "$GIST" create "$WORK/url.txt" > /dev/null 2>&1 && rc=0 || rc=$?
check "gist accepts loopback http:// with a path" test "$rc" -eq 0 -a "$(grep -cx 'http://127.0.0.1:9/x/gists' "$WORK/curl.argv")" -eq 1

printf 'first file\n' > "$WORK/a.txt"
printf 'second "quoted"\n' > "$WORK/b.md"
PATH="$STUB_PATH" bash "$GIST" create -d 'my desc' "$WORK/a.txt" "$WORK/b.md" > "$WORK/gist.out" 2> "$WORK/gist.err" && rc=0 || rc=$?
check "gist create: exits 0" test "$rc" -eq 0
check "gist create: prints the gist URL" test "$(cat "$WORK/gist.out")" = 'https://gist.github.com/abc123'
check "gist create: secret by default" test "$(jq -r '.public' "$WORK/curl.body")" = false
check "gist create: description" test "$(jq -r '.description' "$WORK/curl.body")" = 'my desc'
check "gist create: file contents" test "$(jq -r '.files["b.md"].content' "$WORK/curl.body")" = 'second "quoted"'
check "gist create: both files" test "$(jq -r '.files | keys | join(",")' "$WORK/curl.body")" = 'a.txt,b.md'
check "gist create: POST to /gists" grep -qx 'http://127.0.0.1:9/gists' "$WORK/curl.argv"
check "gist create: token never on curl argv" no_sentinel "$WORK/curl.argv"
check "gist create: keyring token sent as header via stdin config" \
    test "$(cat "$WORK/curl.stdin")" = "header = \"Authorization: Bearer $SENTINEL\""
check "gist create: token never in stdout/stderr" no_sentinel "$WORK/gist.out" "$WORK/gist.err"

printf 'from stdin\n' | PATH="$STUB_PATH" bash "$GIST" create --public -n snippet.sh - > /dev/null 2>&1
check "gist create --public: public true" test "$(jq -r '.public' "$WORK/curl.body")" = true
check "gist create -: stdin content under -n name" test "$(jq -r '.files["snippet.sh"].content' "$WORK/curl.body")" = 'from stdin'
PATH="$STUB_PATH" GITHUB_TOKEN=env-token bash "$GIST" create "$WORK/a.txt" > /dev/null 2>&1
check "gist create: GITHUB_TOKEN takes precedence" grep -qF 'Bearer env-token' "$WORK/curl.stdin"
PATH="$STUB_PATH" bash "$GIST" create "$WORK/a.txt" "$WORK/a.txt" > /dev/null 2>&1 && rc=0 || rc=$?
check "gist create: duplicate names exit 2" test "$rc" -eq 2
PATH="$STUB_PATH" bash "$GIST" create -n x "$WORK/a.txt" "$WORK/b.md" > /dev/null 2>&1 && rc=0 || rc=$?
check "gist create: -n with several files exits 2" test "$rc" -eq 2
PATH="$STUB_PATH" STUB_CURL_EXIT=22 bash "$GIST" create "$WORK/a.txt" > /dev/null 2> "$WORK/gist.err" && rc=0 || rc=$?
check "gist create: API error exits 1 with the body on stderr" test "$rc" -eq 1 -a -n "$(grep -F 'Bad credentials' "$WORK/gist.err" || true)"
check "gist create: API error never prints the token" no_sentinel "$WORK/gist.err"
mv "$CREDS" "$CREDS.saved"
: > "$CREDS"
PATH="$STUB_PATH" bash "$GIST" create "$WORK/a.txt" > /dev/null 2> "$WORK/gist.err" && rc=0 || rc=$?
check "gist create: no token exits 1" test "$rc" -eq 1
mv "$CREDS.saved" "$CREDS"
env SHELLOPTS=xtrace BASH_XTRACEFD=2 DEBUG=1 PATH="$STUB_PATH" bash "$GIST" create "$WORK/a.txt" > /dev/null 2> "$WORK/trace.err"
check "gist trace: SHELLOPTS=xtrace stderr has no token" no_sentinel "$WORK/trace.err"
PATH="$STUB_PATH" bash -x "$GIST" create "$WORK/a.txt" > /dev/null 2> "$WORK/trace.err"
check "gist trace: bash -x stderr has no token" no_sentinel "$WORK/trace.err"
PATH="$STUB_PATH" bash "$GIST" bogus > /dev/null 2>&1 && rc=0 || rc=$?
check "gist: unknown command exits 2" test "$rc" -eq 2

# ---------------------------------------------------------------- installer
INSTALL_HOME="$WORK/install-home"
# the installer builds git-credential-scm with the stub zig (cache under INSTALL_HOME/.cache)
ZIG_DIR="$TESTS_DIR/fixtures"
BIN_DIR="$INSTALL_HOME/.local/bin"
mkdir -p "$INSTALL_HOME" "$WORK/pkg"
printf '#!/usr/bin/env bash\nprintf "install ok installed\\n"\n' > "$WORK/pkg/dpkg-query"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/pkg/apt-cache"
chmod +x "$WORK/pkg/dpkg-query" "$WORK/pkg/apt-cache"
function run_installer() {
    PATH="$ZIG_DIR:$WORK/pkg:$PATH" HOME="$INSTALL_HOME" bash "$INSTALLER" -im user -cm local "$@" scm-auth > "$WORK/out.log" 2>&1
}
function run_hook() {
    PATH="$ZIG_DIR:$WORK/pkg:$1" HOME="$INSTALL_HOME" bash -c '
        source "$1"
        RESOLVED_INSTALL_MODE=user RESOLVED_CONFIG_MODE=local
        family_hook scm-auth "$2" "${@:3}"
    ' _ "$INSTALLER" "${@:2}" > "$WORK/out.log" 2>&1
}

mkdir -p "$INSTALL_HOME/.cache/huggingface"
echo "$OLD_SENTINEL" > "$INSTALL_HOME/.cache/huggingface/token"
echo keep-named > "$INSTALL_HOME/.cache/huggingface/stored_tokens"
run_installer
check "install: exits 0" test $? -eq 0
for script in scm-auth-login forge-gist hf git-credential-token git-credential-scm-oauth; do
    check "install: $script installed" cmp -s "$SRC_BIN/$script" "$BIN_DIR/$script"
    check "install: $script mode 0755" test "$(mode_of "$BIN_DIR/$script")" = 755
done
check "install: hints at scm-auth-login" grep -qF 'scm-auth-login' "$WORK/out.log"
check "install: never touches the hf token file" test -f "$INSTALL_HOME/.cache/huggingface/token"
check "install: git-credential-scm built (stub zig)" test -x "$BIN_DIR/git-credential-scm"

run_installer -cc
check "-cc: exits 0" test $? -eq 0
check "-cc: plaintext hf token removed" test ! -e "$INSTALL_HOME/.cache/huggingface/token"
check "-cc: hf cache dir kept" test -d "$INSTALL_HOME/.cache/huggingface"
check "-cc: stored_tokens never removed by -cc" test -f "$INSTALL_HOME/.cache/huggingface/stored_tokens"
check "-cc: stored_tokens reported for manual review" grep -qF "stored_tokens'; review it and delete it by hand" "$WORK/out.log"
check "-cc: helpers reinstalled" test -x "$BIN_DIR/hf" -a -x "$BIN_DIR/scm-auth-login" -a -x "$BIN_DIR/forge-gist"

# a foreign hf at the shim destination is never overwritten nor removed
printf '#!/bin/sh\necho real hf\n' > "$BIN_DIR/hf"
chmod 0755 "$BIN_DIR/hf"
cp "$BIN_DIR/hf" "$WORK/foreign-hf"
run_installer
check "foreign hf: install exits 0" test $? -eq 0
check "foreign hf: not overwritten" cmp -s "$BIN_DIR/hf" "$WORK/foreign-hf"
check "foreign hf: notice suggests SCM_AUTH_HF_SHIM_DIR" grep -qF 'SCM_AUTH_HF_SHIM_DIR' "$WORK/out.log"
run_hook "$PATH" clean_home "$INSTALL_HOME" 0
check "foreign hf: clean keeps it" cmp -s "$BIN_DIR/hf" "$WORK/foreign-hf"
check "foreign hf: clean removes our helpers" test ! -e "$BIN_DIR/scm-auth-login" -a ! -e "$BIN_DIR/forge-gist"

# SCM_AUTH_HF_SHIM_DIR installs/removes the shim elsewhere
SCM_AUTH_HF_SHIM_DIR="$INSTALL_HOME/shim" run_installer
check "shim dir: shim installed there" cmp -s "$SHIM" "$INSTALL_HOME/shim/hf"
check "shim dir: foreign hf untouched" cmp -s "$BIN_DIR/hf" "$WORK/foreign-hf"
SCM_AUTH_HF_SHIM_DIR="$INSTALL_HOME/shim" run_hook "$PATH" clean_home "$INSTALL_HOME" 0
check "shim dir: clean removes the shim there" test ! -e "$INSTALL_HOME/shim/hf"
rm -f "$BIN_DIR/hf"

# gcli retirement (-cp hook): user copies and config removed, package files only reported
BREW_BIN="$INSTALL_HOME/.local/share/homebrew/bin"
MISE_SHIMS="$INSTALL_HOME/.local/share/mise/shims"
mkdir -p "$BIN_DIR" "$INSTALL_HOME/.config/gcli" "$WORK/sysbin" "$BREW_BIN" "$MISE_SHIMS"
printf '#!/bin/sh\n' > "$BIN_DIR/gcli"
printf '#!/bin/sh\n' > "$WORK/sysbin/gcli"
printf '#!/bin/sh\n' > "$BREW_BIN/gcli"
printf '#!/bin/sh\n' > "$MISE_SHIMS/gcli"
chmod +x "$BIN_DIR/gcli" "$WORK/sysbin/gcli" "$BREW_BIN/gcli" "$MISE_SHIMS/gcli"
echo 'token = x' > "$INSTALL_HOME/.config/gcli/config"
run_hook "$BIN_DIR:$BREW_BIN:$MISE_SHIMS:$WORK/sysbin:$BASE_PATH" clean_packages
check "gcli: hook exits 0" test $? -eq 0
check "gcli: user copy removed" test ! -e "$BIN_DIR/gcli"
check "gcli: config removed" test ! -e "$INSTALL_HOME/.config/gcli"
check "gcli: package-manager copy kept" test -x "$WORK/sysbin/gcli"
check "gcli: package-manager copy reported" grep -qF "gcli at '$WORK/sysbin/gcli' is outside the paths scm-auth removes" "$WORK/out.log"
check "gcli: homebrew copy under HOME kept" test -x "$BREW_BIN/gcli"
check "gcli: homebrew copy reported" grep -qF "gcli at '$BREW_BIN/gcli' is outside the paths scm-auth removes" "$WORK/out.log"
check "gcli: mise shim under HOME kept" test -x "$MISE_SHIMS/gcli"
check "gcli: mise shim reported" grep -qF "gcli at '$MISE_SHIMS/gcli' is outside the paths scm-auth removes" "$WORK/out.log"
run_hook "$BASE_PATH" clean_packages
check "gcli: hook is a no-op when nothing is left" test $? -eq 0

# ---------------------------------------------------------------- scm-auth-status client section
STATUS_HOME="$WORK/status-home"
mkdir -p "$STATUS_HOME/.config/forge" "$STATUS_HOME/.cache/huggingface" "$WORK/status-stub"
printf '[github.com]\ntoken = %s\n' "$OLD_SENTINEL" > "$STATUS_HOME/.config/forge/config"
echo "$OLD_SENTINEL" > "$STATUS_HOME/.cache/huggingface/token"
for tool in ssh ssh-add gpgconf systemctl journalctl; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/status-stub/$tool"
    chmod +x "$WORK/status-stub/$tool"
done
function run_status() {
    PATH="$1" HOME="$STATUS_HOME" XDG_RUNTIME_DIR="$WORK/run" SSH_AUTH_SOCK='' LC_ALL=C \
        SCM_AUTH_HELPER="$WORK/no-such/git-credential-scm" bash "$STATUS" --no-network > "$WORK/status.log" 2>&1 || true
}
run_status "$WORK/status-stub:$SRC_BIN:$WORK/realbin:$WORK/sysbin:$STUB_PATH"
check "status: plaintext forge token counted" grep -qE '^  x forge config +1 plaintext token line\(s\)  ~/.config/forge/config$' "$WORK/status.log"
check "status: forge token source shown (command elided)" grep -qE '^  \+ forge github.com +token from config \(cmd\)$' "$WORK/status.log"
check "status: hf shim first on PATH" grep -qxF "  + hf                     scm-auth shim first on PATH  $SRC_BIN/hf" "$WORK/status.log"
check "status: hf plaintext token file flagged" grep -qE '^  x hf token file +plaintext ~/.cache/huggingface/token$' "$WORK/status.log"
check "status: hf token file fix listed" grep -qE '^  x hf token file +scm-auth-login hf$' "$WORK/status.log"
check "status: gcli still installed flagged" grep -qE '^  x gcli +installed at ' "$WORK/status.log"
check "status: never prints token values" no_sentinel "$WORK/status.log"
printf '[github.com]\ntoken-cmd = git-credential-token github.com\n' > "$STATUS_HOME/.config/forge/config"
rm -f "$STATUS_HOME/.cache/huggingface/token"
run_status "$WORK/status-stub:$WORK/realbin:$BASE_PATH"
check "status: clean forge config" grep -qE '^  \+ forge config +no plaintext token  ' "$WORK/status.log"
check "status: forge not installed" grep -qE '^  - forge +not installed$' "$WORK/status.log"
check "status: real hf without shim flagged" grep -qF "  x hf                     $WORK/realbin/hf first on PATH  not the scm-auth shim" "$WORK/status.log"
if [[ ! -e /usr/bin/gcli && ! -e /bin/gcli ]]; then
    check "status: gcli absent" grep -qE '^  \+ gcli +absent  retired$' "$WORK/status.log"
else
    echo "SKIP: a system gcli is installed; 'gcli: absent' check skipped"
fi

(( OVERALL_RESULT == 0 )) && echo "All scm-auth forge/hf tests passed" || echo "Some scm-auth forge/hf tests FAILED"
exit "$OVERALL_RESULT"
