#!/usr/bin/env bash

usage() {
    cat <<EOF
Summary:
    Generate a Flatpak manifest skeleton for a COSMIC app (Flathub, using
    com.system76.Cosmic.BaseApp) or applet (pop-os/cosmic-flatpak), with
    least-privilege finish-args, and optionally cargo-sources.json.

Usage:
    ${0##*/} [-h] [-p <project-dir>] [-o <manifest>] [-g <git-url> -c <commit>]
             [-R <runtime-version>] [-x <finish-arg>]... [-s] [-f]

Arguments:
    -h                    Show this usage documentation.
    -p <project-dir>      Project root (default: .).
    -o <manifest>         Output path (default: <project>/<APP_ID>.json).
    -g <git-url>          https:// git source URL for publishing (needs -c).
    -c <commit>           40-char commit SHA pinned for the git source.
                          Without -g/-c a local {"type":"dir"} source is used
                          (for local test builds only; never submit it).
    -R <runtime-version>  org.freedesktop.Platform version (default: ${DEFAULT_RUNTIME}).
                          For apps it must match com.system76.Cosmic.BaseApp.
    -x <finish-arg>       Extra finish-arg, repeatable (e.g. -x --share=network).
    -s                    Also generate cargo-sources.json next to the manifest
                          (needs FLATPAK_CARGO_GENERATOR=/path/to/flatpak-cargo-generator.py
                          or flatpak-cargo-generator.py on PATH; uses 'uv' if present).
    -f                    Overwrite existing output files.

Examples:
    ${0##*/} -p . -s
    ${0##*/} -p . -g https://github.com/me/cosmic-ext-foo.git -c <sha> -x --share=network -s

Exit Codes:
    0   manifest written
    1   failure
    2   usage / validation error

Requirements:
    python3 (JSON generation); for -s: flatpak-cargo-generator.py + aiohttp, tomlkit.
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

DEFAULT_RUNTIME='25.08'
FINISH_ARG_RE='^--[a-z-]+(=[A-Za-z0-9_./:*~-]+)?$'
URL_RE='^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~-]+)*(\.git)?$'

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "error: $1"; exit "${2:-1}"; }

# Echo first existing path among arguments (relative to cwd), or nothing.
first_file() {
    local f
    for f in "$@"; do
        [[ -f "$f" ]] && { printf '%s' "$f"; return 0; }
    done
    return 0
}

run_cargo_generator() {
    local out="$1" gen="${FLATPAK_CARGO_GENERATOR:-}"
    if [[ -z "$gen" ]]; then
        gen="$(command -v flatpak-cargo-generator.py || true)"
    fi
    [[ -n "$gen" && -f "$gen" ]] || die 'flatpak-cargo-generator.py not found; set FLATPAK_CARGO_GENERATOR (see references/packaging.md)'
    [[ -f Cargo.lock ]] || die 'Cargo.lock missing; run cargo generate-lockfile first'
    log "generating $out from Cargo.lock"
    if command -v uv &>/dev/null; then
        uv run --quiet --no-project --with aiohttp --with tomlkit python "$gen" Cargo.lock -o "$out"
    else
        python3 "$gen" Cargo.lock -o "$out"
    fi
}

main() {
    local opt project='.' output='' git_url='' commit='' runtime="$DEFAULT_RUNTIME" gen_sources=0 force=0
    local kind appid pkg bin desktop metainfo icon symbolic gpu=0 sources_out
    local -a extra=() args=()

    while getopts ':hp:o:g:c:R:x:sf' opt; do
        case "$opt" in
            h) usage; exit 0 ;;
            p) project="$OPTARG" ;;
            o) output="$OPTARG" ;;
            g) git_url="$OPTARG" ;;
            c) commit="$OPTARG" ;;
            R) runtime="$OPTARG" ;;
            x) extra+=("$OPTARG") ;;
            s) gen_sources=1 ;;
            f) force=1 ;;
            :) die "option -$OPTARG requires an argument" 2 ;;
            *) die "unknown option -$OPTARG (see -h)" 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (( $# == 0 )) || die "unexpected arguments: $*" 2
    if [[ "${DEBUG:-0}" == 1 ]]; then set -x; fi

    command -v python3 &>/dev/null || die 'missing dependency: python3'
    [[ -f "$project/Cargo.toml" ]] || die "no Cargo.toml in $project" 2
    [[ "$runtime" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || die "invalid runtime version '$runtime' (e.g. 25.08)" 2
    if [[ -n "$git_url" || -n "$commit" ]]; then
        [[ "$git_url" =~ $URL_RE ]] || die "invalid -g URL '$git_url' (https only)" 2
        [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die '-c must be a full 40-char commit SHA' 2
    fi
    for opt in "${extra[@]}"; do
        [[ "$opt" =~ $FINISH_ARG_RE ]] || die "invalid finish-arg '$opt'" 2
    done

    project="$(realpath "$project")"
    # Resolve -o against the caller's cwd before changing directory.
    [[ -z "$output" ]] || output="$(realpath -m "$output")"
    cd "$project"

    appid="$(grep -rhoE "const APP_ID: &'static str = \"[^\"]+\"" src 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/' | head -n 1)"
    [[ -n "$appid" ]] || die 'could not find `const APP_ID` under src/'
    [[ "$appid" != 'dev.mmurphy.Test' ]] || die 'APP_ID is still the template placeholder'
    pkg="$(awk -F'"' '/^\[package\]/ { p = 1; next } /^\[/ { p = 0 } p && /^name[[:space:]]*=/ { print $2; exit }' Cargo.toml)"
    bin="$(awk -F'"' '/^\[\[bin\]\]/ { b = 1; next } /^\[/ { b = 0 } b && /^name[[:space:]]*=/ { print $2; exit }' Cargo.toml)"
    bin="${bin:-$pkg}"
    [[ -n "$bin" ]] || die 'could not determine binary name from Cargo.toml'
    if grep -rqs 'cosmic::applet::run' src || grep -qE '^[[:space:]]*"applet"' Cargo.toml; then kind='applet'; else kind='app'; fi
    grep -qE '"wgpu"|libcosmic/wgpu' Cargo.toml && gpu=1

    if grep -qs 'xdgen' build.rs; then
        desktop='target/xdgen/app.desktop'
        metainfo='target/xdgen/app.metainfo.xml'
    else
        desktop="$(first_file "res/$appid.desktop" "data/$appid.desktop" "resources/$appid.desktop" resources/app.desktop res/*.desktop data/*.desktop)"
        metainfo="$(first_file "res/$appid.metainfo.xml" "data/$appid.metainfo.xml" "resources/$appid.metainfo.xml" resources/app.metainfo.xml res/*.metainfo.xml data/*.metainfo.xml)"
    fi
    [[ -n "$desktop" && -n "$metainfo" ]] || die 'could not locate desktop entry and metainfo sources'
    icon="$(first_file resources/icons/hicolor/scalable/apps/icon.svg "resources/icons/hicolor/scalable/apps/$appid.svg" resources/icon.svg "res/icons/hicolor/scalable/apps/$appid.svg" "data/$appid.svg" res/*.svg data/*.svg resources/*.svg)"
    symbolic="$(first_file "resources/$appid-symbolic.svg" "res/$appid-symbolic.svg" "data/$appid-symbolic.svg" "resources/icons/hicolor/symbolic/apps/$appid-symbolic.svg" "res/icons/hicolor/symbolic/apps/$appid-symbolic.svg")"
    [[ -n "$icon" ]] || log 'warning: no app icon SVG found; add an icon install command manually'

    output="${output:-$project/$appid.json}"
    [[ "$force" == 1 || ! -e "$output" ]] || die "refusing to overwrite $output (use -f)" 2

    args=(--share=ipc --socket=wayland --socket=fallback-x11)
    (( gpu == 1 )) && args+=(--device=dri)
    args+=(--talk-name=com.system76.CosmicSettingsDaemon '--talk-name=com.system76.CosmicSettingsDaemon.*')
    if [[ "$kind" == applet ]]; then
        args+=(--filesystem=xdg-config/cosmic:rw)
    else
        args+=(--filesystem=xdg-config/cosmic:ro "--filesystem=xdg-config/cosmic/$appid:create")
    fi
    args+=("${extra[@]}")
    [[ -d "$(dirname "$output")" ]] || die "output directory does not exist: $(dirname "$output")" 2

    python3 -I -"$output" "$project" "$kind" "$appid" "$bin" "$runtime" "$git_url" "$commit" \
        "$desktop" "$metainfo" "$icon" "$symbolic" "${args[@]}" <<'PY'
import json, os, sys

(output, project, kind, appid, binary, runtime, git_url, commit,
 desktop, metainfo, icon, symbolic, *finish_args) = sys.argv[1:]

dest = "${FLATPAK_DEST}"
cmds = [
    "cargo --offline fetch --manifest-path Cargo.toml --verbose",
    "cargo --offline build --release --verbose",
    f"install -Dm0755 target/release/{binary} -t {dest}/bin/",
    f"install -Dm0644 {desktop} {dest}/share/applications/{appid}.desktop",
    f"install -Dm0644 {metainfo} {dest}/share/metainfo/{appid}.metainfo.xml",
]
if icon:
    cmds.append(f"install -Dm0644 {icon} {dest}/share/icons/hicolor/scalable/apps/{appid}.svg")
if symbolic:
    cmds.append(f"install -Dm0644 {symbolic} {dest}/share/icons/hicolor/symbolic/apps/{appid}-symbolic.svg")

source = ({"type": "git", "url": git_url, "commit": commit} if git_url
          else {"type": "dir",
                "path": os.path.relpath(project, os.path.dirname(os.path.abspath(output)))})

manifest = {"id": appid, "runtime": "org.freedesktop.Platform", "runtime-version": runtime}
if kind == "app":
    manifest.update({"base": "com.system76.Cosmic.BaseApp", "base-version": "stable"})
manifest.update({
    "sdk": "org.freedesktop.Sdk",
    "sdk-extensions": ["org.freedesktop.Sdk.Extension.rust-stable"],
    "command": binary,
    "finish-args": finish_args,
    "build-options": {
        "append-path": "/usr/lib/sdk/rust-stable/bin",
        "env": {"CARGO_HOME": f"/run/build/{binary}/cargo", "CARGO_NET_OFFLINE": "true"},
    },
    "modules": [{
        "name": binary,
        "buildsystem": "simple",
        "build-commands": cmds,
        "sources": [source, "cargo-sources.json"],
    }],
})

with open(output, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=4)
    fh.write("\n")
PY
    printf 'wrote %s (%s, %s)\n' "$output" "$kind" "$appid"
    [[ -n "$git_url" ]] || log 'warning: local dir source — for test builds only; use -g/-c before submitting'

    if (( gen_sources == 1 )); then
        sources_out="$(dirname "$output")/cargo-sources.json"
        [[ "$force" == 1 || ! -e "$sources_out" ]] || die "refusing to overwrite $sources_out (use -f)" 2
        run_cargo_generator "$sources_out"
        printf 'wrote %s\n' "$sources_out"
    else
        log 'note: cargo-sources.json not generated (use -s) — the manifest references it'
    fi

    cat <<EOF
review finish-args (least privilege; justify extras):
$(printf '  %s\n' "${args[@]}")
channel: $( [[ "$kind" == applet ]] && echo 'pop-os/cosmic-flatpak (app/<id>/<id>.json)' || echo 'Flathub (check BaseApp runtime-version matches)' )
test:    flatpak run org.flatpak.Builder --user --install --force-clean --install-deps-from=flathub build-dir '$output'
lint:    flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest '$output'
EOF
}

main "$@"
