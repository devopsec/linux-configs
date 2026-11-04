#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Validate a COSMIC (libcosmic) app or applet project: App ID consistency,
    desktop entry / metainfo rules for apps vs applets, trademark naming,
    freedesktop validators, then cargo fmt / clippy / test.

Usage:
    ${0##*/} [-h] [-n] [-s] [<project-dir>]

Arguments:
    -h              Show this usage documentation.
    -n              Skip cargo commands (metadata checks only).
    -s              Strict: treat warnings as failures.
    <project-dir>   Project root containing Cargo.toml (default: .).

Environment:
    DEBUG=1         Trace execution.

Exit Codes:
    0   all checks passed
    1   one or more checks failed (or warnings with -s)
    2   usage error
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

FAILS=0
WARNS=0
KIND=''
APPID=''
PKG_NAME=''

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "error: $1"; exit "${2:-1}"; }
ok() { printf '[ok]   %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; WARNS=$((WARNS + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
section() { printf '\n== %s ==\n' "$*"; }

# Value of key $2 in the [Desktop Entry] group of file $1.
desktop_key() {
    awk -v key="$2" '
        /^\[/ { main = ($0 == "[Desktop Entry]") }
        main && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
    ' "$1"
}

# First existing file among the arguments.
first_file() {
    local f
    for f in "$@"; do
        [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
    done
    return 0
}

detect_identity() {
    local -a ids=()
    section 'Identity'
    PKG_NAME="$(awk -F'"' '/^\[package\]/ { p = 1; next } /^\[/ { p = 0 } p && /^name[[:space:]]*=/ { print $2; exit }' Cargo.toml)"
    if grep -rqs 'cosmic::applet::run' src || grep -qE '^[[:space:]]*"applet"' Cargo.toml; then
        KIND='applet'
    else
        KIND='app'
    fi
    ok "package '${PKG_NAME:-<workspace>}' detected as $KIND"

    if grep -qs 'libcosmic' Cargo.toml; then ok 'depends on libcosmic'; else fail 'Cargo.toml does not reference libcosmic'; fi

    mapfile -t ids < <(grep -rhoE "const APP_ID: &'static str = \"[^\"]+\"" src 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/' | sort -u)
    case "${#ids[@]}" in
        0) fail 'no `const APP_ID` found under src/' ;;
        1) APPID="${ids[0]}"; ok "APP_ID = $APPID" ;;
        *) APPID="${ids[0]}"; fail "multiple APP_ID values in src/: ${ids[*]}" ;;
    esac
    if [[ "$APPID" == 'dev.mmurphy.Test' ]]; then
        fail 'APP_ID is the cosmic-app-template placeholder (dev.mmurphy.Test) — set your RDNN ID'
    fi

    if [[ -f justfile ]]; then
        local just_id
        just_id="$(sed -nE "s/^appid := '([^']+)'.*/\1/p" justfile | head -n 1)"
        if [[ -z "$just_id" ]]; then
            warn 'justfile has no `appid :=` variable'
        elif [[ "$just_id" == "$APPID" ]]; then
            ok 'justfile appid matches'
        else
            fail "justfile appid '$just_id' != APP_ID '$APPID'"
        fi
    else
        warn 'no justfile (COSMIC projects conventionally use just recipes)'
    fi

    if [[ -f Cargo.lock ]]; then ok 'Cargo.lock present'; else warn 'no Cargo.lock — `--locked` builds (template justfile, Flatpak) will fail'; fi
}

check_trademark() {
    section 'Naming (COSMIC trademark policy section 5)'
    if [[ "$APPID" == com.system76.* ]]; then
        warn "App ID uses reserved com.system76. prefix — only valid for official System76 software"
    else
        ok 'App ID not in reserved com.system76. namespace'
    fi
    if [[ "$PKG_NAME" == cosmic-* && "$PKG_NAME" != cosmic-ext-* ]]; then
        warn "package '$PKG_NAME' uses reserved 'cosmic-' prefix — third parties should use 'cosmic-ext-'"
    elif [[ -n "$PKG_NAME" ]]; then
        ok "package name '$PKG_NAME' acceptable"
    fi
}

