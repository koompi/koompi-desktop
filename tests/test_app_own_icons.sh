#!/usr/bin/env bash
# A bare app icon (the bar) draws the icon the app ships, not the active theme's full-bleed tile.
# scripts/colors/app_own_icons.sh picks it: the app's own hicolor icon, then pixmaps, then a theme the
# active one inherits from, in its Inherits order; per name scalable first, then the largest SVG design,
# then the smallest PNG of 64 px or more, then the largest smaller PNG. Fake icon trees, no shell needed.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/colors/app_own_icons.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
[[ -f "$SCRIPT" ]] || fail "missing scripts/colors/app_own_icons.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
data="$WORK/share" home="$WORK/home"
mkdir -p "$home"
icon() { mkdir -p "$(dirname -- "$data/$1")" && : > "$data/$1"; }

printf '[Icon Theme]\nName=tiles\nInherits=flat-dark,flat,hicolor\n' > "$WORK/index.theme"
mkdir -p "$data/icons/tiles" && cp "$WORK/index.theme" "$data/icons/tiles/index.theme"
icon icons/tiles/apps/scalable/chrome.svg                  # the tile itself is never an answer
icon icons/hicolor/16x16/apps/chrome.png
icon icons/hicolor/32x32/apps/chrome.png
icon icons/hicolor/64x64/apps/chrome.png
icon icons/hicolor/256x256/apps/chrome.png
icon icons/hicolor/48x48/apps/tiny.png
icon icons/hicolor/32x32/apps/tiny.png
icon icons/hicolor/scalable/apps/vector.svg
icon icons/hicolor/512x512/apps/vector.png
icon pixmaps/vector.png                                     # hicolor beats pixmaps
icon pixmaps/term.png
icon icons/flat/apps/48/term.svg                            # pixmaps beat an inherited theme
icon icons/flat/apps/48/settings.svg
icon icons/flat/apps/22/settings.svg
icon icons/flat-dark/apps/32/settings.svg                   # earlier in Inherits wins
icon icons/flat/apps/48/files.svg
icon icons/flat/apps/16@2x/files.svg                        # a 16 px design drawn twice as big is still a 16 px design

out="$(env -i HOME="$home" PATH="$PATH" XDG_DATA_HOME="$WORK/none" XDG_DATA_DIRS="$data" QS_ICON_THEME=tiles bash "$SCRIPT")"
want=$(printf '%s\n' \
    "chrome	$data/icons/hicolor/64x64/apps/chrome.png" \
    "files	$data/icons/flat/apps/48/files.svg" \
    "settings	$data/icons/flat-dark/apps/32/settings.svg" \
    "term	$data/pixmaps/term.png" \
    "tiny	$data/icons/hicolor/48x48/apps/tiny.png" \
    "vector	$data/icons/hicolor/scalable/apps/vector.svg")
[[ "$out" == "$want" ]] || fail "app_own_icons.sh picked
$out
want
$want"
echo "ok   own icons: hicolor, then pixmaps, then the inherited themes in order; scalable, largest design, 64 px PNG"
