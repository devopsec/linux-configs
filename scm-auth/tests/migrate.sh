#!/usr/bin/env bash
#
# Offline test for scm-auth/bin/scm-auth-migrate and scm-auth/bin/scm-auth-status: runs both in
# a temporary HOME with stubbed systemctl, secret-tool, git-credential-scm, ssh, ssh-add and
# gpgconf on PATH (the stubs log their argv) and asserts the ssh config rewrite, backup,
# planned/applied unit and keyring actions (retag preview vs --apply), idempotency, opt-out
# flags, the helper report of scm-auth-status and that no secret value is ever printed.

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
MIGRATE="$TESTS_DIR/../bin/scm-auth-migrate"
STATUS="$TESTS_DIR/../bin/scm-auth-status"
SENTINEL='SENTINEL-SECRET-0123456789'
PREFIX='# scm-auth-migrate: '

declare -i OVERALL_RESULT=0
WORK=""
# shellcheck disable=SC2329
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
WORK="$(mktemp -d /tmp/linux-configs-scm-auth-migrate-test.XXXXXX)"
STUB_LOG="$WORK/stub.log"
STATE="$WORK/state"
mkdir -p "$WORK/bin" "$STATE"

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

function write_stub() {
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$WORK/bin/$1"
    chmod +x "$WORK/bin/$1"
}

# systemctl: logs argv; 'ssh-agent.service' is unknown to exercise failure tolerance.
# ssh-agent.socket stays 'enabled' after disable (vendor symlink) unless STUB_DISABLE_WORKS=1,
# and reports 'masked' once masked; state lives in $STATE so 'rm -f $STATE/*' resets it
write_stub systemctl 'printf "systemctl %s\n" "$*" >> "$STUB_LOG"
[[ "$*" == *ssh-agent.service* ]] && { echo "Unit ssh-agent.service does not exist" >&2; exit 1; }
case "$*" in
"--user disable --now ssh-agent.socket") [[ "${STUB_DISABLE_WORKS:-0}" == 1 ]] && touch "$STATE/sock-disabled" ;;
"--user mask --now ssh-agent.socket") touch "$STATE/sock-masked" ;;
"--user show-environment") [[ -e "$STATE/env-sock" ]] && echo "SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh"; echo "PATH=/usr/bin" ;;
"--user set-environment SSH_AUTH_SOCK="*) touch "$STATE/env-sock" ;;
"--user is-enabled ssh-agent.socket")
    if [[ -e "$STATE/sock-masked" ]]; then echo masked; exit 1; fi
    if [[ -e "$STATE/sock-disabled" ]]; then echo disabled; exit 1; fi
    echo enabled; exit 0 ;;
esac
[[ "$1 $2" == "--user is-enabled" ]] && { echo enabled; exit 0; }
exit 0'

# secret-tool: like the real tool, item path, label and secret value on stdout and the
# attribute lines on stderr; a cleared item disappears from later searches
write_stub secret-tool 'printf "secret-tool %s\n" "$*" >> "$STUB_LOG"
item() { printf "[%s]\nlabel = %s\nsecret = %s\n" "$1" "$2" "$SENTINEL"; shift 2; printf "attribute.%s\n" "$@" >&2; }
case "$1 $2 $3 $4" in
"search --all ssh-key gitlab_ed25519")
    [[ -e "$STATE/ssh" ]] || item /1641 "SSH gitlab_ed25519" "ssh-key = gitlab_ed25519" ;;
"search --all service forge")
    [[ -e "$STATE/forge-codeberg.org" ]] || item /1640 "forge: codeberg.org" "service = forge" "host = codeberg.org"
    [[ -e "$STATE/forge-github.com" ]] || item /1638 "forge: github.com" "service = forge" "host = github.com" ;;
"clear ssh-key gitlab_ed25519 ") touch "$STATE/ssh" ;;
"clear service forge host") touch "$STATE/forge-$5" ;;
esac
exit 0'

# git-credential-scm: logs argv; 'retag' prints labels/attributes like the real helper (one stale
# forge item and a duplicate until '--apply retag' ran), 'list' one line per item (2 tagged,
# 1 untagged until retagged); STUB_SCM_FAIL=1 makes everything but --version fail like a missing bus
write_stub git-credential-scm 'printf "git-credential-scm %s\n" "$*" >> "$STUB_LOG"
[[ "$*" == --version ]] && { echo "git-credential-scm 0.1.0"; exit 0; }
[[ "${STUB_SCM_FAIL:-0}" == 1 ]] && { echo "git-credential-scm: cannot connect to the session bus" >&2; exit 1; }
suffix=" (preview; run with --apply to change)"
[[ "$1" == --apply ]] && suffix=" (applied)"
case "$*" in
retag | "--apply retag")
    if [[ -e "$STATE/retagged" ]]; then
        printf "ok      scm-auth: https://github.com/\nretag: 0 to update, 0 duplicate(s) to delete, 2 already tagged, 0 skipped%s\n" "$suffix"
    else
        printf "retag   forge: github.com -> scm-auth: https://github.com/ (tool=forge)\n"
        printf "delete  Git: https://github.com/ (duplicate of a newer item)\n"
        printf "retag: 1 to update, 1 duplicate(s) to delete, 1 already tagged, 0 skipped%s\n" "$suffix"
    fi
    [[ "$1" == --apply ]] && touch "$STATE/retagged" ;;
