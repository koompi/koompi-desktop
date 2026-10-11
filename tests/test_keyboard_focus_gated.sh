#!/usr/bin/env bash
# A layer surface asks for keyboard focus only while its own flag says it is open: `GlobalStates.x ? OnDemand : None`.
# A bare OnDemand or Exclusive keeps the mapped window in the compositor's focus list whatever the panel is doing.
# Windows that only exist while shown (modal dialogs, capture overlays) are named below with the reason.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

command -v python3 > /dev/null 2>&1 || { echo "skip: python3 not installed"; exit 0; }

python3 -I - "$SHELL_ROOT" <<'PY'
import re
import sys
from pathlib import Path

ALLOWED = {
    "modules/koompi/sidebarLeft/aiChat/feedback/FeedbackWindow.qml": "modal dialog, created when asked for",
    "modules/koompi/sidebarLeft/aiChat/feedback/CorrectionWindow.qml": "modal dialog, created when asked for",
    "modules/koompi/sidebarLeft/aiChat/memory/MemoryBrowserWindow.qml": "modal dialog, created when asked for",
    "modules/koompi/regionSelector/RegionSelection.qml": "visible: false until a capture starts",
    "modules/waffle/screenSnip/WRegionSelectionPanel.qml": "visible: false until a capture starts",
    "modules/koompi/screenTranslator/ScreenTranslatorPanel.qml": "visible: false until a capture starts",
    "modules/koompi/screensaver/ScreensaverSurface.qml": "exists only while the screensaver runs",
    "modules/koompi/sessionScreen/SessionScreen.qml": "visible: GlobalStates.sessionOpen, modal",
    "modules/waffle/sessionScreen/WaffleSessionScreen.qml": "loaded while GlobalStates.sessionOpen, modal",
    "modules/common/widgets/FullscreenPolkitWindow.qml": "exists only while an authentication is asked",
}
PROP = re.compile(r"^[ \t]*WlrLayershell\.keyboardFocus:[ \t]*(.*(?:\n[ \t]*[?:].*)*)", re.M)


def ungated(text):
    bad = []
    for m in PROP.finditer(text):
        value = " ".join(m.group(1).split())
        if value == "WlrKeyboardFocus.None":
            continue
        if "?" in value and "WlrKeyboardFocus.None" in value:
            continue
        bad.append((text.count("\n", 0, m.start()) + 1, value))
    return bad


fixtures = [
    ("WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand", True),
    ("WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive", True),
    ("WlrLayershell.keyboardFocus: GlobalStates.x ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None", False),
    ("WlrLayershell.keyboardFocus: a\n    ? WlrKeyboardFocus.OnDemand\n    : WlrKeyboardFocus.None", False),
    ("WlrLayershell.keyboardFocus: WlrKeyboardFocus.None", False),
    ("// WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive", False),
]
for text, want in fixtures:
    if bool(ungated(text)) != want:
        print(f"FAIL: the scan broke on: {text!r}, wanted ungated={want}")
        sys.exit(1)

root = Path(sys.argv[1])
problems, seen = [], set()
for path in sorted(root.rglob("*.qml")):
    rel = path.relative_to(root).as_posix()
    for line, value in ungated(path.read_text(errors="replace")):
        if rel in ALLOWED:
            seen.add(rel)
        else:
            problems.append(f"{rel}:{line}: keyboardFocus is {value}, not gated on the surface's own open flag")
for rel in sorted(set(ALLOWED) - seen):
    problems.append(f"{rel}: listed as an allowed ungated window but it is gated or gone; drop it from the list")
if problems:
    print("\n".join("FAIL: " + p for p in problems))
    sys.exit(1)
print(f"ok   focus: every layer surface asks for the keyboard only while its flag is open ({len(seen)} on-demand windows named)")
PY
