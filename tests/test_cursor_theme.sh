#!/usr/bin/env bash
# One cursor, Bibata-Modern-Classic at 24, everywhere. The theme is stated in four places that cannot read each other, and
# when they drift the session shows two pointers: everything follows
# XCURSOR_THEME except an X11 client that names no theme, which follows
# ~/.icons/default and so gets whatever the installer wrote there. Telegram
# under XWayland is one of those clients, which is how the drift got noticed.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUPS="$ROOT/sdata/install/setups/desktop.sh"
ENV_LUA="$ROOT/dots/.config/hypr/hyprland/env.lua"
EXECS_LUA="$ROOT/dots/.config/hypr/hyprland/execs.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

want="$(grep -oP "^readonly KOOMPI_CURSOR_THEME='\K[^']+" "$SETUPS")"
want_size="$(grep -oP '^readonly KOOMPI_CURSOR_SIZE=\K.+' "$SETUPS")"
[[ -n "$want" && -n "$want_size" ]] || fail "setups.sh no longer declares the cursor theme and size"

env_theme="$(grep -oP '^local cursor_theme = "\K[^"]+' "$ENV_LUA" || true)"
grep -q 'hl\.env("XCURSOR_THEME", cursor_theme)' "$ENV_LUA" \
    || fail "env.lua no longer exports XCURSOR_THEME from cursor_theme"
env_size="$(grep -oP 'hl\.env\("XCURSOR_SIZE", "\K[^"]+' "$ENV_LUA")"
[[ "$env_theme" == "$want" ]] \
    || fail "env.lua exports XCURSOR_THEME=$env_theme but the installer ships $want"
[[ "$env_size" == "$want_size" ]] \
    || fail "env.lua exports XCURSOR_SIZE=$env_size but the installer ships $want_size"

grep -q 'hyprctl setcursor " \.\. (os\.getenv("XCURSOR_THEME")' "$EXECS_LUA" \
    || fail "execs.lua no longer sets the compositor cursor from the theme env.lua exports"
exec_size="$(grep -oP 'hyprctl setcursor .* \K[0-9]+(?=")' "$EXECS_LUA" || true)"
[[ "$exec_size" == "$want_size" ]] \
    || fail "execs.lua sets the cursor size to $exec_size but the installer ships $want_size"

# The fallback the installer writes is the one an X11 client with no theme of
# its own lands on, so it is the copy that has to agree, not just exist.
grep -q 'Inherits=\${theme}' "$SETUPS" \
    || fail "the ~/.icons/default fallback no longer derives from the resolved theme"
grep -q 'cursor-theme "\$theme"' "$SETUPS" \
    || fail "the gsettings cursor-theme no longer derives from the resolved theme"
[[ "$want" == "Bibata-Modern-Classic" && "$want_size" == 24 ]] \
    || fail "the shipped cursor is $want at $want_size, not Bibata-Modern-Classic at 24"
bibata="$ROOT/sdata/dist-arch/koompi-bibata-modern-classic-bin/PKGBUILD"
grep -q "^_variant=$want\$" "$bibata" || fail "the Bibata package ships a directory other than $want"
grep -q "koompi-bibata-modern-classic-bin" "$ROOT/sdata/dist-arch/koompi-base/PKGBUILD" \
    || fail "koompi-base no longer depends on the cursor package"

# A theme that is not on disk must not be named: toolkits pick unpredictable stand-ins.
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
(
    source "$SETUPS"
    export HOME="$T/home" XDG_DATA_HOME="$T/home/.local/share" XDG_DATA_DIRS="$T/share"
    mkdir -p "$HOME" "$T/share/icons"
    ! cursor_theme_available || fail "a missing $want counted as installed"
    mkdir -p "$T/share/icons/$want" && touch "$T/share/icons/$want/index.theme"
    cursor_theme_available || fail "an installed $want was not found"
    DRY_RUN=false; manifest_add() { :; }; info() { :; }; ok() { :; }; warn() { :; }; err() { :; }
    setup_cursor_default Adwaita
    grep -qx 'Inherits=Adwaita' "$HOME/.icons/default/index.theme" || fail "the fallback did not follow the theme it was given"
) || exit 1

# Live check: the running session is a fifth statement of the same thing, and it
# is the one the user actually sees.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    live="$HOME/.icons/default/index.theme"
    if [[ -f "$live" ]]; then
        got="$(grep -oP '^Inherits=\K.+' "$live" || true)"
        [[ "$got" == "$want" ]] \
            || fail "this machine's X11 cursor fallback is $got, not $want; run ./setup install"
    fi
fi

echo "ok"
