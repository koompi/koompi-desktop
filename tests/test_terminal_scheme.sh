#!/usr/bin/env bash
# Konsole and wezterm are the terminals KOOMPI ships a look for: green on
# near-black, a full ANSI palette so syntax highlighting reads in colour, and a
# see-through background. The wallpaper palette is for every other terminal; a
# shell inside these two leaves it out, and the wallpaper broadcast passes them
# by, or either one repaints them in wallpaper colours.
#
# fish's universal-variable file is state, not config. Shipping one put fish
# 3.4's universals and __fish_initialized back on every update, so fish 4.3+
# re-ran its scope migration and printed the notice again each time.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTS="$ROOT/dots"
WEZTERM="$DOTS/.config/wezterm/wezterm.lua"
PROFILE="$DOTS/.local/share/konsole/Profile 1.profile"
APPLYCOLOR="$DOTS/.config/quickshell/koompi/scripts/colors/applycolor.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ ! -e "$DOTS/.config/fish/fish_variables" ]] \
    || fail "dots ship fish_variables; every update would re-arm fish's 4.3 migration notice"

scheme_name="$(grep -oP '^ColorScheme=\K.+' "$PROFILE")"
scheme="$DOTS/.local/share/konsole/$scheme_name.colorscheme"
[[ -f "$scheme" ]] || fail "Konsole's profile names $scheme_name, which dots do not ship"

rgb() { printf '%d,%d,%d' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
konsole_color() {
    awk -v want="[$1]" '$0 == want { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && sub(/^Color=/, "") { print; exit }' "$scheme"
}
wezterm_list() {
    sed -n "/^  $1 = {/,/^  },/p" "$WEZTERM" | grep -oP "'#\K[0-9a-fA-F]{6}"
}

same() {
    local section="$1" hex="$2" got
    got="$(konsole_color "$section")"
    [[ "$got" == "$(rgb "$hex")" ]] \
        || fail "Konsole $section is ${got:-missing}, wezterm has #$hex ($(rgb "$hex"))"
}

same Foreground "$(grep -oP "^  foreground = '#\K[0-9a-fA-F]{6}" "$WEZTERM")"
same Background "$(grep -oP "^  background = '#\K[0-9a-fA-F]{6}" "$WEZTERM")"
mapfile -t ansi < <(wezterm_list ansi)
mapfile -t brights < <(wezterm_list brights)
(( ${#ansi[@]} == 8 && ${#brights[@]} == 8 )) \
    || fail "wezterm.lua no longer lists 8 ansi and 8 bright colours"
for i in {0..7}; do
    same "Color$i" "${ansi[$i]}"
    same "Color${i}Intense" "${brights[$i]}"
done

# Not wezterm's number: Konsole at wezterm's 0.8 lets far more wallpaper
# through, so it carries its own, set by eye.
konsole_opacity="$(grep -oP '^Opacity=\K[0-9.]+' "$scheme")"
awk -v b="$konsole_opacity" 'BEGIN { exit !(b > 0 && b < 1) }' \
    || fail "Konsole opacity is ${konsole_opacity:-unset}; the shipped look is see-through"

for tool in fish setsid ps script; do
    command -v "$tool" >/dev/null || { echo "skip: no $tool for the shell checks"; exit 0; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home/.local/state/quickshell/user/generated/terminal" "$tmp/bin"
marker='wallpaper-palette'
echo "$marker" > "$tmp/home/.local/state/quickshell/user/generated/terminal/sequences.txt"

# A terminal starts its shell as the leader of a new session. A stub of that
# name does the same, so the shell sees what it sees inside the real one.
for term in konsole wezterm-gui foot; do
    printf '#!/bin/bash\nsetsid --wait "$@"\n' > "$tmp/bin/$term"
    chmod +x "$tmp/bin/$term"
done

# TERM=linux keeps starship and eza out of a shell that only needs to start.
fish_in() {
    HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_DATA_HOME="$tmp/home/.local/share" \
        XDG_CACHE_HOME="$tmp/home/.cache" TERM=linux "$tmp/bin/$1" \
        fish --no-config -i -c "${2:-source $DOTS/.config/fish/config.fish}" </dev/null 2>&1
}
for term in konsole wezterm-gui; do
    fish_in "$term" | grep -qF "$marker" \
        && fail "fish inside $term printed the wallpaper palette over the terminal's own scheme"
done
# A shell started from that shell is still inside the same terminal.
fish_in konsole "fish --no-config -i -c 'source $DOTS/.config/fish/config.fish'" | grep -qF "$marker" \
    && fail "a nested fish inside konsole printed the wallpaper palette"
fish_in foot | grep -qF "$marker" \
    || fail "fish inside foot left out the wallpaper palette it has no scheme without"

# The broadcast decides per pty. script(1) gives its command a real pty as a
# session leader; a copy of it under a terminal's name stands in for that
# terminal.
fn="$(sed -n '/^keeps_own_scheme() {/,/^}/p' "$APPLYCOLOR")"
[[ -n "$fn" ]] || fail "applycolor.sh no longer has keeps_own_scheme"
printf '%s\n' "$fn" > "$tmp/fn.sh"
mkdir "$tmp/pty"
for term in konsole wezterm-gui foot; do
    cp "$(command -v script)" "$tmp/pty/$term"
    verdict="$("$tmp/pty/$term" -qec "bash -c 'source $tmp/fn.sh; keeps_own_scheme \$(tty) && echo keep || echo paint'" /dev/null </dev/null | tr -d '\r')"
    case "$term:$verdict" in
        konsole:keep | wezterm-gui:keep | foot:paint) ;;
        *) fail "the broadcast would ${verdict:-misjudge} a pty inside $term" ;;
    esac
done

echo "ok"
