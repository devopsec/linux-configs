#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Scaffold a new COSMIC application or panel applet from the official
    pop-os template using cargo-generate, enforce COSMIC naming rules, and
    apply known template fixes.

Usage:
    ${0##*/} [-h] -t <app|applet> -n <name> -i <app-id> [-d <description>]
             [-l <license>] [-r <repo-url>] [-o <parent-dir>] [-L] [-c] [-N] [-O]

Arguments:
    -h                  Show this usage documentation.
    -t <app|applet>     Template type (required).
    -n <name>           Crate/binary name, kebab-case (required). Third-party
                        projects should use the 'cosmic-ext-' prefix.
    -i <app-id>         RDNN App ID, e.g. io.github.user.MyApp (required).
    -d <description>    One-line description (default: template default).
    -l <license>        SPDX license expression (default: MPL-2.0).
    -r <repo-url>       https:// repository URL (default: template default).
    -o <parent-dir>     Directory to create the project in (default: .).
    -L                  Use the cached template from upstream.sh instead of GitHub.
    -c                  Run 'cargo check' after generating (slow: builds libcosmic).
    -N                  Skip 'cargo generate-lockfile' (offline).
    -O                  Official System76 project: allow com.system76.* IDs and
                        the bare 'cosmic-' prefix (trademark policy section 5).

Examples:
    ${0##*/} -t app -n cosmic-ext-notes -i io.github.jdoe.CosmicExtNotes \\
        -d 'Quick notes for the COSMIC desktop' -r https://github.com/jdoe/cosmic-ext-notes
    ${0##*/} -t applet -n cosmic-ext-applet-cpu -i io.github.jdoe.CosmicExtAppletCpu -o ~/src

Exit Codes:
    0   project created
    1   failure (dependency, generation, post-processing)
    2   usage / validation error

Requirements:
    cargo, cargo-generate (cargo install cargo-generate), git, network access
    (unless -L and -N).
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

CACHE_DIR="${COSMIC_SRC_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cosmic-dev-src}"
# Flathub-compatible ID (mirrors cosmic-app-template cargo-generate.toml).
APPID_RE='^([a-z]|_[0-9])[a-z0-9_]*(\.([a-z]|_[0-9])[a-z0-9_]*){1,3}\.([A-Za-z]|_[0-9])[A-Za-z0-9_-]*$'
# Additional constraint from cosmic-applet-template cargo-generate.toml.
APPLET_APPID_RE='^[a-zA-Z0-9]+\.[a-zA-Z0-9]+\.[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)?$'
NAME_RE='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
LICENSE_RE='^[A-Za-z0-9.+-]+( (AND|OR|WITH) [A-Za-z0-9.+-]+)*$'
URL_RE='^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~-]+)*/?$'
# Characters that would break the TOML/XML/desktop files the template writes.
BAD_DESC_RE='["\\<>&]'

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "error: $1"; exit "${2:-1}"; }

validate_inputs() {
    local kind="$1" name="$2" appid="$3" desc="$4" license="$5" repo="$6" official="$7"
    case "$kind" in app | applet) ;; *) die "-t must be 'app' or 'applet'" 2 ;; esac
    [[ -n "$name" && -n "$appid" ]] || die 'missing required -n <name> and/or -i <app-id>' 2
    [[ "$name" =~ $NAME_RE && ${#name} -le 64 ]] || die "invalid name '$name' (kebab-case, <=64 chars)" 2
    [[ "$appid" =~ $APPID_RE ]] || die "invalid App ID '$appid' (RDNN, 3-5 segments, lowercase except last)" 2
    if [[ "$kind" == applet && ! "$appid" =~ $APPLET_APPID_RE ]]; then
        die "applet App ID '$appid' must have 3-4 segments, no '_' in the first two" 2
    fi
    if [[ -n "$desc" && ( "$desc" =~ $BAD_DESC_RE || "$desc" == *$'\n'* || ${#desc} -gt 200 ) ]]; then
        die 'description must be one line <=200 chars without quotes, backslashes, <, >, &' 2
    fi
    [[ "$license" =~ $LICENSE_RE ]] || die "invalid SPDX license expression '$license'" 2
    [[ -z "$repo" || "$repo" =~ $URL_RE ]] || die "invalid repository URL '$repo' (https only)" 2

    if (( official == 0 )); then
        [[ "$appid" != com.system76.* ]] \
            || die 'com.system76.* App IDs are reserved for official COSMIC software (TRADEMARK.md 5.1); use -O only if this is a System76 project' 2
        if [[ "$name" == cosmic-* && "$name" != cosmic-ext-* ]]; then
            die "'cosmic-' package prefix is reserved; use 'cosmic-ext-${name#cosmic-}' (TRADEMARK.md 5.2) or -O" 2
        fi
        [[ "$name" == cosmic-ext-* ]] || log "note: third-party COSMIC projects are encouraged to use the 'cosmic-ext-' prefix"
    fi
}

# Replace the app template's hard-coded APP_ID and verify consistency.
post_process() {
    local project="$1" appid="$2" found
    if [[ -f "$project/src/app.rs" ]]; then
        sed -i -E "s/(const APP_ID: &'static str = \")[^\"]*(\";)/\\1${appid}\\2/" "$project/src/app.rs"
        found="$(grep -oE "const APP_ID: &'static str = \"[^\"]+\"" "$project/src/app.rs" | sed -E 's/.*"([^"]+)"/\1/')"
        [[ "$found" == "$appid" ]] || die "APP_ID in src/app.rs is '$found', expected '$appid'"
    fi
    grep -q "^appid := '${appid}'" "$project/justfile" \
        || log "warning: justfile appid does not match '$appid' — check $project/justfile"
}

main() {
    local opt kind='' name='' appid='' desc='' license='MPL-2.0' repo='' outdir='.'
    local use_cache=0 do_check=0 no_lock=0 official=0 project script_dir
    local -a gen=()

    while getopts ':ht:n:i:d:l:r:o:LcNO' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            t) kind="$OPTARG" ;;
            n) name="$OPTARG" ;;
            i) appid="$OPTARG" ;;
            d) desc="$OPTARG" ;;
            l) license="$OPTARG" ;;
            r) repo="$OPTARG" ;;
            o) outdir="$OPTARG" ;;
            L) use_cache=1 ;;
            c) do_check=1 ;;
            N) no_lock=1 ;;
            O) official=1 ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG (see -h)" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (( $# == 0 )) || die "unexpected arguments: $*" 2
    if [[ "${DEBUG:-0}" == 1 ]]; then set -x; fi

    validate_inputs "$kind" "$name" "$appid" "$desc" "$license" "$repo" "$official"

    command -v cargo &>/dev/null || die 'missing dependency: cargo (https://rustup.rs)'
    cargo generate --version &>/dev/null || die 'missing dependency: cargo-generate (cargo install cargo-generate)'
    [[ -d "$outdir" ]] || die "output directory does not exist: $outdir" 2
    outdir="$(realpath "$outdir")"
    project="$outdir/$name"
    [[ ! -e "$project" ]] || die "refusing to overwrite existing path: $project" 2

    gen=(cargo generate)
    if (( use_cache == 1 )); then
        [[ -d "$CACHE_DIR/cosmic-$kind-template" ]] || die "template not cached; run: upstream.sh sync"
        gen+=(--path "$CACHE_DIR/cosmic-$kind-template")
    else
        gen+=(--git "https://github.com/pop-os/cosmic-$kind-template")
    fi
    gen+=(--name "$name" --destination "$outdir" --silent --vcs git --define "appid=$appid" --define "license=$license")
    [[ -n "$desc" ]] && gen+=(--define "description=$desc")
    [[ -n "$repo" ]] && gen+=(--define "repository-url=$repo")

    log "generating $kind '$name' ($appid) in $outdir"
    "${gen[@]}" || die 'cargo generate failed'
    [[ -f "$project/Cargo.toml" ]] || die "generation did not produce $project/Cargo.toml"

    post_process "$project" "$appid"

    if (( no_lock == 0 )); then
        log 'generating Cargo.lock (template justfile builds with --locked)'
        (cd "$project" && cargo generate-lockfile) || die 'cargo generate-lockfile failed'
    fi
    if (( do_check == 1 )); then
        log 'running cargo check (first build compiles libcosmic; this takes a while)'
        (cd "$project" && cargo check) || die 'cargo check failed'
    fi

    script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    printf 'created: %s\nnext:\n' "$project"
    printf '  cd %q\n' "$project"
    printf '  %s/upstream.sh rev .        # libcosmic commit + features\n' "$script_dir"
    if [[ "$kind" == applet ]]; then
        printf '  just prefix="$HOME/.local" install   # then Settings > Desktop > Panel > Applets\n'
    else
        printf '  just run\n'
    fi
    printf '  %s/validate-project.sh .\n' "$script_dir"
    printf 'review: README.md, resources/*.desktop, resources/*.metainfo.xml, i18n/en/*.ftl, icon SVG\n'
}

main "$@"
