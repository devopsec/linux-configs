#!/usr/bin/env bash

# fonts family installer: a curated set of Nerd Fonts plus the fontconfig rules that go with them.
# sources the shared library for flags/orchestration; can also run standalone
# as 'fonts/install.sh [-cc] [-cp] [-sp] [-sc] [-im MODE] [-cm MODE] [fonts]'

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -Eeuo pipefail
    shopt -s inherit_errexit nullglob
fi

FONTS_INSTALL_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
# shellcheck source=installer-libs/common.sh
source "$FONTS_INSTALL_DIR/../installer-libs/common.sh"

register_family fonts fonts

declare -ga FONT_ARCHIVE_NAMES=()
declare -gA FONT_ARCHIVE_URLS=()
declare -gA FONT_ARCHIVE_COUNTS=()
declare -ga NERD_FONTS=(JetBrainsMono NerdFontsSymbolsOnly FiraCode FiraMono Mononoki Hack)
NERD_FONTS_RELEASE_URL="${NERD_FONTS_RELEASE_URL:-https://github.com/ryanoasis/nerd-fonts/releases/latest/download}"
GOOGLE_FONTS_URL="${GOOGLE_FONTS_URL:-https://raw.githubusercontent.com/google/fonts/main}"
FONTCONFIG_SRC_DIR="$FONTS_INSTALL_DIR/fontconfig/conf.d"
FONTCONFIG_GLOBAL_AVAIL="/etc/fonts/conf.avail"
FONTCONFIG_GLOBAL_ENABLED="/etc/fonts/conf.d"

