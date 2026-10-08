#!/usr/bin/env bash
# The session opts into XDG autostart. hyprland-session.target ships in dots/ and
# wants xdg-desktop-autostart.target, which refuses a manual start, so nothing in the
# tree may start it by hand. Offline: nothing here talks to a user manager.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/dots/.config/systemd/user/hyprland-session.target"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

T="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT

unit_values() {
    awk -F= -v key="$2" '
        /^\[/ { in_unit = ($0 == "[Unit]") }
        { name = $1; gsub(/[ \t]/, "", name) }
        in_unit && name == key { sub(/^[^=]*=/, ""); n = split($0, v, " "); for (i = 1; i <= n; i++) print v[i] }
    ' "$1"
}
has_value() { unit_values "$1" "$2" | grep -qxF -- "$3"; }

# --- the session target ---
[[ -f "$TARGET" ]] || fail "dots/.config/systemd/user/hyprland-session.target is not shipped; a fresh install cannot start it, so graphical-session.target never activates and hypridle, the crash watcher and the portals never start"
has_value "$TARGET" BindsTo graphical-session.target || fail "the session target does not bind graphical-session.target"
has_value "$TARGET" Wants graphical-session-pre.target || fail "the session target does not want graphical-session-pre.target"
has_value "$TARGET" After graphical-session-pre.target || fail "the session target is not ordered after graphical-session-pre.target"
has_value "$TARGET" Wants xdg-desktop-autostart.target || fail "the session target does not want xdg-desktop-autostart.target, so no login item starts"
echo "ok   static: the session target binds graphical-session.target and wants xdg-desktop-autostart.target"

if command -v systemd-analyze > /dev/null 2>&1; then
    mkdir -p "$T/verify/home" "$T/verify/config" "$T/verify/data" "$T/verify/run"
    chmod 700 "$T/verify/run"
    verify_out="$(env -i PATH="$PATH" HOME="$T/verify/home" XDG_CONFIG_HOME="$T/verify/config" \
        XDG_DATA_HOME="$T/verify/data" XDG_RUNTIME_DIR="$T/verify/run" XDG_CONFIG_DIRS=/etc/xdg \
        systemd-analyze --user verify "$TARGET" 2>&1)" \
        || fail "systemd-analyze --user verify rejects the session target: $verify_out"
    [[ -z "$verify_out" ]] \
        || fail "systemd-analyze --user verify has something to say about the session target (it exits 0 on a typo like Wantz=, so any output fails): $verify_out"
    echo "ok   systemd-analyze --user verify: the session target loads without a word"
else
    echo "skip: systemd-analyze is not installed; the session target's syntax was not verified"
fi

hand_start="$(git -C "$ROOT" grep --no-color -nIE 'systemctl[^&|;]*(start|restart|isolate)[^&|;]*xdg-desktop-autostart' \
    -- . ':(exclude)tests' ':(exclude)docs' ':(exclude).work' 2>&1)"
(( $? <= 1 )) || fail "git grep failed: $hand_start"
[[ -z "$hand_start" ]] || fail "something starts xdg-desktop-autostart.target by hand; it has RefuseManualStart=yes, so the start is refused and the session target has to want it instead:
$hand_start"
echo "ok   static: nothing in the tree starts xdg-desktop-autostart.target by hand"

echo "session autostart tests passed"
