#!/usr/bin/env bash
# The plate masks an icon only when it knows the theme the shell draws from. The shell's Qt
# takes its icon theme from qt6ct (env.lua sets QT_QPA_PLATFORMTHEME=qt6ct), not kdeglobals,
# and the two can differ: a seat with kdeglobals on breeze-dark and qt6ct on koompi-icons-dark
# drew WhiteSur icons the plate never cut.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$ROOT/dots/.config/quickshell/koompi"
INDEX="$SHELL_DIR/scripts/colors/icon_theme_index.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$INDEX" ]] || fail "scripts/colors/icon_theme_index.sh is missing"
grep -qF 'scripts/colors/icon_theme_index.sh' "$SHELL_DIR/modules/common/widgets/AppIconBodies.qml" \
    || fail "AppIconBodies.qml does not read the theme through icon_theme_index.sh"
grep -qF 'hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")' "$ROOT/dots/.config/hypr/hyprland/env.lua" \
    || fail "env.lua no longer sets qt6ct; the qt6ct branch below no longer describes the session"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/home" "$WORK/config/qt6ct" "$WORK/data/icons/koompi-icons-dark/apps/scalable" \
    "$WORK/data/icons/koompi-icons-dark/devices/scalable" "$WORK/data/icons/breeze-dark/apps/scalable"
touch "$WORK/data/icons/koompi-icons-dark/apps/scalable/firefox.svg" \
    "$WORK/data/icons/koompi-icons-dark/devices/scalable/computer.svg" \
    "$WORK/data/icons/breeze-dark/apps/scalable/kate.svg"
printf '[General]\nfoo=1\n\n[Icons]\nTheme=breeze-dark\n' > "$WORK/config/kdeglobals"
printf '[Appearance]\nicon_theme=koompi-icons-dark\nstyle=Darkly\n' > "$WORK/config/qt6ct/qt6ct.conf"

index() { # VAR=value... for the run
    env -i PATH="$PATH" HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/home/.local/share" \
        XDG_DATA_DIRS="$WORK/data" "$@" bash "$INDEX"
}

out="$(index QT_QPA_PLATFORMTHEME=qt6ct)"
[[ "$(head -1 <<< "$out")" == koompi-icons-dark ]] || fail "under qt6ct the theme is qt6ct's icon_theme, got: $(head -1 <<< "$out")"
[[ "$(tail -n +2 <<< "$out" | sort | tr '\n' ' ')" == "computer firefox " ]] \
    || fail "the names are the qt6ct theme's apps and devices, got: $(tail -n +2 <<< "$out" | tr '\n' ' ')"

out="$(index QT_QPA_PLATFORMTHEME=kde)"
[[ "$out" == $'breeze-dark\nkate' ]] || fail "without qt6ct the theme is kdeglobals' [Icons] Theme, got: $out"

out="$(index QT_QPA_PLATFORMTHEME=qt6ct QS_ICON_THEME=breeze-dark)"
[[ "$(head -1 <<< "$out")" == breeze-dark ]] || fail "QS_ICON_THEME overrides both, got: $(head -1 <<< "$out")"

printf '[Appearance]\nstyle=Darkly\n' > "$WORK/config/qt6ct/qt6ct.conf"
out="$(index QT_QPA_PLATFORMTHEME=qt6ct)"
[[ "$(head -1 <<< "$out")" == breeze-dark ]] || fail "a qt6ct.conf with no icon_theme falls back to kdeglobals, got: $(head -1 <<< "$out")"

rm -f "$WORK/config/kdeglobals" "$WORK/config/qt6ct/qt6ct.conf"
out="$(index QT_QPA_PLATFORMTHEME=qt6ct)"
[[ -z "$out" ]] || fail "no theme anywhere prints one empty line and no names, got: $out"

echo "ok   the plate reads the icon theme the shell draws from: QS_ICON_THEME, then qt6ct under qt6ct, then kdeglobals"