function font_define() {
    local font_name="$1" font_url index=0
    shift
    [[ -n "$font_name" && $# -gt 0 ]] || { log_error "font_define requires a name and at least one URL"; return 2; }
    [[ -z "${FONT_ARCHIVE_COUNTS[$font_name]:-}" ]] || { log_error "Font '$font_name' is already defined"; return 2; }
    FONT_ARCHIVE_NAMES+=("$font_name")
    for font_url in "$@"; do
        FONT_ARCHIVE_URLS["$font_name:$index"]="$font_url"
        index=$((index + 1))
    done
    FONT_ARCHIVE_COUNTS["$font_name"]="$index"
}

for NERD_FONT in "${NERD_FONTS[@]}"; do
    font_define "$NERD_FONT" "$NERD_FONTS_RELEASE_URL/$NERD_FONT.zip"
done
font_define Gelasio "$GOOGLE_FONTS_URL/ofl/gelasio/Gelasio%5Bwght%5D.ttf"
font_define ComicRelief \
    "$GOOGLE_FONTS_URL/ofl/comicrelief/ComicRelief-Regular.ttf" \
    "$GOOGLE_FONTS_URL/ofl/comicrelief/ComicRelief-Bold.ttf"

pkg_define fontconfig apt=fontconfig pacman=fontconfig nix=fontconfig

function fonts_define_package() {
    local package_id="$1" apt_name="$2" pacman_name="$3"
    pkg_define "$package_id" "apt=$apt_name" "pacman=$pacman_name"
}

fonts_define_package fonts-croscore fonts-croscore ttf-croscore
fonts_define_package fonts-caladea fonts-crosextra-caladea ttf-caladea
fonts_define_package fonts-carlito fonts-crosextra-carlito ttf-carlito
fonts_define_package fonts-dejavu fonts-dejavu ttf-dejavu
fonts_define_package fonts-droid-fallback fonts-droid-fallback ttf-droid
fonts_define_package fonts-font-awesome fonts-font-awesome ttf-font-awesome
fonts_define_package fonts-freefont fonts-freefont-ttf ttf-freefont
fonts_define_package fonts-inter fonts-inter ttf-inter
fonts_define_package fonts-lato fonts-lato ttf-lato
fonts_define_package fonts-liberation fonts-liberation ttf-liberation
fonts_define_package fonts-liberation-sans-narrow fonts-liberation-sans-narrow ttf-liberation-narrow
fonts_define_package fonts-linuxlibertine fonts-linuxlibertine ttf-linux-libertine
fonts_define_package fonts-noto-core fonts-noto-core noto-fonts
fonts_define_package fonts-noto-extra fonts-noto-extra noto-fonts-extra
fonts_define_package fonts-noto-mono fonts-noto-mono noto-fonts
fonts_define_package fonts-noto-ui-core fonts-noto-ui-core noto-fonts
fonts_define_package fonts-noto-cjk fonts-noto-cjk noto-fonts-cjk
fonts_define_package fonts-noto-cjk-extra fonts-noto-cjk-extra noto-fonts-cjk-extra
fonts_define_package fonts-noto-color-emoji fonts-noto-color-emoji noto-fonts-emoji
fonts_define_package fonts-open-sans fonts-open-sans ttf-opensans
fonts_define_package fonts-sil-gentium fonts-sil-gentium gentium-plus-fonts
fonts_define_package fonts-sil-gentium-basic fonts-sil-gentium-basic gentium-basic-fonts
fonts_define_package fonts-stix fonts-stix otf-stix
fonts_define_package fonts-ubuntu fonts-ubuntu ttf-ubuntu-font-family
fonts_define_package fonts-urw-base35 fonts-urw-base35 urw-fonts
fonts_define_package fonts-inconsolata fonts-inconsolata ttf-inconsolata
fonts_define_package fonts-comic-neue fonts-comic-neue ttf-comic-neue

family_requires fonts fontconfig curl unzip \
    fonts-croscore fonts-caladea fonts-carlito fonts-dejavu fonts-droid-fallback \
    fonts-font-awesome fonts-freefont fonts-inter fonts-lato fonts-liberation \
    fonts-liberation-sans-narrow fonts-linuxlibertine fonts-noto-core fonts-noto-extra \
    fonts-noto-mono fonts-noto-ui-core fonts-noto-cjk fonts-noto-cjk-extra \
    fonts-noto-color-emoji fonts-open-sans fonts-sil-gentium fonts-sil-gentium-basic \
    fonts-stix fonts-ubuntu fonts-urw-base35 fonts-inconsolata fonts-comic-neue

function fonts_dir() {
    if [[ "$RESOLVED_INSTALL_MODE" == "system" ]]; then
        printf '%s\n' "/usr/local/share/fonts"
    else
        printf '%s\n' "$HOME/.local/share/fonts"
    fi
}

function fonts_refresh_cache() {
    if command -v fc-cache >/dev/null; then
        run_scoped fc-cache -f "$(fonts_dir)"
    else
        log_notice "'fc-cache' not found (fontconfig missing?); skipping font cache refresh"
    fi
}

# downloads one font archive/file into '<fonts dir>/<name>/'; skips when already present,
# and only logs a NOTICE when a source cannot be installed (e.g. offline)
function fonts_install_one() (
    local name="$1" target work_dir archive content first_font relative_dir relative_path rule source_filename url
    local index=0 font_count="${FONT_ARCHIVE_COUNTS[$1]}" success_count=0
    work_dir=""
    trap '[[ -z "$work_dir" ]] || rm -rf -- "$work_dir"' EXIT
    target="$(fonts_dir)/$name"

    if [[ -f "$target/.linux-configs-installed" ]]; then
        log_info "'$name' font already installed in '$target'"
        return 0
    fi

    log_info "Installing '$name' font into '$target'"
    work_dir="$(mktemp -d /tmp/linux-configs-font.XXXXXX)"
    while (( index < font_count )); do
        url="${FONT_ARCHIVE_URLS[$name:$index]}"
        content="$work_dir/content/$index"
        archive="$work_dir/archive-$index"
        mkdir -p "$content"

        if ! curl --globoff -fsSL --retry 2 -o "$archive" "$url"; then
            log_notice "could not download '$name' from '$url'; skipping this source"
            index=$((index + 1))
            continue
        fi
        if [[ "$url" == *.zip ]]; then
            if ! unzip -qo "$archive" -d "$content"; then
                log_notice "Could not extract '$name' from '$url'; skipping this source"
                index=$((index + 1))
                continue
            fi
        else
            source_filename="${url##*/}"
            source_filename="${source_filename%%\?*}"
            source_filename="${source_filename//%5B/[}"
            source_filename="${source_filename//%5D/]}"
            cp "$archive" "$content/$source_filename"
        fi
        find "$content" -type f ! -iname '*.ttf' ! -iname '*.otf' -delete
        first_font="$(find "$content" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)"
        if [[ -z "$first_font" ]]; then
            log_notice "Downloaded '$name' from '$url' contained no font files; skipping this source"
        else
            success_count=$((success_count + 1))
        fi
        index=$((index + 1))
    done

    first_font="$(find "$work_dir/content" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print -quit)"
    [[ -n "$first_font" ]] || return 0
    run_scoped mkdir -p "$target"
    while IFS= read -r -d '' rule; do
        relative_path="${rule#"$work_dir/content/"}"
        relative_path="${relative_path#*/}"
        relative_dir="${relative_path%/*}"
        if [[ "$relative_dir" == "$relative_path" ]]; then relative_dir=""; fi
        run_scoped mkdir -p "$target${relative_dir:+/$relative_dir}"
        run_scoped cp -a "$rule" "$target/$relative_path"
    done < <(find "$work_dir/content" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)
    if (( success_count == font_count )); then
        run_scoped touch "$target/.linux-configs-installed"
    fi
    return 0
)

function fonts_install_deps() {
    local name index font_count needs_unzip

    if ! command -v curl >/dev/null; then
        log_notice "'curl' is required to download fonts; skipping font installs"
        return 0
    fi

    for name in "${FONT_ARCHIVE_NAMES[@]}"; do
        index=0
        font_count="${FONT_ARCHIVE_COUNTS[$name]}"
        needs_unzip=0
        while (( index < font_count )); do
            if [[ "${FONT_ARCHIVE_URLS[$name:$index]}" == *.zip ]] && ! command -v unzip >/dev/null; then
                log_notice "'unzip' is required to extract '$name'; skipping this font family"
                needs_unzip=1
                break
            fi
            index=$((index + 1))
        done
        if (( needs_unzip == 1 )); then continue; fi
        fonts_install_one "$name"
    done
    fonts_refresh_cache
}

# removes only the per-font directories created by this installer
function fonts_clean_packages() {
    local name target

    for name in "${FONT_ARCHIVE_NAMES[@]}"; do
        target="$(fonts_dir)/$name"
        [[ -d "$target" ]] || continue
        log_info "Removing '$name' font from '$target'"
        run_scoped rm -rf -- "$target"
    done
    fonts_refresh_cache
}

# copies the fontconfig rules into the target home; as_root=1 uses sudo
function fonts_configure_home() {
    local target_home="$1" as_root="${2:-0}"
    local rule
    run_as "$as_root" mkdir -p "$target_home/.config/fontconfig/conf.d"
    for rule in "$FONTCONFIG_SRC_DIR"/*.conf; do
        install_file "$as_root" "$rule" "$target_home/.config/fontconfig/conf.d/${rule##*/}" -f
    done
    return 0
}

# removes only the rule files shipped by this repo, leaving any other user rules alone
function fonts_clean_home() {
    local target_home="$1" as_root="${2:-0}" rule
    for rule in "$FONTCONFIG_SRC_DIR"/*.conf; do
        run_as "$as_root" rm -f -- "$target_home/.config/fontconfig/conf.d/${rule##*/}"
    done
    return 0
}

