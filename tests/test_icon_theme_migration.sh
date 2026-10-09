#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$(ls "$ROOT"/sdata/migrations/*-koompi-icons-theme.sh)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$TEST_ROOT/share/icons/koompi-icons" "$TEST_ROOT/share/icons/koompi-icons-dark" "$TEST_ROOT/nothing"
touch "$TEST_ROOT/share/icons/koompi-icons/index.theme" "$TEST_ROOT/share/icons/koompi-icons-dark/index.theme"
DATA_DIRS="$TEST_ROOT/share"

run_with() {
    local home="$TEST_ROOT/$1" kdeglobals="$2" qt6ct="$3" myc="$4"
    mkdir -p "$home/.config/qt6ct" "$home/.config/kde-material-you-colors"
    printf '[General]\nColorScheme=x\n\n[Icons]\nTheme=%s\n\n[KDE]\nfoo=bar\n' "$kdeglobals" > "$home/.config/kdeglobals"
    printf '[Appearance]\nicon_theme=%s\nstyle=Darkly\n' "$qt6ct" > "$home/.config/qt6ct/qt6ct.conf"
    printf 'iconslight = %s\niconsdark = %s\n' "${myc%%,*}" "${myc##*,}" > "$home/.config/kde-material-you-colors/config.conf"
    HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_DIRS="$DATA_DIRS" GSETTINGS_BACKEND=keyfile \
        bash -euo pipefail "$MIG" >/dev/null
    printf '%s\n' "$home"
}

h="$(run_with shipped breeze-plus-dark breeze-plus-dark breeze-plus,breeze-plus-dark)"
grep -qx 'Theme=koompi-icons-dark' "$h/.config/kdeglobals" || fail "kdeglobals did not move"
grep -qx 'foo=bar' "$h/.config/kdeglobals" || fail "kdeglobals lost another key"
grep -qx 'icon_theme=koompi-icons-dark' "$h/.config/qt6ct/qt6ct.conf" || fail "qt6ct did not move"
grep -qx 'iconslight = koompi-icons' "$h/.config/kde-material-you-colors/config.conf" || fail "iconslight did not move"
grep -qx 'iconsdark = koompi-icons-dark' "$h/.config/kde-material-you-colors/config.conf" || fail "iconsdark did not move"

h="$(run_with light breeze-plus breeze-plus breeze-plus,breeze-plus-dark)"
grep -qx 'Theme=koompi-icons' "$h/.config/kdeglobals" || fail "light kdeglobals did not move"

h="$(run_with picked Papirus Papirus Papirus,Papirus-Dark)"
grep -qx 'Theme=Papirus' "$h/.config/kdeglobals" || fail "a user-picked theme was changed in kdeglobals"
grep -qx 'icon_theme=Papirus' "$h/.config/qt6ct/qt6ct.conf" || fail "a user-picked theme was changed in qt6ct"
grep -qx 'iconsdark = Papirus-Dark' "$h/.config/kde-material-you-colors/config.conf" || fail "a user-picked theme was changed in config.conf"

h="$(run_with again breeze-plus-dark breeze-plus-dark breeze-plus,breeze-plus-dark)"
HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_DIRS="$DATA_DIRS" bash -euo pipefail "$MIG" >/dev/null || fail "second run failed"
grep -qx 'Theme=koompi-icons-dark' "$h/.config/kdeglobals" || fail "second run undid the move"

# theme not installed: nothing moves, and the run still succeeds so the update does not fail
DATA_DIRS="$TEST_ROOT/nothing"
h="$(run_with notheme breeze-plus-dark breeze-plus-dark breeze-plus,breeze-plus-dark)"
grep -qx 'Theme=breeze-plus-dark' "$h/.config/kdeglobals" || fail "kdeglobals moved to a theme that is not installed"
grep -qx 'icon_theme=breeze-plus-dark' "$h/.config/qt6ct/qt6ct.conf" || fail "qt6ct moved to a theme that is not installed"
grep -qx 'iconsdark = breeze-plus-dark' "$h/.config/kde-material-you-colors/config.conf" || fail "config.conf moved to a theme that is not installed"
DATA_DIRS="$TEST_ROOT/share"

HOME="$TEST_ROOT/empty" XDG_DATA_DIRS="$DATA_DIRS" XDG_CONFIG_HOME="$TEST_ROOT/empty/.config" bash -euo pipefail "$MIG" >/dev/null || fail "a home with none of the files failed"

echo "ok"
