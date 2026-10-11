#!/usr/bin/env bash
# Every status glyph on the bar answers a click: it does its job, or at least opens the panel
# where that thing lives. A glyph that only shows a tooltip reads as broken.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$REPO_ROOT/dots/.config/quickshell/koompi"
BAR="$QS/modules/koompi/bar"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'toggleSidebarRightOn("wifi")' "$BAR/NetworkIndicator.qml" || fail "the network glyph does not open the network list"
for f in "$BAR/BarContent.qml" "$QS/modules/koompi/verticalBar/VerticalBarContent.qml"; do
  grep -q 'NetworkIndicator' "$f" || fail "${f##*/} draws its own network glyph instead of NetworkIndicator"
  grep -q 'text: Network.materialSymbol' "$f" && fail "${f##*/} has a bare network glyph with no click"
done
echo "ok   the network glyph opens the network list, on both bars"

grep -q 'toggleSidebarRightOn("battery")' "$BAR/BatteryIndicator.qml" || fail "the battery glyph does not open the battery page"
grep -q 'switchxkblayout' "$BAR/HyprlandXkbIndicator.qml" || fail "the input source does not switch on click"
echo "ok   battery opens its page; the input source switches layout"

# every mode light has a click
lights=$(grep -c '^    ModeIndicator {' "$BAR/ModeIndicators.qml")
toggles=$(grep -c '^        toggle:' "$BAR/ModeIndicators.qml")
[ "$lights" -eq "$toggles" ] || fail "$((lights - toggles)) mode light(s) do nothing on click ($toggles of $lights)"
echo "ok   all $lights mode lights answer a click"

# the request reaches the panel and lands on that list
grep -q 'signal sidebarRightModuleRequested' "$QS/GlobalStates.qml" || fail "GlobalStates has no panel-page request"
grep -q 'onSidebarRightModuleRequested' "$QS/modules/koompi/sidebarRight/SidebarRight.qml" || fail "the right panel ignores page requests"
for m in wifi battery sound; do
  grep -q "\"$m\"" "$QS/modules/koompi/sidebarRight/SidebarRight.qml" || fail "the right panel has no '$m' page"
done
echo "ok   the right panel opens on the page the glyph asked for"
