#!/usr/bin/env bash
# A bare app icon (the bar) draws the icon the app ships, not the active theme's full-bleed tile.
# scripts/colors/app_own_icons.sh picks it: the app's own hicolor icon, then pixmaps, then a theme the
# active one inherits from, in its Inherits order; per name scalable first, then the largest SVG design,
# then the smallest PNG of 64 px or more, then the largest smaller PNG. Fake icon trees, no shell needed.
# With ImageMagick, a launchable app's own icon that is a logo on a flat light tile (or disc) is cut down to
# the logo, cached; a dark tile, and a dark logo that would vanish on the dark bar, keep their tile.
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

run() { env -i HOME="$home" PATH="$PATH" XDG_DATA_HOME="$WORK/none" XDG_DATA_DIRS="$data" XDG_CACHE_HOME="$WORK/cache" QS_ICON_THEME=tiles bash "$SCRIPT"; }
out="$(run)"
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

command -v magick > /dev/null 2>&1 || { echo "skip: no ImageMagick, light tiles not cut"; exit 0; }
tile() { # name ground logo-colour shape: a 112 px tile or disc on a 128 px canvas, a logo in its middle
    local name=$1 ground=$2 logo=$3 shape=$4 dir="$data/icons/hicolor/128x128/apps"
    mkdir -p "$dir"
    local body="roundrectangle 8,8 119,119 26,26"; [[ $shape == disc ]] && body="circle 64,64 64,1"
    local mark="circle 64,64 64,34"; [[ $logo == "#111111" ]] && mark="polygon 34,34 94,94 94,34 34,94"
    magick -size 128x128 xc:none -fill "$ground" -draw "$body" -fill "$logo" -draw "$mark" "PNG32:$dir/$name.png"
    mkdir -p "$data/applications" && printf '[Desktop Entry]\nType=Application\nName=%s\nIcon=%s\n' "$name" "$name" > "$data/applications/$name.desktop"
}
tile lightsquare "#ffffff" "#3a7bd5" square
tile lightdisc "#fafafa" "#25d366" disc
tile darksquare "#1b1d42" "#ff8800" square
tile darklogo "#ffffff" "#111111" square
tile notlaunched "#ffffff" "#3a7bd5" square
rm -f "$data/applications/notlaunched.desktop"

out="$(run)"
line() { grep -P "^$1\t" <<< "$out"; }
for name in lightsquare lightdisc; do
    [[ "$(line $name)" == "$name	$WORK/cache/koompi/bare-icons/"*".png	cut" ]] || fail "$name should be cut to its logo, got '$(line $name)'"
    cut="$(line $name | cut -f2)"
    edge=$(magick "$cut" -format '%[fx:p{64,2}.a]' info:); middle=$(magick "$cut" -format '%[fx:p{64,64}.a]' info:)
    [[ $edge == 0 && $middle == 1 ]] || fail "$name: the ground should be gone and the logo kept (edge alpha $edge, middle alpha $middle)"
done
echo "ok   light tile: a logo on a white square or disc is cut out of it, the ground transparent, the logo whole"
for name in darksquare darklogo notlaunched; do
    [[ "$(line $name)" == "$name	$data/icons/hicolor/128x128/apps/$name.png" ]] || fail "$name should keep its own icon, got '$(line $name)'"
done
echo "ok   light tile: a dark tile, a black logo and an icon no app asks for keep their own file"

[[ "$(run)" == "$out" ]] || fail "a second run should read the same answers from the cache"
rm -f "$data/applications/lightdisc.desktop"
run > /dev/null
[[ $(find "$WORK/cache/koompi/bare-icons" -type f | wc -l) -eq 3 ]] || fail "the cache should drop the disc once no app asks for it: $(ls "$WORK/cache/koompi/bare-icons")"
echo "ok   light tile: answers are cached per file and pruned when no app asks for them"
