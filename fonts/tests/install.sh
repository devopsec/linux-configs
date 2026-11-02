#!/usr/bin/env bash
#
# Offline test for the fonts family installer: runs fonts/install.sh in a temporary HOME
# against locally built zips served through file:// URLs (no network, no sudo) and asserts
# install, idempotency, offline fallback, clean (-cp) and fontconfig rule handling (-cc).

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

TESTS_DIR="$(dirname "$(realpath -m "${BASH_SOURCE[0]}")")"
INSTALLER="$TESTS_DIR/../install.sh"
CONF_SRC="$TESTS_DIR/../fontconfig/conf.d"
NERD_FONTS=(JetBrainsMono NerdFontsSymbolsOnly FiraCode FiraMono Mononoki Hack)
FONTS=("${NERD_FONTS[@]}" Gelasio ComicRelief)

declare -i OVERALL_RESULT=0
WORK=""
# shellcheck disable=SC2329
function cleanup() {
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
}
trap cleanup EXIT
WORK="$(mktemp -d /tmp/linux-configs-fonts-test.XXXXXX)"

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
    PATH="$WORK/bin:$PATH" HOME="$WORK/home" NERD_FONTS_RELEASE_URL="$URL" \
        GOOGLE_FONTS_URL="$GOOGLE_URL" bash "$INSTALLER" -im user -cm local "$@" > "$WORK/out.log" 2>&1
}

function count_fonts() {
    find "$WORK/home/.local/share/fonts" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
}

mkdir -p "$WORK/home" "$WORK/zips" "$WORK/build" "$WORK/bin" \
    "$WORK/google/ofl/gelasio" "$WORK/google/ofl/comicrelief"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/fc-cache"
printf '#!/usr/bin/env bash\nprintf "install ok installed\\n"\n' > "$WORK/bin/dpkg-query"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/apt-cache"
chmod +x "$WORK/bin/fc-cache"
chmod +x "$WORK/bin/dpkg-query" "$WORK/bin/apt-cache"
for name in "${NERD_FONTS[@]}"; do
    (
        cd "$WORK/build" || exit 1
        : > "${name}-Regular.ttf"
        echo license > LICENSE.txt
        echo readme > README.md
        zip -q "$WORK/zips/$name.zip" "${name}-Regular.ttf" LICENSE.txt README.md
    )
done
touch "$WORK/google/ofl/gelasio/Gelasio[wght].ttf" \
    "$WORK/google/ofl/comicrelief/ComicRelief-Regular.ttf" \
    "$WORK/google/ofl/comicrelief/ComicRelief-Bold.ttf"
URL="file://$WORK/zips"
GOOGLE_URL="file://$WORK/google"

# install fonts only
run_installer -sc
check "install exits 0" test $? -eq 0
check "all ${#FONTS[@]} fonts installed in own dirs" test "$(count_fonts)" -eq "${#FONTS[@]}"
check "both Comic Relief styles are installed" test "$(find "$WORK/home/.local/share/fonts/ComicRelief" -iname '*.ttf' | wc -l)" -eq 2
check "LICENSE/README stripped" test -z "$(find "$WORK/home/.local/share/fonts" \( -name 'LICENSE*' -o -name 'README*' \) -print)"

# idempotency
run_installer -sc
check "second run skips every font" test "$(grep -c 'already installed' "$WORK/out.log")" -eq "${#FONTS[@]}"

# foreign fonts survive clean; owned dirs are removed
mkdir -p "$WORK/home/.local/share/fonts/Foreign"
: > "$WORK/home/.local/share/fonts/Foreign/keep.ttf"
run_installer -cp -sp -sc
check "clean removes owned font dirs" test ! -e "$WORK/home/.local/share/fonts/JetBrainsMono"
check "clean removes Google font dirs" test ! -e "$WORK/home/.local/share/fonts/Gelasio"
check "clean keeps foreign fonts" test -f "$WORK/home/.local/share/fonts/Foreign/keep.ttf"

# offline: NOTICE per font, exit 0, no partial dirs
for name in "${FONTS[@]}"; do rm -rf "$WORK/home/.local/share/fonts/$name"; done
URL="file://$WORK/missing"
GOOGLE_URL="file://$WORK/missing-google"
run_installer -sc
check "offline exits 0" test $? -eq 0
check "offline logs a NOTICE per font source" test "$(grep -c 'could not download' "$WORK/out.log")" -eq "$(( ${#FONTS[@]} + 1 ))"
check "offline leaves no partial dirs" test ! -e "$WORK/home/.local/share/fonts/Hack"
URL="file://$WORK/zips"
GOOGLE_URL="file://$WORK/google"

# fontconfig rules
CONF_DST="$WORK/home/.config/fontconfig/conf.d"
mkdir -p "$CONF_DST"
echo '<fontconfig/>' > "$CONF_DST/99-foreign.conf"
run_installer -sp
check "config run copies every rule" test "$(find "$CONF_DST" -name '[0-9]*-*.conf' ! -name '99-foreign.conf' | wc -l)" -eq "$(find "$CONF_SRC" -name '*.conf' | wc -l)"
run_installer -cc -sp
check "clean configs keeps foreign rule" test -f "$CONF_DST/99-foreign.conf"
check "clean configs reinstalls rules" test -f "$CONF_DST/60-monospace-default.conf"

# neovim installer no longer owns fonts
check "neovim/install.sh has no font logic" test -z "$(grep -il 'nerd_font\|fc-cache' "$TESTS_DIR/../../neovim/install.sh")"

(( OVERALL_RESULT == 0 )) && echo "All fonts tests passed" || echo "Some fonts tests FAILED"
exit "$OVERALL_RESULT"