# system-wide rules: files in conf.avail enabled through conf.d symlinks (Debian/Fedora layout)
function fonts_configure_global() {
    local rule
    run_priv mkdir -p "$FONTCONFIG_GLOBAL_AVAIL" "$FONTCONFIG_GLOBAL_ENABLED"
    for rule in "$FONTCONFIG_SRC_DIR"/*.conf; do
        install_file 1 "$rule" "$FONTCONFIG_GLOBAL_AVAIL/${rule##*/}" -f
        link_path 1 "$FONTCONFIG_GLOBAL_AVAIL/${rule##*/}" "$FONTCONFIG_GLOBAL_ENABLED/${rule##*/}"
    done
    return 0
}

function fonts_clean_global() {
    local rule
    for rule in "$FONTCONFIG_SRC_DIR"/*.conf; do
        run_priv rm -f -- "$FONTCONFIG_GLOBAL_AVAIL/${rule##*/}" "$FONTCONFIG_GLOBAL_ENABLED/${rule##*/}"
    done
    return 0
}

function fonts_post_install() {
    log_info "Terminal applications must be configured manually to use JetBrainsMono Nerd Font."
}

# standalone entrypoint: only runs when invoked directly, not when sourced by the root installer
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    setup_install "$@"
    run_install fonts
fi
