#!/usr/bin/env bash
# switchwall.sh names the icon theme on every wallpaper or mode change. When
# koompi-icons is not on disk it must keep the breeze-plus pair, or every app icon
# falls back to hicolor.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SWITCH="$ROOT/dots/.config/quickshell/koompi/scripts/colors/switchwall.sh"
ICONFN="$ROOT/dots/.config/quickshell/koompi/scripts/colors/icon_theme.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

fn="$(sed -n '/^icon_theme_for() {/,/^}/p' "$ICONFN")"
[[ -n "$fn" ]] || fail "switchwall.sh has no icon_theme_for in icon_theme.sh"
eval "$fn"

# only the lookup runs: gsettings and the rest of switchwall.sh never start
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"
unset XDG_DATA_HOME

export XDG_DATA_DIRS="$TEST_ROOT/none"
[[ "$(icon_theme_for light)" == breeze-plus ]] || fail "light without the theme is not breeze-plus"
[[ "$(icon_theme_for dark)" == breeze-plus-dark ]] || fail "dark without the theme is not breeze-plus-dark"

mkdir -p "$TEST_ROOT/sys/icons/koompi-icons" "$TEST_ROOT/sys/icons/koompi-icons-dark"
touch "$TEST_ROOT/sys/icons/koompi-icons/index.theme" "$TEST_ROOT/sys/icons/koompi-icons-dark/index.theme"
export XDG_DATA_DIRS="$TEST_ROOT/none:$TEST_ROOT/sys"
[[ "$(icon_theme_for light)" == koompi-icons ]] || fail "light with the theme is not koompi-icons"
[[ "$(icon_theme_for dark)" == koompi-icons-dark ]] || fail "dark with the theme is not koompi-icons-dark"

export XDG_DATA_DIRS="$TEST_ROOT/none"
mkdir -p "$HOME/.local/share/icons/koompi-icons-dark"
touch "$HOME/.local/share/icons/koompi-icons-dark/index.theme"
[[ "$(icon_theme_for dark)" == koompi-icons-dark ]] || fail "a per-user install is not found"
[[ "$(icon_theme_for light)" == breeze-plus ]] || fail "light picked a theme only dark has"

# every place the script names the theme goes through the lookup
grep -qF "icon_theme.sh" "$SWITCH" || fail "switchwall.sh does not source icon_theme.sh"
if grep -nE "(icon-theme|icon_theme=)[ =]*['\"]?koompi-icons" "$SWITCH"; then
    fail "switchwall.sh names koompi-icons without checking it is installed"
fi

echo "ok"
