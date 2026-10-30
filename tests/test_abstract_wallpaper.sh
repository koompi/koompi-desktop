#!/usr/bin/env bash
# The abstract wallpaper source draws its image here: abstract_wallpaper.py
# writes SVG, rsvg-convert renders it at the screen's size, and
# random_abstract_wall.sh names, keeps, prunes and applies it. hyprctl,
# xdg-user-dir and apply_wall.sh are stubs; nothing on the desktop changes.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
GEN="$SHELL_ROOT/scripts/images/abstract_wallpaper.py"
SCRIPT="$SHELL_ROOT/scripts/colors/random/random_abstract_wall.sh"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -x "$SCRIPT" ]] || fail "missing or not executable: ${SCRIPT#"$REPO_ROOT"/}"
command -v python3 > /dev/null || { echo "skip: python3 not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- the generator ------------------------------------------------------------
listing="$(python3 -I "$GEN" --list)" || fail "--list failed"
read -ra styles <<< "$(sed -n 's/^styles: //p' <<< "$listing")"
read -ra palettes <<< "$(sed -n 's/^palettes: //p' <<< "$listing")"
(( ${#styles[@]} >= 13 && ${#palettes[@]} >= 14 )) || fail "too few styles or palettes: $listing"

for style in "${styles[@]}"; do
    python3 -I "$GEN" --width 320 --height 200 --style "$style" --palette aubergine --seed 7 \
        > "$tmp/$style.svg" 2> "$tmp/$style.meta" || fail "$style did not generate"
    [[ "$(cat "$tmp/$style.meta")" == "style=$style palette=aubergine seed=7" ]] ||
        fail "$style reported '$(cat "$tmp/$style.meta")'"
    python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$tmp/$style.svg" ||
        fail "$style is not well-formed SVG"
    grep -q 'filter="url(#grain)"' "$tmp/$style.svg" || fail "$style has no grain, so its gradients band"
done
# A seed is a picture: the same one draws the same image, another does not.
python3 -I "$GEN" --width 320 --height 200 --style waves --palette ocean --seed 42 > "$tmp/a.svg" 2>/dev/null
python3 -I "$GEN" --width 320 --height 200 --style waves --palette ocean --seed 42 > "$tmp/b.svg" 2>/dev/null
python3 -I "$GEN" --width 320 --height 200 --style waves --palette ocean --seed 43 > "$tmp/c.svg" 2>/dev/null
cmp -s "$tmp/a.svg" "$tmp/b.svg" || fail "the same seed drew two different images"
cmp -s "$tmp/a.svg" "$tmp/c.svg" && fail "two seeds drew the same image"
# -I and no bytecode: the dotfiles tree stays as shipped
[[ -z "$(find "$SHELL_ROOT/scripts/images" -name __pycache__)" ]] || fail "the generator left __pycache__ in the dotfiles"
echo "ok   generator: ${#styles[@]} styles x ${#palettes[@]} palettes, well-formed SVG with grain, seeded"

if ! command -v rsvg-convert > /dev/null; then
    echo "skip: rsvg-convert not installed, nothing rendered"
    exit 0
fi

# librsvg, not just an XML parser, has to accept every style
for style in "${styles[@]}"; do
    rsvg-convert -o "$tmp/$style.png" "$tmp/$style.svg" 2> "$tmp/$style.err" && [[ -s "$tmp/$style.png" ]] ||
        fail "rsvg-convert could not render $style: $(cat "$tmp/$style.err")"
done
echo "ok   render: rsvg-convert draws all ${#styles[@]} styles"

# --- the source script --------------------------------------------------------
mkdir -p "$tmp/q/scripts/colors/random" "$tmp/q/scripts/images" "$tmp/bin" "$tmp/home/.config/koompi"
cp "$SCRIPT" "$tmp/q/scripts/colors/random/"
cp "$GEN" "$tmp/q/scripts/images/"
cp -r "$SHELL_ROOT/scripts/images/abstract" "$tmp/q/scripts/images/"
script="$tmp/q/scripts/colors/random/random_abstract_wall.sh"
cat > "$tmp/q/scripts/colors/apply_wall.sh" <<STUB
#!/usr/bin/env bash
printf '%s\t%s\n' "\${KOOMPI_TARGET_WORKSPACE:-}" "\$1" >> "$tmp/applied"
STUB
# two screens: the larger one sets the size
printf '#!/bin/sh\necho %s\n' "'[{\"width\":320,\"height\":200},{\"width\":480,\"height\":300}]'" > "$tmp/bin/hyprctl"
printf '#!/bin/sh\necho "%s/Pictures"\n' "$tmp/home" > "$tmp/bin/xdg-user-dir"
chmod +x "$tmp/bin/"* "$tmp/q/scripts/colors/apply_wall.sh"
saved="$tmp/home/Pictures/Wallpapers/Abstract"
config="$tmp/home/.config/koompi/config.json"
echo '{}' > "$config"

run() { HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" PATH="$tmp/bin:$PATH" "$script" "$@" > "$tmp/out" 2>&1; }
png_size() { python3 -I -c 'import struct, sys; d = open(sys.argv[1], "rb").read(24); print(*struct.unpack(">II", d[16:24]))' "$1"; }

run 6 --style lines --palette dusk || fail "the script failed: $(cat "$tmp/out")"
made="$(compgen -G "$saved/abstract-lines-dusk-*.png")" || fail "no abstract-lines-dusk-<seed>.png in $saved: $(ls -A "$saved")"
[[ "$(png_size "$made")" == "480 300" ]] || fail "rendered at $(png_size "$made"), want the larger screen's 480 300"
[[ "$(cat "$tmp/applied")" == "6	$made" ]] || fail "apply_wall.sh got '$(cat "$tmp/applied")', want workspace 6 and $made"
[[ "$(stat -c %a "$made")" == 644 ]] || fail "saved image is mode $(stat -c %a "$made")"
[[ -z "$(find "$saved" -name '.*' -o -name '*.part')" ]] || fail "left a temp file: $(ls -A "$saved")"

# config.json narrows the choice; a name the generator does not know is dropped
echo '{"background":{"randomWallpaper":{"abstract":{"styles":["rings","sparkles"],"palettes":["ember"]}}}}' > "$config"
run || fail "configured run failed: $(cat "$tmp/out")"
compgen -G "$saved/abstract-rings-ember-*.png" > /dev/null || fail "config.json's styles and palettes were not used: $(ls "$saved")"

# Pruned to the newest 24, but never a file a workspace shows.
rm -f "$saved"/*
for i in $(seq 1 30); do
    touch -d "@$((1700000000 + i))" "$saved/abstract-waves-ocean-$i.png"
done
jq -n --arg p "$saved/abstract-waves-ocean-1.png" '{background: {workspaceWallpapers: {workspaces: {ws2: {path: $p}}}}}' > "$config"
run || fail "prune run failed: $(cat "$tmp/out")"
left="$(find "$saved" -name 'abstract-*.png' | wc -l)"
(( left == 25 )) || fail "kept $left files, want the newest 24 plus the one in use"
[[ -e "$saved/abstract-waves-ocean-1.png" ]] || fail "pruned the wallpaper a workspace is showing"
[[ -e "$saved/abstract-waves-ocean-2.png" ]] && fail "kept an old unused file past the limit"
echo "ok   script: rendered at the largest screen, named by style/palette/seed, applied, config subset, pruned around what is in use"

# --- wiring -------------------------------------------------------------------
KEYBINDS="$REPO_ROOT/dots/.config/hypr/hyprland/keybinds_shell_extra.lua"
SELECTOR="$SHELL_ROOT/modules/koompi/wallpaperSelector/WallpaperSelector.qml"
grep -q 'quickshell:wallpaperRandomAbstract"' "$KEYBINDS" || fail "no keybind for quickshell:wallpaperRandomAbstract"
awk '/name: "wallpaperRandomAbstract"/,/^    }/' "$SELECTOR" | grep -q 'random_abstract_wall.sh' ||
    fail "the wallpaperRandomAbstract shortcut does not run random_abstract_wall.sh"
grep -q 'random_abstract_wall.sh' "$SHELL_ROOT/modules/settings/QuickConfig.qml" || fail "Quick settings has no abstract button"
echo "ok   wiring: keybind, shell shortcut and Quick settings button reach the script"