check_desktop() {
    local file icon exec_bin out
    section 'Desktop entry'
    file="$(first_file target/xdgen/app.desktop "res/$APPID.desktop" "data/$APPID.desktop" "resources/$APPID.desktop" resources/app.desktop res/*.desktop data/*.desktop resources/*.desktop)"
    if [[ -z "$file" ]]; then
        fail 'no desktop entry found (resources/, res/, data/, target/xdgen/)'
        return 0
    fi
    ok "checking $file"
    [[ "$file" == target/xdgen/* ]] || warn 'validating source template; run `cargo build` to validate the xdgen-generated entry'

    icon="$(desktop_key "$file" Icon)"
    if [[ "$icon" == "$APPID" || "$icon" == "$APPID-symbolic" ]]; then ok "Icon=$icon"; else warn "Icon='$icon' differs from App ID '$APPID'"; fi
    exec_bin="$(desktop_key "$file" Exec)"
    exec_bin="${exec_bin%% *}"
    if [[ -n "$PKG_NAME" && "${exec_bin##*/}" != "$PKG_NAME" ]]; then
        warn "Exec binary '$exec_bin' != package name '$PKG_NAME' (fine if [[bin]] renames it)"
    fi

    if [[ "$KIND" == applet ]]; then
        if [[ "$(desktop_key "$file" X-CosmicApplet)" == true ]]; then ok 'X-CosmicApplet=true'; else fail 'applet needs X-CosmicApplet=true (else not listed in panel settings)'; fi
        if [[ "$(desktop_key "$file" NoDisplay)" == true ]]; then ok 'NoDisplay=true'; else fail 'applet needs NoDisplay=true (hide from launchers)'; fi
        if [[ -n "$(desktop_key "$file" X-CosmicHoverPopup)" ]]; then ok 'X-CosmicHoverPopup set'; else warn 'X-CosmicHoverPopup unset (official applets use Auto)'; fi
    else
        if [[ -z "$(desktop_key "$file" X-CosmicApplet)" ]]; then ok 'no applet keys on app'; else fail 'X-CosmicApplet set on a non-applet project'; fi
        [[ "$(desktop_key "$file" NoDisplay)" != true ]] || warn 'NoDisplay=true hides the app from launchers'
    fi

    if command -v desktop-file-validate &>/dev/null; then
        if out="$(desktop-file-validate "$file" 2>&1)"; then
            if [[ -z "$out" ]]; then
                ok 'desktop-file-validate clean'
            else
                warn 'desktop-file-validate hints:'
                printf '%s\n' "$out" | sed 's/^/       /'
            fi
        else
            fail 'desktop-file-validate errors:'
            printf '%s\n' "$out" | sed 's/^/       /'
        fi
    else
        warn 'desktop-file-validate not installed (desktop-file-utils)'
    fi
}

check_metainfo() {
    local file want other out
    section 'AppStream metainfo'
    file="$(first_file target/xdgen/app.metainfo.xml "res/$APPID.metainfo.xml" "data/$APPID.metainfo.xml" "resources/$APPID.metainfo.xml" resources/app.metainfo.xml res/*.metainfo.xml data/*.metainfo.xml resources/*.metainfo.xml)"
    if [[ -z "$file" ]]; then
        fail 'no *.metainfo.xml found'
        return 0
    fi
    ok "checking $file"
    if [[ "$KIND" == applet ]]; then
        want='com.system76.CosmicApplet'; other='com.system76.CosmicApplication'
    else
        want='com.system76.CosmicApplication'; other='com.system76.CosmicApplet'
    fi
    if grep -q "<id>$want</id>" "$file"; then ok "provides $want"; else fail "missing <provides><id>$want</id></provides> for a COSMIC $KIND"; fi
    ! grep -q "<id>$other</id>" "$file" || fail "declares $other but project is an $KIND"
    if grep -q "<id>$APPID</id>" "$file"; then ok 'component <id> matches APP_ID'; else fail "component <id> does not match APP_ID '$APPID'"; fi
    if grep -q "<launchable type=\"desktop-id\">$APPID.desktop</launchable>" "$file"; then ok 'launchable matches'; else warn "launchable should be $APPID.desktop"; fi
    grep -q '<description>' "$file" || warn 'no <description> (required for Flathub / COSMIC Store listings)'
    grep -q '<releases>' "$file" || warn 'no <releases> (required for Flathub)'

    if command -v appstreamcli &>/dev/null; then
        if out="$(appstreamcli validate --no-net "$file" 2>&1)"; then
            ok 'appstreamcli validate passed'
        else
            warn 'appstreamcli validate reported issues:'
            printf '%s\n' "$out" | sed 's/^/       /' | head -n 30
        fi
    else
        warn 'appstreamcli not installed (appstream)'
    fi
}

check_assets() {
    local -a svgs=() ftl=()
    section 'Icons & i18n'
    mapfile -t svgs < <(find resources res data -name '*.svg' -not -path '*/screenshots/*' 2>/dev/null)
    if (( ${#svgs[@]} > 0 )); then ok "${#svgs[@]} SVG icon(s) found"; else warn 'no SVG icon found under resources/, res/, data/'; fi
    if [[ -f i18n.toml ]]; then
        mapfile -t ftl < <(find i18n -name '*.ftl' 2>/dev/null)
        if (( ${#ftl[@]} > 0 )); then ok "i18n: ${#ftl[@]} .ftl file(s)"; else fail 'i18n.toml present but no i18n/**/*.ftl'; fi
    else
        warn 'no i18n.toml (strings not localizable)'
    fi
}

run_cargo() {
    local -a locked=()
    section 'Cargo quality gates'
    command -v cargo &>/dev/null || { fail 'cargo not installed'; return 0; }
    [[ -f Cargo.lock ]] && locked=(--locked)
    if cargo fmt --all -- --check >/dev/null 2>&1; then ok 'cargo fmt --check'; else fail 'cargo fmt --check (run: cargo fmt --all)'; fi
    log 'running cargo clippy (first run compiles libcosmic)'
    if cargo clippy --all-targets "${locked[@]}" -- -D warnings; then ok 'cargo clippy -D warnings'; else fail 'cargo clippy'; fi
    if cargo test "${locked[@]}"; then ok 'cargo test'; else fail 'cargo test'; fi
}

main() {
    local opt no_cargo=0 strict=0 dir
    while getopts ':hns' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            n) no_cargo=1 ;;
            s) strict=1 ;;
            *) die "unknown option -$OPTARG (see -h)" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (( $# <= 1 )) || die 'at most one project directory' 2
    dir="${1:-.}"
    [[ -f "$dir/Cargo.toml" ]] || die "no Cargo.toml in $dir" 2
    if [[ "${DEBUG:-0}" == 1 ]]; then set -x; fi
    cd "$dir"
    printf 'project: %s\n' "$(pwd)"

    detect_identity
    check_trademark
    check_desktop
    check_metainfo
    check_assets
    (( no_cargo == 1 )) || run_cargo

    section 'Summary'
    printf 'kind: %s, app id: %s, failures: %d, warnings: %d\n' "$KIND" "${APPID:-?}" "$FAILS" "$WARNS"
    (( FAILS == 0 )) || exit 1
    (( strict == 0 || WARNS == 0 )) || exit 1
}

main "$@"
