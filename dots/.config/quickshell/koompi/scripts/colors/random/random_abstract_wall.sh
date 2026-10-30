#!/usr/bin/env bash

# Random abstract wallpaper, drawn on this machine: waves, silk folds, mesh
# gradients, dunes and auroras in the manner of macOS; arcs, contours, low-poly,
# halftone and retro stripes in the manner of Ubuntu. Offline, at the screen's
# own size, never the same twice.
#
# Usage: random_abstract_wall.sh [workspace-id] [--notify] [--style S] [--palette P]
# The workspace id pins where the image lands, as random_wall.sh does.
# Styles and palettes: scripts/images/abstract_wallpaper.py --list. Without
# --style, a random one from .background.randomWallpaper.abstract.styles in
# config.json, or from all of them; palettes the same way.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$XDG_CONFIG_HOME/koompi/config.json"
GENERATOR="$SCRIPT_DIR/../../images/abstract_wallpaper.py"
# Generated files are kept for the library source to reuse; past this many the
# oldest unused ones go, so a held-down key cannot fill the disk.
KEEP=24

notify=0 style="" palette=""
while [ $# -gt 0 ]; do
    case "$1" in
        --notify) notify=1 ;;
        --style) style="${2:-}"; shift ;;
        --palette) palette="${2:-}"; shift ;;
        0) ;;
        *[!0-9]*) ;;
        *) export KOOMPI_TARGET_WORKSPACE="$1" ;;
    esac
    shift
done

fail() {
    echo "random_abstract_wall: $*" >&2
    [ "$notify" = 1 ] && command -v notify-send >/dev/null 2>&1 \
        && notify-send -a "Wallpaper" -i "image-x-generic" "No abstract wallpaper" "$*"
    exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is not installed"
command -v rsvg-convert >/dev/null 2>&1 || fail "rsvg-convert (librsvg) is not installed"

get_pictures_dir() {
    if command -v xdg-user-dir >/dev/null 2>&1; then
        xdg-user-dir PICTURES
        return
    fi
    echo "$HOME/Pictures"
}

# A user's subset, if they named one; a name the generator does not know is
# dropped here rather than failing the keypress.
pick_from_config() { # pick_from_config <key> <known names...>
    local key="$1" name
    shift
    local -a known=("$@") chosen=()
    while IFS= read -r name; do
        [[ " ${known[*]} " == *" $name "* ]] && chosen+=("$name")
    done < <(jq -r ".background.randomWallpaper.abstract.${key}[]?" "$CONFIG_FILE" 2>/dev/null)
    [ "${#chosen[@]}" -gt 0 ] && printf '%s' "${chosen[RANDOM % ${#chosen[@]}]}"
}

listing="$(python3 -I "$GENERATOR" --list)" || fail "the generator at $GENERATOR did not run"
read -ra all_styles <<< "$(sed -n 's/^styles: //p' <<< "$listing")"
read -ra all_palettes <<< "$(sed -n 's/^palettes: //p' <<< "$listing")"
[ -n "$style" ] || style="$(pick_from_config styles "${all_styles[@]}")"
[ -n "$palette" ] || palette="$(pick_from_config palettes "${all_palettes[@]}")"

# The largest connected screen, in pixels: a vector drawing is exact at any
# size, so render once at the size that needs the most.
size="$(hyprctl monitors -j 2>/dev/null | jq -r 'max_by(.width * .height) | "\(.width) \(.height)"' 2>/dev/null)"
read -r width height <<< "$size"
[[ "${width:-}" =~ ^[0-9]+$ && "${height:-}" =~ ^[0-9]+$ ]] || { width=2560; height=1440; }

save_dir="$(get_pictures_dir)/Wallpapers/Abstract"
mkdir -p "$save_dir" || fail "cannot create $save_dir"

args=(--width "$width" --height "$height")
[ -n "$style" ] && args+=(--style "$style")
[ -n "$palette" ] && args+=(--palette "$palette")
svg="$(mktemp -- "$save_dir/.abstract.XXXXXX.svg")" || fail "cannot write to $save_dir"
trap 'rm -f "$svg" "${part:-}"' EXIT
python3 -I "$GENERATOR" "${args[@]}" > "$svg" 2> "$svg.meta" || { rm -f "$svg.meta"; fail "the generator failed"; }
# style=... palette=... seed=... names the file, so a favourite can be drawn again
meta="$(tail -n1 "$svg.meta")"
rm -f "$svg.meta"
name="$(sed -E 's/style=([a-z]+) palette=([a-z]+) seed=([0-9]+)/abstract-\1-\2-\3/' <<< "$meta")"
[[ "$name" =~ ^abstract-[a-z]+-[a-z]+-[0-9]+$ ]] || name="abstract-$(date +%Y%m%d-%H%M%S)"
target="$save_dir/$name.png"

part="$(mktemp -- "$target.XXXXXX.part")" || fail "cannot write to $save_dir"
rsvg-convert -o "$part" "$svg" && [ -s "$part" ] || fail "rsvg-convert could not render $name"
chmod 644 "$part"
mv -f "$part" "$target"

# Oldest first past KEEP, never one a workspace or the global wallpaper shows.
mapfile -t used < <(jq -r '[.background.wallpaperPath // empty]
    + [.background.workspaceWallpapers.workspaces[]?.path // empty] | .[]' "$CONFIG_FILE" 2>/dev/null)
mapfile -t old < <(find "$save_dir" -maxdepth 1 -type f -name 'abstract-*.png' -printf '%T@ %p\n' \
    | sort -rn | tail -n +$((KEEP + 1)) | cut -d' ' -f2-)
for f in "${old[@]}"; do
    [[ " ${used[*]} " == *" $f "* ]] || rm -f -- "$f"
done

printf '%s\n' "$target"
"$SCRIPT_DIR/../apply_wall.sh" "$target"