get)
    # github.com has a token (the sentinel); every other host has none
    grep -qx host=github.com && printf "username=tester\npassword=gho_%s\n" "$SENTINEL" ;;
list | "--all list")
    printf "2026-11-01T10:00:00Z\tscm-auth: https://github.com/\tapplication=scm-auth protocol=https server=github.com tool=git\n"
    printf "2026-11-01T10:00:00Z\tscm-auth: https://huggingface.co/\tapplication=scm-auth protocol=https server=huggingface.co tool=hf\n"
    [[ "$1" == --all && ! -e "$STATE/retagged" ]] && printf "2026-10-01T10:00:00Z\tGit: https://codeberg.org/\tprotocol=https server=codeberg.org\n" ;;
*) exit 2 ;;
esac
exit 0'

# ssh: '-G' resolves pinned.example with an IdentityAgent pin, '-T' greets like GitHub
write_stub ssh 'printf "ssh %s\n" "$*" >> "$STUB_LOG"
if [[ "$1" == -G ]]; then
    host="${2#*@}"
    if [[ "$host" == tangled.org && -n "${STUB_TANGLED_USER:-}" ]]; then
        printf "user %s\n" "$STUB_TANGLED_USER"
    else
        printf "user git\n"
    fi
    printf "hostname %s\n" "$host"
    [[ "$host" == pinned.example ]] && printf "identityagent /run/user/1000/gnupg/S.gpg-agent.ssh\n"
    exit 0
fi
# a Tangled knot greets any key, but identifies it only by the atproto handle as login name
case "${!#}" in
git@tangled.org) printf "Hi there! This is the knot1.tangled.sh knot.\n"; exit 0 ;;
*@tangled.org) printf "Hi @%s! You'"'"'re authenticated to knot1.tangled.sh knot.\n" "${STUB_TANGLED_USER:-?}"; exit 0 ;;
esac
printf "Hi tester! You'"'"'ve successfully authenticated, but GitHub does not provide shell access.\n" >&2
exit 1'

# journalctl: the user journal holds whatever $STATE/journal holds (skipped OAuth requests)
write_stub journalctl 'printf "journalctl %s\n" "$*" >> "$STUB_LOG"
cat "$STATE/journal" 2>/dev/null || true'

# ssh-add: three keys in gcr-ssh-agent, none in gpg-agent; fingerprints must never be printed
write_stub ssh-add 'printf "ssh-add %s\n" "$*" >> "$STUB_LOG"
if [[ "$SSH_AUTH_SOCK" == */gcr/ssh ]]; then
    for i in 1 2 3; do printf "256 SHA256:FAKEFINGERPRINT%s key%s (ED25519)\n" "$i" "$i"; done
    exit 0
fi
echo "The agent has no identities."
exit 1'

write_stub gpgconf 'printf "%s\n" "$GPG_SOCKET"'

