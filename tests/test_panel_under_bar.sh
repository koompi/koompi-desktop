#!/usr/bin/env bash
# A panel that hangs from the bar comes out from beneath it, never across it (docs/navigation.md, Motion).
# Hyprland's `slide top` starts a layer at the screen edge, so the card crosses the bar on its way down.
# A panel that should drop down does the move itself, in a window that starts under the bar and clips;
# anything else under the bar appears in place (Hyprland's popin).
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$REPO_ROOT/dots/.config/hypr/hyprland/rules.lua"
CC="$REPO_ROOT/dots/.config/quickshell/koompi/modules/koompi/controlCenter/ControlCenter.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -nE 'animation *= *"slide top"' "$RULES" && fail "a layer slides in from the top edge, across the bar"
echo "ok   no layer slides down from the screen edge across the bar"

if [[ -f "$CC" ]]; then
    grep -qE 'namespace = "quickshell:controlCenter" \}, no_anim = true' "$RULES" || fail "Hyprland still animates the Control Center's layer"
    grep -q 'top: Appearance.sizes.barHeight' "$CC" || fail "the Control Center's window does not start at the bar's lower edge"
    grep -q 'clip: true' "$CC" || fail "the Control Center does not clip, so its card would show above the bar's edge"
    grep -q 'property real reveal' "$CC" || fail "the Control Center has no reveal to slide its card on"
    echo "ok   the Control Center drops from under the bar: window at the bar's edge, clipped, its own slide"
fi
