#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIG="$(ls "$ROOT"/sdata/migrations/*-cursor-bibata.sh)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

mkdir -p "$TEST_ROOT/share/icons/Bibata-Modern-Classic" "$TEST_ROOT/nothing"
touch "$TEST_ROOT/share/icons/Bibata-Modern-Classic/index.theme"
DATA_DIRS="$TEST_ROOT/share"

# run_with NAME GSETTINGS_VALUE [INDEX_INHERITS]; prints the home
run_with() {
    local home="$TEST_ROOT/$1" gs="$2" inh="${3:-}"
    mkdir -p "$home/.config" "$home/.icons/default"
    rm -f "$home/.icons/default/index.theme"
    [[ -z $inh ]] || printf '[Icon Theme]\nInherits=%s\n' "$inh" > "$home/.icons/default/index.theme"
    export HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
        XDG_DATA_DIRS="$DATA_DIRS" GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas
    [[ -z $gs ]] || gsettings set org.gnome.desktop.interface cursor-theme "$gs"
    bash -euo pipefail "$MIG" >/dev/null
    printf '%s\n' "$home"
}
gs_value() { HOME="$1" XDG_CONFIG_HOME="$1/.config" GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas gsettings get org.gnome.desktop.interface cursor-theme; }

h="$(run_with shipped Adwaita Adwaita)"
grep -qx 'Inherits=Bibata-Modern-Classic' "$h/.icons/default/index.theme" || fail "the fallback did not move"
[[ "$(gs_value "$h")" == "'Bibata-Modern-Classic'" ]] || fail "gsettings did not move"

h="$(run_with packaged Adwaita)"
grep -qx 'Inherits=Bibata-Modern-Classic' "$h/.icons/default/index.theme" || fail "a packaged user got no fallback"

h="$(run_with picked Layan Layan)"
grep -qx 'Inherits=Layan' "$h/.icons/default/index.theme" || fail "a user-picked fallback was changed"
[[ "$(gs_value "$h")" == "'Layan'" ]] || fail "a user-picked gsettings cursor was changed"

h="$(run_with pickedbare Layan)"
[[ ! -e "$h/.icons/default/index.theme" ]] || fail "a user who picked another cursor got a fallback written"

h="$(run_with again Adwaita Adwaita)"
HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_DIRS="$DATA_DIRS" GSETTINGS_BACKEND=keyfile GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas bash -euo pipefail "$MIG" >/dev/null || fail "second run failed"
grep -qx 'Inherits=Bibata-Modern-Classic' "$h/.icons/default/index.theme" || fail "second run undid the move"

DATA_DIRS="$TEST_ROOT/nothing"
h="$(run_with notheme Adwaita Adwaita)"
grep -qx 'Inherits=Adwaita' "$h/.icons/default/index.theme" || fail "moved to a theme that is not installed"
[[ "$(gs_value "$h")" == "'Adwaita'" ]] || fail "gsettings moved to a theme that is not installed"

echo "ok"