# curl: logs argv and whether the token arrived on the --config stdin; GitHub-style 200 reply
write_stub curl 'printf "curl %s\n" "$*" >> "$STUB_LOG"
config="$(cat)"
[[ "$config" == *"Authorization: Bearer gho_$SENTINEL"* ]] && printf "curl-config-has-token\n" >> "$STUB_LOG"
while (( $# > 0 )); do [[ "$1" == -o ]] && out="$2"; shift; done
printf "{\"login\":\"tester\"}" > "$out"
printf 200'

# stubs see the work paths through the environment
export STUB_LOG STATE SENTINEL
# the scripts under test must never reach a real git-credential-scm (and the live keyring)
export SCM_AUTH_HELPER="$WORK/bin/git-credential-scm"
export GPG_SOCKET="$WORK/run/gnupg/S.gpg-agent.ssh"
export GITHUB_TOKEN="$SENTINEL" HF_TOKEN="$SENTINEL"

# ssh config fixture: IdentityAgent pins in several spellings, missing/existing/untestable
# IdentityFile entries
function make_home() {
    local home="$1"
    mkdir -p "$home/.ssh" "$home/.config/systemd/user" "$home/.local/bin"
    : > "$home/.ssh/github_ed25519"
    : > "$home/.ssh/pubonly_ed25519.pub"
    cat > "$home/.ssh/config" <<'EOF'
Host github.com
    Tag scm
    IdentityFile ~/.ssh/github_ed25519
    IdentityFile ~/.ssh/github_ed25519-sk
    IdentityFile "%d/.ssh/quoted_missing"
    IdentityFile=${HOME}/.ssh/eq_missing
    IdentityFile ${HOME}/.ssh/pubonly_ed25519
    IdentityFile ~/.ssh/%h_ed25519
    IdentityFile none
    IdentityFile relative_key

Host gitlab.com
    identityagent $XDG_RUNTIME_DIR/openssh_agent
    AddKeysToAgent yes
	IDENTITYAGENT=${XDG_RUNTIME_DIR}/other_agent
# IdentityAgent already-commented

Host *
  IdentityAgent ~/.gnupg/S.gpg-agent.ssh
    IdentityAgent %d/.gnupg/S.gpg-agent.ssh
EOF
    chmod 0640 "$home/.ssh/config"
    printf '[Service]\nExecStart=/usr/bin/ssh-add\n' > "$home/.config/systemd/user/ssh-add-gitlab.service"
    printf '#!/bin/sh\n' > "$home/.local/bin/ssh-askpass-keyring"
}

function expected_config() {
    cat <<EOF
Host github.com
    Tag scm
    IdentityFile ~/.ssh/github_ed25519
${PREFIX}    IdentityFile ~/.ssh/github_ed25519-sk
${PREFIX}    IdentityFile "%d/.ssh/quoted_missing"
${PREFIX}    IdentityFile=\${HOME}/.ssh/eq_missing
    IdentityFile \${HOME}/.ssh/pubonly_ed25519
    IdentityFile ~/.ssh/%h_ed25519
    IdentityFile none
    IdentityFile relative_key

Host gitlab.com
${PREFIX}    identityagent \$XDG_RUNTIME_DIR/openssh_agent
    AddKeysToAgent yes
${PREFIX}	IDENTITYAGENT=\${XDG_RUNTIME_DIR}/other_agent
# IdentityAgent already-commented

Host *
${PREFIX}  IdentityAgent ~/.gnupg/S.gpg-agent.ssh
${PREFIX}    IdentityAgent %d/.gnupg/S.gpg-agent.ssh
EOF
}

function run_migrate() {
    local home="$1"
    shift
    : > "$STUB_LOG"
    PATH="$WORK/bin:$PATH" HOME="$home" XDG_RUNTIME_DIR="${MIGRATE_RUNTIME_DIR:-$WORK/norun}" \
        SCM_AUTH_HELPER="${MIGRATE_HELPER-$SCM_AUTH_HELPER}" \
        bash "$MIGRATE" "$@" > "$WORK/out.log" 2>&1
}

function backups_of() {
    local -a files=("$1"/.ssh/config.bak.*)
    echo "${#files[@]}"
}

function logged() {
    grep -E "^$1 " "$STUB_LOG" | sed "s/^$1 //" || true
}

# shellcheck disable=SC2329 # invoked indirectly through check
function no_sentinel() {
    ! grep -qF -- "$SENTINEL" "$@"
}

# argument handling
check "-h prints usage" bash -c '"$1" -h | grep -q "^Usage: scm-auth-migrate"' _ "$MIGRATE"
check "unknown argument exits 2" bash -c '"$1" --bogus 2>/dev/null; test $? -eq 2' _ "$MIGRATE"

# dry run (default): nothing changes, actions only planned
HOME1="$WORK/home1"
make_home "$HOME1"
cp "$HOME1/.ssh/config" "$WORK/original-config"
run_migrate "$HOME1"
check "dry run exits 0" test $? -eq 0
check "dry run leaves ~/.ssh/config unchanged" cmp -s "$HOME1/.ssh/config" "$WORK/original-config"
check "dry run creates no backup" test "$(backups_of "$HOME1")" -eq 0
check "dry run shows the planned diff" grep -qF "+${PREFIX}  IdentityAgent ~/.gnupg/S.gpg-agent.ssh" "$WORK/out.log"
check "dry run plans the gcr socket enable" grep -qx 'would run: systemctl --user enable gcr-ssh-agent.socket' "$WORK/out.log"
check "dry run plans the keyring clear" grep -qx 'would run: secret-tool clear ssh-key gitlab_ed25519' "$WORK/out.log"
check "dry run calls only read-only systemctl" test -z "$(logged systemctl | grep -v '^--user is-enabled ' || true)"
check "dry run plans the conditional mask" grep -qx 'would run (only if ssh-agent.socket is still enabled after disable): systemctl --user mask --now ssh-agent.socket' "$WORK/out.log"
check "dry run clears no keyring item" test -z "$(logged secret-tool | grep '^clear' || true)"
check "dry run previews the retag only" diff -u <(printf 'retag\n') <(logged git-credential-scm)
check "dry run shows the retag plan" grep -qx 'retag   forge: github.com -> scm-auth: https://github.com/ (tool=forge)' "$WORK/out.log"
check "dry run shows the retag summary" grep -qx 'retag: 1 to update, 1 duplicate(s) to delete, 1 already tagged, 0 skipped (preview; run with --apply to change)' "$WORK/out.log"
check "dry run does not retag" test ! -e "$STATE/retagged"
check "dry run keeps the legacy unit" test -f "$HOME1/.config/systemd/user/ssh-add-gitlab.service"
check "dry run keeps the askpass helper" test -f "$HOME1/.local/bin/ssh-askpass-keyring"
check "dry run says how to apply" grep -q 're-run with --apply' "$WORK/out.log"
check "dry run never prints a secret value" no_sentinel "$WORK/out.log"
check "explicit --dry-run changes nothing" bash -c 'PATH="$1:$PATH" HOME="$2" "$3" --dry-run >/dev/null 2>&1 && cmp -s "$2/.ssh/config" "$4"' _ "$WORK/bin" "$HOME1" "$MIGRATE" "$WORK/original-config"

# apply: backup, rewrite, unit/keyring/file cleanup
run_migrate "$HOME1" --apply
check "apply exits 0 despite a failing unit" test $? -eq 0
check "apply rewrites ~/.ssh/config as expected" diff -u <(expected_config) "$HOME1/.ssh/config"
check "apply keeps the config mode" test "$(stat -c '%a' "$HOME1/.ssh/config")" = 640
check "apply creates one backup" test "$(backups_of "$HOME1")" -eq 1
BACKUP=("$HOME1"/.ssh/config.bak.*)
check "backup holds the original config" cmp -s "${BACKUP[0]}" "$WORK/original-config"
check "backup name is timestamped" bash -c '[[ "${1##*/}" =~ ^config\.bak\.[0-9]{8}-[0-9]{6}$ ]]' _ "${BACKUP[0]}"
check "backup mode is 0600" test "$(stat -c '%a' "${BACKUP[0]}")" = 600
check "apply prints the diff" grep -qF "+${PREFIX}    IdentityFile ~/.ssh/github_ed25519-sk" "$WORK/out.log"
check "apply runs the expected systemctl calls" diff -u <(printf '%s\n' \
    '--user enable gcr-ssh-agent.socket' \
    '--user disable --now ssh-agent.socket' \
    '--user disable --now ssh-agent.service' \
    '--user disable --now ssh-add-gitlab.service' \
    '--user is-enabled ssh-agent.socket' \
    '--user mask --now ssh-agent.socket' \
    '--user daemon-reload') <(logged systemctl)
check "apply explains the mask" grep -q "ssh-agent.socket is still 'enabled' after disable (vendor/global symlink); masking it" "$WORK/out.log"
check "apply reports the failing unit and continues" grep -q "warning: 'systemctl --user disable --now ssh-agent.service' failed" "$WORK/out.log"
check "apply clears only the legacy SSH keyring item via secret-tool" diff -u <(printf '%s\n' \
    'clear ssh-key gitlab_ed25519') <(logged secret-tool | grep '^clear' | sort)
check "apply uses secret-tool only for the SSH item (no forge items)" test -z "$(logged secret-tool | grep -v -e '^search --all ssh-key gitlab_ed25519$' -e '^clear ssh-key gitlab_ed25519$' || true)"
check "apply runs retag --apply (action last)" diff -u <(printf -- '--apply retag\n') <(logged git-credential-scm)
check "apply shows the applied retag summary" grep -qx 'retag: 1 to update, 1 duplicate(s) to delete, 1 already tagged, 0 skipped (applied)' "$WORK/out.log"
check "apply retagged the keyring items" test -e "$STATE/retagged"
check "apply deletes the legacy unit file" test ! -e "$HOME1/.config/systemd/user/ssh-add-gitlab.service"
check "apply deletes the askpass helper" test ! -e "$HOME1/.local/bin/ssh-askpass-keyring"
check "apply keeps existing identity files" test -f "$HOME1/.ssh/github_ed25519"
check "apply never prints a secret value" no_sentinel "$WORK/out.log"

# second apply: idempotent
cp "$HOME1/.ssh/config" "$WORK/migrated-config"
sleep 1
run_migrate "$HOME1" --apply
check "second apply exits 0" test $? -eq 0
check "second apply leaves the config unchanged" cmp -s "$HOME1/.ssh/config" "$WORK/migrated-config"
check "second apply creates no new backup" test "$(backups_of "$HOME1")" -eq 1
check "second apply clears nothing" test -z "$(logged secret-tool | grep '^clear' || true)"
check "second apply re-runs the idempotent retag" diff -u <(printf -- '--apply retag\n') <(logged git-credential-scm)
check "second apply reports config/files/keyring already migrated" grep -q 'config/files/keyring already migrated; systemd actions re-applied (idempotent)' "$WORK/out.log"
check "second apply re-runs the idempotent systemctl calls" test -n "$(logged systemctl)"
check "second apply does not mask again" test -z "$(logged systemctl | grep '^--user mask' || true)"
check "dry run after mask plans no mask" bash -c 'PATH="$1:$PATH" HOME="$2" "$3" 2>&1 | grep -q "mask --now"; test $? -eq 1' _ "$WORK/bin" "$HOME1" "$MIGRATE"

# a user-level disable that works (no vendor symlink): no mask
HOME1B="$WORK/home1b"
make_home "$HOME1B"
rm -f "$STATE"/*
STUB_DISABLE_WORKS=1 run_migrate "$HOME1B" --apply
check "working disable: apply exits 0" test $? -eq 0
check "working disable: no mask" test -z "$(logged systemctl | grep '^--user mask' || true)"
check "working disable: state checked" test -n "$(logged systemctl | grep '^--user is-enabled ssh-agent.socket$' || true)"

# stopping ssh-agent.socket unsets SSH_AUTH_SOCK in the user manager: restored to the gcr socket
# when that socket exists, once
if command -v python3 >/dev/null; then
    mkdir -p "$WORK/run2/gcr"
    python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$WORK/run2/gcr/ssh"
    HOME1C="$WORK/home1c"
    make_home "$HOME1C"
    rm -f "$STATE"/*
    MIGRATE_RUNTIME_DIR="$WORK/run2" run_migrate "$HOME1C" --apply
    check "auth sock: restored to the gcr socket" grep -qx -- "--user set-environment SSH_AUTH_SOCK=$WORK/run2/gcr/ssh" <(logged systemctl)
    MIGRATE_RUNTIME_DIR="$WORK/run2" run_migrate "$HOME1C" --apply
    check "auth sock: not set again when present" test -z "$(logged systemctl | grep -- '--user set-environment' || true)"
    MIGRATE_RUNTIME_DIR="$WORK/run2" run_migrate "$HOME1C"
    check "auth sock: dry run sets nothing" test -z "$(logged systemctl | grep -v '^--user is-enabled ' || true)"
fi

# opt-out flags: no systemctl and no secret-tool at all
HOME2="$WORK/home2"
make_home "$HOME2"
rm -f "$STATE"/*
run_migrate "$HOME2" --apply --no-systemd --no-keyring
check "--no-systemd/--no-keyring apply exits 0" test $? -eq 0
check "--no-systemd calls no systemctl" test -z "$(logged systemctl)"
check "--no-keyring calls no secret-tool" test -z "$(logged secret-tool)"
check "--no-keyring runs no retag" test -z "$(logged git-credential-scm)"
check "--no-systemd keeps the unit file" test -f "$HOME2/.config/systemd/user/ssh-add-gitlab.service"
check "opt-out apply still migrates ~/.ssh/config" diff -u <(expected_config) "$HOME2/.ssh/config"
check "opt-out apply still removes the askpass helper" test ! -e "$HOME2/.local/bin/ssh-askpass-keyring"

# helper resolution and failures: found on PATH without SCM_AUTH_HELPER; a missing or failing
# helper is a warning in a dry run and makes --apply exit 1 after the other steps ran
HOME2B="$WORK/home2b"
make_home "$HOME2B"
rm -f "$STATE"/*
MIGRATE_HELPER='' run_migrate "$HOME2B" --no-systemd
check "helper on PATH: dry run exits 0" test $? -eq 0
check "helper on PATH: retag previewed" diff -u <(printf 'retag\n') <(logged git-credential-scm)
MIGRATE_HELPER="$WORK/missing/git-credential-scm" run_migrate "$HOME2B" --no-systemd
check "missing helper: dry run exits 0" test $? -eq 0
check "missing helper: dry run warns" grep -q 'warning: git-credential-scm not found (run ./install.sh scm-auth); keyring items not retagged' "$WORK/out.log"
check "missing helper: dry run reports the unpreviewed step" grep -q 'dry run: 1 step(s) could not be previewed' "$WORK/out.log"
check "missing helper: no helper fallback on PATH" test -z "$(logged git-credential-scm)"
check "missing helper: SSH item still planned" grep -qx 'would run: secret-tool clear ssh-key gitlab_ed25519' "$WORK/out.log"
RC=0
MIGRATE_HELPER="$WORK/missing/git-credential-scm" run_migrate "$HOME2B" --no-systemd --apply || RC=$?
check "missing helper: apply exits 1" test "$RC" -eq 1
check "missing helper: apply says incomplete" grep -q 'migration incomplete: 1 step(s) failed' "$WORK/out.log"
check "missing helper: apply still migrates ~/.ssh/config" diff -u <(expected_config) "$HOME2B/.ssh/config"
check "missing helper: apply still clears the SSH item" grep -qx 'clear ssh-key gitlab_ed25519' <(logged secret-tool)
RC=0
STUB_SCM_FAIL=1 run_migrate "$HOME2B" --no-systemd --apply || RC=$?
check "failing retag: apply exits 1" test "$RC" -eq 1
check "failing retag: warned with the exit code" grep -q "warning: '$WORK/bin/git-credential-scm --apply retag' failed (exit 1); keyring items not retagged" "$WORK/out.log"
check "failing retag: nothing retagged" test ! -e "$STATE/retagged"
check "helper runs never print a secret value" no_sentinel "$WORK/out.log"

# no ~/.ssh/config: that step is skipped, not failed (stubs stay first on PATH so the real
# systemctl/secret-tool are never reached)
HOME3="$WORK/home3"
mkdir -p "$HOME3"
run_migrate "$HOME3" --apply
check "no ~/.ssh/config: apply exits 0" test $? -eq 0
check "no ~/.ssh/config: reported" grep -q "/.ssh/config' not found" "$WORK/out.log"
check "no ~/.ssh/config: nothing created" test ! -e "$HOME3/.ssh/config"

# missing key material: a block whose IdentityFile lines are all missing keeps the plain ones and
# warns, but a '-sk' stub next to its plain sibling is commented out; a block with another key
# only loses its missing lines; top-level lines form their own block
function expected_mixed_config() {
    cat <<EOF
IdentityFile ~/.ssh/toplevel_missing

Host bitbucket.org
${PREFIX}    IdentityFile ~/.ssh/bitbucket_ed25519-sk
    IdentityFile ~/.ssh/bitbucket_ed25519

Host codeberg.org
${PREFIX}    IdentityFile ~/.ssh/codeberg_ed25519-sk
    IdentityFile ~/.ssh/codeberg_ed25519

Host lonesk.example
    IdentityFile ~/.ssh/lonesk_ed25519-sk
EOF
}

rm -f "$STATE"/*
HOME4="$WORK/home4"
mkdir -p "$HOME4/.ssh"
: > "$HOME4/.ssh/codeberg_ed25519.pub"
cat > "$HOME4/.ssh/config" <<'EOF'
IdentityFile ~/.ssh/toplevel_missing

Host bitbucket.org
    IdentityFile ~/.ssh/bitbucket_ed25519-sk
    IdentityFile ~/.ssh/bitbucket_ed25519

Host codeberg.org
    IdentityFile ~/.ssh/codeberg_ed25519-sk
    IdentityFile ~/.ssh/codeberg_ed25519

Host lonesk.example
    IdentityFile ~/.ssh/lonesk_ed25519-sk
EOF
cp "$HOME4/.ssh/config" "$WORK/original-config4"
run_migrate "$HOME4"
check "dry run warns for the top-level missing key" grep -qF "warning: no key material for $HOME4/.ssh/toplevel_missing (host block: (top level)); export it with: ssh-add -L | grep -F toplevel_missing > $HOME4/.ssh/toplevel_missing.pub" "$WORK/out.log"
check "dry run warns once for the all-missing block" test "$(grep -cF "warning: no key material for $HOME4/.ssh/bitbucket_ed25519" "$WORK/out.log")" -eq 1
check "dry run hints the plain key" grep -qF "warning: no key material for $HOME4/.ssh/bitbucket_ed25519 (host block: Host bitbucket.org); export it with: ssh-add -L | grep -F bitbucket_ed25519 > $HOME4/.ssh/bitbucket_ed25519.pub" "$WORK/out.log"
check "dry run plans to comment out the -sk stub next to its missing sibling" grep -qF "+${PREFIX}    IdentityFile ~/.ssh/bitbucket_ed25519-sk" "$WORK/out.log"
check "dry run keeps a lone -sk stub and hints its plain key" grep -qF "warning: no key material for $HOME4/.ssh/lonesk_ed25519-sk (host block: Host lonesk.example); export it with: ssh-add -L | grep -F lonesk_ed25519 > $HOME4/.ssh/lonesk_ed25519.pub" "$WORK/out.log"
check "dry run never suggests a -sk.pub export target" bash -c '! grep -q -- "-sk\.pub" "$1"' _ "$WORK/out.log"
check "dry run does not warn for the block with another key" bash -c '! grep -q "no key material for .*codeberg" "$1"' _ "$WORK/out.log"
check "dry run with warnings leaves the config unchanged" cmp -s "$HOME4/.ssh/config" "$WORK/original-config4"
run_migrate "$HOME4" --apply
check "apply exits 0 with warnings" test $? -eq 0
check "apply comments out the redundant/missing keys only" diff -u <(expected_mixed_config) "$HOME4/.ssh/config"
check "apply still warns once for the all-missing block" test "$(grep -cF "warning: no key material for $HOME4/.ssh/bitbucket_ed25519" "$WORK/out.log")" -eq 1
check "apply creates one backup for the rewrite" test "$(backups_of "$HOME4")" -eq 1
cp "$HOME4/.ssh/config" "$WORK/migrated-config4"
run_migrate "$HOME4" --apply
check "second apply leaves the config unchanged" cmp -s "$HOME4/.ssh/config" "$WORK/migrated-config4"
check "second apply creates no new backup" test "$(backups_of "$HOME4")" -eq 1
check "second apply keeps the warning for the all-missing block" test "$(grep -cF "warning: no key material for $HOME4/.ssh/bitbucket_ed25519" "$WORK/out.log")" -eq 1
run_migrate "$HOME4"
check "dry run after migration does not ask to apply" bash -c '! grep -q "re-run with --apply" "$1"' _ "$WORK/out.log"
check "dry run after migration reports config already migrated" grep -q 'config, files and keyring already migrated' "$WORK/out.log"

HOME5="$WORK/home5"
mkdir -p "$HOME5/.ssh"
cat > "$HOME5/.ssh/config" <<'EOF'
Host bitbucket.org
    IdentityFile ~/.ssh/bitbucket_ed25519-sk
    IdentityFile ~/.ssh/bitbucket_ed25519
EOF
run_migrate "$HOME5" --apply
check "all-missing block alone: -sk commented, plain kept" diff -u <(printf 'Host bitbucket.org\n%s    IdentityFile ~/.ssh/bitbucket_ed25519-sk\n    IdentityFile ~/.ssh/bitbucket_ed25519\n' "$PREFIX") "$HOME5/.ssh/config"
check "all-missing block alone: apply makes one backup" test "$(backups_of "$HOME5")" -eq 1
check "all-missing block alone: apply warns once" test "$(grep -cF "warning: no key material for $HOME5/.ssh/bitbucket_ed25519" "$WORK/out.log")" -eq 1
cp "$HOME5/.ssh/config" "$WORK/migrated-config5"
sleep 1
run_migrate "$HOME5" --apply
check "all-missing block alone: second apply leaves the config unchanged" cmp -s "$HOME5/.ssh/config" "$WORK/migrated-config5"
check "all-missing block alone: second apply makes no new backup" test "$(backups_of "$HOME5")" -eq 1
check "all-missing block alone: second apply still warns once" test "$(grep -cF "warning: no key material for $HOME5/.ssh/bitbucket_ed25519" "$WORK/out.log")" -eq 1

# a lone missing -sk stub (no plain sibling) is kept with a warning and is not a change
HOME6="$WORK/home6"
mkdir -p "$HOME6/.ssh"
printf 'Host lonesk.example\n    IdentityFile ~/.ssh/lonesk_ed25519-sk\n' > "$HOME6/.ssh/config"
cp "$HOME6/.ssh/config" "$WORK/original-config6"
run_migrate "$HOME6" --apply
check "lone -sk stub: config kept" cmp -s "$HOME6/.ssh/config" "$WORK/original-config6"
check "lone -sk stub: no backup" test "$(backups_of "$HOME6")" -eq 0
check "lone -sk stub: warned" grep -qF "warning: no key material for $HOME6/.ssh/lonesk_ed25519-sk" "$WORK/out.log"

# status: agent sockets for the key counts
if command -v python3 >/dev/null; then
    mkdir -p "$WORK/run/gcr" "$WORK/run/gnupg"
    python3 - "$WORK/run/gcr/ssh" "$GPG_SOCKET" <<'EOF'
import socket, sys
for path in sys.argv[1:]:
    socket.socket(socket.AF_UNIX).bind(path)
EOF
    rm -f "$STATE"/sock-*
    : > "$STUB_LOG"
    # LC_ALL=C: ASCII glyphs (+ ok, x problem, ! warning, * info, - skipped); not a tty: no colour
    STATUS_ENV=(PATH="$WORK/bin:$PATH" HOME="$HOME1" XDG_RUNTIME_DIR="$WORK/run" SSH_AUTH_SOCK="$WORK/run/gcr/ssh" LC_ALL=C)
    env "${STATUS_ENV[@]}" bash "$STATUS" github.com pinned.example tangled.org > "$WORK/status.log" 2>&1
    check "status exits 0" test $? -eq 0
    check "status has titled sections" test "$(grep -cxE 'SSH agents|Hosts|Git HTTPS credentials|Clients|Next steps' "$WORK/status.log")" -eq 5
    check "status names the agent" grep -qE '^  \+ SSH_AUTH_SOCK +gcr-ssh-agent  ' "$WORK/status.log"
    check "status counts gcr-ssh-agent keys" grep -qE '^  \* gcr-ssh-agent +3 keys  ' "$WORK/status.log"
    check "status counts gpg-agent keys" grep -qE '^  \* gpg-agent +0 keys  ' "$WORK/status.log"
    check "status lists the gcr socket unit" grep -qE '^  \+ gcr-ssh-agent.socket +enabled$' "$WORK/status.log"
    check "status flags an enabled ssh-agent.socket" grep -qE '^  x ssh-agent.socket +enabled  still starts at login$' "$WORK/status.log"
    check "status tells how to mask ssh-agent.socket" grep -qE '^  x ssh-agent.socket +scm-auth-migrate --apply \(masks ssh-agent.socket\)$' "$WORK/status.log"
    PROBLEMS_ENABLED="$(sed -n 's/^. Summary: \([0-9]*\) problem.*/\1/p' "$WORK/status.log")"
    touch "$STATE/sock-masked"
    env "${STATUS_ENV[@]}" bash "$STATUS" github.com pinned.example tangled.org > "$WORK/status-masked.log" 2>&1
    check "status shows a masked ssh-agent.socket as ok" grep -qE '^  \+ ssh-agent.socket +masked$' "$WORK/status-masked.log"
    PROBLEMS_MASKED="$(sed -n 's/^. Summary: \([0-9]*\) problem.*/\1/p' "$WORK/status-masked.log")"
    check "masked ssh-agent.socket is one problem fewer" test "$(( ${PROBLEMS_ENABLED:-0} - ${PROBLEMS_MASKED:-0} ))" -eq 1
    rm -f "$STATE/sock-masked"
    check "status prints a host table header" grep -qE '^  HOST +AGENT +SSH +API$' "$WORK/status.log"
    check "status shows an unpinned host" grep -qE '^  github.com +\+ gcr-ssh-agent ' "$WORK/status.log"
    check "status flags a pinned host" grep -qE '^  pinned.example +x gpg-agent pin ' "$WORK/status.log"
    check "status explains a pinned host" grep -qE '^  x pinned.example agent +IdentityAgent pinned to /run/user/1000/gnupg/S.gpg-agent.ssh;' "$WORK/status.log"
    check "status reports the ssh -T account" grep -qE '^  github.com +\+ gcr-ssh-agent +\+ tester ' "$WORK/status.log"
    check "status reports the API account and token type" grep -qE '^  github.com .* \+ tester \(gho_\)$' "$WORK/status.log"
    check "status API call targets the GitHub user endpoint" grep -q '^curl .*--config - https://api.github.com/user$' "$STUB_LOG"
    check "status passes the token to curl on stdin" grep -qx 'curl-config-has-token' "$STUB_LOG"
    check "status never passes the token in argv" bash -c '! grep "^curl " "$1" | grep -q "$2"' _ "$STUB_LOG" "$SENTINEL"
    check "status reports a host without token API" grep -qE '^  pinned.example .* - n/a \(no token API\)$' "$WORK/status.log"
    check "status ssh -T is bounded and non-interactive" grep -q '^ssh -T -o ConnectTimeout=8 -o ConnectionAttempts=1 -o BatchMode=yes .* git@github.com$' "$STUB_LOG"
    check "status flags an unidentified tangled key (Hi there!)" grep -qE '^  tangled.org +\+ gcr-ssh-agent +x key not identified' "$WORK/status.log"
    check "status tells to log in to tangled with the handle" grep -qE "^  x tangled.org ssh +the knot .*set 'User <your-handle>' under 'Host tangled.org'" "$WORK/status.log"
    check "status ends with the problem summary" grep -qE '^x Summary: [1-9][0-9]* problem\(s\)$' "$WORK/status.log"
    check "status prints no colour codes when not on a terminal" bash -c '! grep -q $'"'"'\e'"'"' "$1"' _ "$WORK/status.log"
    check "status never prints key fingerprints" bash -c '! grep -q FAKEFINGERPRINT "$1"' _ "$WORK/status.log"
    check "status never prints a secret value" no_sentinel "$WORK/status.log"
    : > "$STUB_LOG"
    env "${STATUS_ENV[@]}" STUB_TANGLED_USER=handle.example bash "$STATUS" tangled.org > "$WORK/status.log" 2>&1
    check "status logs in with the configured User" grep -q '^ssh -T .* handle.example@tangled.org$' "$STUB_LOG"
    check "status accepts an identified tangled key" grep -qE '^  tangled.org +\+ gcr-ssh-agent +\+ @handle.example ' "$WORK/status.log"
    env "${STATUS_ENV[@]}" LC_ALL=C.UTF-8 bash "$STATUS" --no-network github.com > "$WORK/status-utf8.log" 2>&1
    check "status uses Unicode glyphs in a UTF-8 locale" grep -qE '^  ✓ SSH_AUTH_SOCK ' "$WORK/status-utf8.log"
    printf 'no keyring token for https://gitlab.com; not starting the OAuth browser flow for non-interactive caller idea[42] (...)\n' > "$STATE/journal"
    env "${STATUS_ENV[@]}" bash "$STATUS" --no-network github.com > "$WORK/status.log" 2>&1
    check "status warns about OAuth requests skipped for background callers" grep -qE '^  ! oauth skipped \(24h\) +1 background request\(s\) missed the keyring' "$WORK/status.log"
    check "status reads only the scm-auth journal tag" grep -q '^journalctl --user -t scm-auth ' "$STUB_LOG"
    rm -f "$STATE/journal"
    : > "$STUB_LOG"
    env "${STATUS_ENV[@]}" bash "$STATUS" --no-network > "$WORK/status.log" 2>&1
    check "status --no-network checks all default hosts" test "$(grep -cE '^  [a-z.]+ +\+ gcr-ssh-agent +- skipped +- skipped$' "$WORK/status.log")" -eq 9
    check "status checks hf.co (Hugging Face SSH), not huggingface.co" grep -qE '^  hf.co +\+ ' "$WORK/status.log"
    check "status --no-network runs no ssh -T" test -z "$(logged ssh | grep -- '^-T' || true)"
    check "status --no-network runs no API call" test -z "$(logged curl)"
    check "status calls no secret-tool" test -z "$(logged secret-tool)"
else
    echo "SKIP: python3 not installed; status socket checks skipped"
fi

# status: git-credential-scm path, version and item counts (counted, never listed)
function run_status() {
    : > "$STUB_LOG"
    PATH="$WORK/bin:$PATH" HOME="$HOME1" XDG_RUNTIME_DIR="$WORK/norun" LC_ALL=C \
        bash "$STATUS" --no-network github.com > "$WORK/status-helper.log" 2>&1 || true
}
function status_problems() {
    sed -n 's/^. Summary: \([0-9]*\) problem.*/\1/p' "$WORK/status-helper.log"
}
rm -f "$STATE/retagged"
run_status
check "status reports the helper version and path" grep -qE "^  \+ git-credential-scm +git-credential-scm 0.1.0  $WORK/bin/git-credential-scm\$" "$WORK/status-helper.log"
check "status counts tagged and flags untagged items" grep -qE '^  x keyring items +2 tagged, 1 untagged  application=scm-auth$' "$WORK/status-helper.log"
check "status tells how to tag untagged items" grep -qE '^  x keyring items +scm-auth-migrate --apply$' "$WORK/status-helper.log"
check "status runs only --version and list" diff -u <(printf '%s\n' --version list '--all list') <(logged git-credential-scm)
check "status prints no item labels" bash -c '! grep -qE "(scm-auth|Git): https://" "$1"' _ "$WORK/status-helper.log"
check "status helper section never prints a secret value" no_sentinel "$WORK/status-helper.log"
PROBLEMS_UNTAGGED="$(status_problems)"
touch "$STATE/retagged"
run_status
check "status shows no untagged items after retag" grep -qE '^  \+ keyring items +2 tagged, 0 untagged' "$WORK/status-helper.log"
check "untagged items are one problem" test "$(( ${PROBLEMS_UNTAGGED:-0} - $(status_problems) ))" -eq 1
SCM_AUTH_HELPER="$WORK/missing/git-credential-scm" run_status
check "status flags a missing helper" grep -qE '^  x git-credential-scm +missing$' "$WORK/status-helper.log"
STUB_SCM_FAIL=1 run_status
check "status flags a failing list" grep -qE '^  x keyring items +list failed  session bus or keyring unavailable$' "$WORK/status-helper.log"
check "status hides the helper's stderr" bash -c '! grep -q "cannot connect" "$1"' _ "$WORK/status-helper.log"

check "status rejects an invalid host" bash -c '"$1" --no-network "bad;host" 2>/dev/null; test $? -eq 2' _ "$STATUS"

(( OVERALL_RESULT == 0 )) && echo "All scm-auth migrate/status tests passed" || echo "Some scm-auth migrate/status tests FAILED"
exit "$OVERALL_RESULT"
