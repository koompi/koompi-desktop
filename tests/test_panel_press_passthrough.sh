#!/usr/bin/env bash
# A pinned side panel learns it was clicked from a handler laid over its content.
# J57 used a TapHandler there; it accepted every press, so no button, toggle or
# notification in either sidebar could be clicked. The overlay must only watch.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/dots/.config/quickshell/koompi/modules/koompi"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in sidebarLeft/SidebarLeft.qml sidebarRight/SidebarRight.qml; do
    block="$(grep -A6 'z: 100' "$SHELL_DIR/$f" | grep -v '^ *//' | grep -B2 -A2 'engaged = true')"
    [[ -n $block ]] || fail "$f: no engaged overlay found"
    grep -q 'PointHandler' <<< "$block" || fail "$f: the engaged overlay is not a PointHandler"
    grep -q 'TapHandler' <<< "$block" && fail "$f: a TapHandler on the overlay swallows every click"
done
echo "ok   source: both sidebars watch presses with a PointHandler"

runner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $runner ]] || { echo "skip: Qt 6 qmltestrunner not installed, static check only"; exit 0; }
out="$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen timeout 60 "$runner" -input "$REPO_ROOT/tests/qml/tst_press_passthrough.qml" 2>&1)"
grep -q '^Totals: 3 passed, 0 failed' <<< "$out" || { printf '%s\n' "$out" >&2; fail "a click under the overlay did not reach the button"; }
echo "ok   live: a click under a PointHandler overlay reaches the button and still engages the panel"
