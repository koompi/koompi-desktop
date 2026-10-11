#!/usr/bin/env bash
# hyprland/shellOverrides/main.lua is the one file in hypr/hyprland that the shell writes:
# Game mode and the anti-flashbang shader live only there. Both update routes mirror that
# tree over the user's copy, so each put the shipped stub back over it:
#   sdata/install/files.sh        (./setup, the SYNC_DIRS mirror)
#   dots/.local/bin/koompi-migrate (the packaged update)
# Each now leaves the file alone while it exists, writes the stub where it is missing, and
# still mirrors the rest of hypr/hyprland, deletions included. Both run for real, against
# the real shipped tree, in a scratch home.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$ROOT/dots/.config/hypr"
STUB="$HYPR/hyprland/shellOverrides/main.lua"
OVERRIDES=".config/hypr/hyprland/shellOverrides/main.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v rsync > /dev/null 2>&1 || { echo "skip: rsync not installed"; exit 0; }
[[ -f "$STUB" ]] || fail "the shipped stub $STUB is missing"

T="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT

GAME_LINES=(
    'hl.config({animations={enabled=0}})'
    'hl.config({decoration={blur={enabled=0}}})'
    'hl.config({decoration={shadow={enabled=0}}})'
    'hl.config({decoration={rounding=0}})'
    'hl.config({general={gaps_in=0}})'
    'hl.config({general={gaps_out=0}})'
    'hl.config({general={border_size=1}})'
    'hl.config({general={allow_tearing=1}})'
)
{ cat "$STUB"; printf '%s\n' "${GAME_LINES[@]}"; } > "$T/game-overrides"

# a home carrying the shipped hypr tree, then what an install leaves drifting from it
fresh_home() {
    rm -rf "$1"
    mkdir -p "$1/.config"
    cp -a "$HYPR" "$1/.config/hypr"
}
game_mode_on() { cp -- "$T/game-overrides" "$1/$OVERRIDES"; }
drift() {
    printf 'drifted\n' > "$1/.config/hypr/hyprland/general.lua"
    printf 'stray\n' > "$1/.config/hypr/hyprland/removed_upstream.lua"
}
mirrored() {
    cmp -s -- "$1/.config/hypr/hyprland/general.lua" "$HYPR/hyprland/general.lua" \
        && [[ ! -e "$1/.config/hypr/hyprland/removed_upstream.lua" ]]
}
snapshot() { (cd -- "$1/.config" && find . -type f -exec md5sum {} + | sort -k2); }

# --- route 1: sdata/install/files.sh ---
REPO="$T/repo"
mkdir -p "$REPO/dots/.config/quickshell/koompi" "$REPO/dots/.config/quickshell/koompi-quicklook" "$REPO/dots/.local/bin" "$REPO/dots/.local/share/koompi"
cp -a "$HYPR" "$REPO/dots/.config/hypr"
touch "$REPO/dots/.config/quickshell/koompi/shell.qml" "$REPO/dots/.config/quickshell/koompi-quicklook/shell.qml" "$REPO/dots/.local/bin/koompi-x" "$REPO/dots/.local/share/koompi/x"

install_into() {
    (
        export HOME="$1" DRY_RUN=false ASSUME_YES=true NO_COLOR=1 SKIP_BACKUP=false REPO_ROOT="$REPO"
        unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_BIN_HOME XDG_CACHE_HOME BACKUP_ROOT KOOMPI_STATE_DIR
        source "$ROOT/sdata/lib/common.sh"
        source "$ROOT/sdata/install/files.sh"
        install_files
    ) > "$T/install.out" 2>&1 || fail "install_files failed: $(tail -5 "$T/install.out")"
}

A="$T/home-a"
mkdir -p "$A"
install_into "$A"
cmp -s -- "$A/$OVERRIDES" "$STUB" || fail "setup: a fresh home did not get the shipped stub"
grep -qxF -- "$A/$OVERRIDES" "$A/.local/state/koompi/installed-files" || fail "setup: the seeded stub is not in the manifest, so uninstall would leave it"
echo "ok   setup: a fresh home gets the stub, and the manifest records it"

game_mode_on "$A"
drift "$A"
install_into "$A"
cmp -s -- "$A/$OVERRIDES" "$T/game-overrides" || fail "setup: an update reset the overrides file; it now holds: $(cat "$A/$OVERRIDES")"
mirrored "$A" || fail "setup: the rest of hypr/hyprland is no longer mirrored (a drifted file stayed, or a stray one was not deleted)"
grep -q "keeping your $OVERRIDES" "$T/install.out" || fail "setup: the install did not say it kept the overrides file"
[[ ! -e "$A/.koompi-dots-backup" ]] || [[ -z "$(find "$A/.koompi-dots-backup" -path '*shellOverrides*' -type f)" ]] \
    || fail "setup: the overrides file was backed up as if the update changed it"
echo "ok   setup: a home whose overrides hold Game mode keeps them through an update, and the rest of hypr/hyprland is still mirrored"

before="$(snapshot "$A")"
install_into "$A"
[[ "$(snapshot "$A")" == "$before" ]] || fail "setup: a second update changed the home"
echo "ok   setup: a second update changes nothing"

rm -- "$A/$OVERRIDES"
install_into "$A"
cmp -s -- "$A/$OVERRIDES" "$STUB" || fail "setup: a missing overrides file was not put back, so the config would fail on its require"
echo "ok   setup: a missing overrides file is seeded again"

# --- route 2: koompi-migrate ---
SKEL="$T/skel"
mkdir -p "$SKEL/.config"
cp -a "$HYPR" "$SKEL/.config/hypr"

migrate() {
    local home=$1; shift
    (
        export HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share"
        export KOOMPI_MIGRATE_SKEL="$SKEL" KOOMPI_MIGRATE_XDG="$T/no-xdg"
        unset HYPRLAND_INSTANCE_SIGNATURE KOOMPI_STATE_DIR KOOMPI_CONFIG_FILE
        "$ROOT/dots/.local/bin/koompi-migrate" "$@"
    ) > "$T/migrate.out" 2>&1 || fail "koompi-migrate $* failed: $(tail -5 "$T/migrate.out")"
}

B="$T/home-b"
fresh_home "$B"
rm -rf "$B/.config/hypr/hyprland/shellOverrides"
migrate "$B"
grep -q 'sync .*hypr/hyprland' "$T/migrate.out" || fail "migrate: a dry run did not report the missing overrides file: $(cat "$T/migrate.out")"
[[ ! -e "$B/$OVERRIDES" ]] || fail "migrate: a dry run wrote the stub"
migrate "$B" --apply
cmp -s -- "$B/$OVERRIDES" "$STUB" || fail "migrate: a home with no overrides file did not get the stub"
echo "ok   migrate: a home with no overrides file gets the stub, and a dry run only reports it"

fresh_home "$B"
game_mode_on "$B"
drift "$B"
migrate "$B" --apply
cmp -s -- "$B/$OVERRIDES" "$T/game-overrides" || fail "migrate: an update reset the overrides file; it now holds: $(cat "$B/$OVERRIDES")"
mirrored "$B" || fail "migrate: the rest of hypr/hyprland is no longer mirrored (a drifted file stayed, or a stray one was not deleted)"
echo "ok   migrate: a home whose overrides hold Game mode keeps them through an update, and the rest of hypr/hyprland is still mirrored"

migrate "$B"
grep -q 'everything up to date' "$T/migrate.out" || fail "migrate: Game mode in the overrides file still counts as a pending change: $(cat "$T/migrate.out")"
echo "ok   migrate: the overrides file is never a pending change"

echo "hypr overrides survive both update routes"
