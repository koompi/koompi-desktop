#!/usr/bin/env bash
# 4-finger up opens the overview and down closes it; neither toggles, so repeating a motion never undoes it
set -uo pipefail
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL="$REPO_ROOT/dots/.config/hypr/hyprland/general.lua"
PANEL="$REPO_ROOT/dots/.config/quickshell/koompi/modules/koompi/overview/OverviewPanel.qml"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

action_for() { # the global a 4-finger gesture in direction $1 dispatches
    awk -v dir="$1" '/hl\.gesture\(\{/{blk=""; on=1} on{blk=blk $0 "\n"} on&&/^\}\)/{on=0; if (blk ~ /fingers = 4/ && blk ~ ("direction = \"" dir "\"")) print blk}' "$GENERAL" \
        | grep -oE 'quickshell:[A-Za-z]+' | head -1
}

[[ "$(action_for up)" == "quickshell:overviewWorkspacesOpen" ]] || fail "4-finger up does not open the overview (got '$(action_for up)')"
[[ "$(action_for down)" == "quickshell:overviewWorkspacesClose" ]] || fail "4-finger down does not close the overview (got '$(action_for down)')"
grep -q 'name: "overviewWorkspacesOpen"' "$PANEL" || fail "the shell has no overviewWorkspacesOpen shortcut for the gesture to reach"
echo "ok   4-finger up opens the overview, down closes it, and the shell answers both"
