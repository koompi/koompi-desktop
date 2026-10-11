#!/usr/bin/env bash
# A notification about a file (a screenshot's "Screenshot saved" with its path as the body) offers
# Copy path and Show in folder, both in the app groups and in the System group, and System does
# not fold files together: nine screenshots are nine paths.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$REPO_ROOT/dots/.config/quickshell/koompi"
ITEM="$QS/modules/common/widgets/NotificationItem.qml"
SYS="$QS/modules/koompi/sidebarRight/notifications/SystemGroup.qml"
JS="$QS/services/notification-system.js"
SHOT="$QS/modules/common/utils/ScreenshotAction.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q "notify-send 'Screenshot saved' \"\$savePath\"" "$SHOT" || fail "the snip no longer names the saved file as the notification body"
for f in "$ITEM" "$SYS"; do
  grep -q 'Translation.tr("Copy path")' "$f" || fail "${f##*/}: file notifications have no Copy path"
  grep -q 'Translation.tr("Show in folder")' "$f" || fail "${f##*/}: file notifications have no Show in folder"
  grep -q 'FileReveal.show(' "$f" || fail "${f##*/}: Show in folder does not use the shared file-manager call"
done
grep -q "FileManager1.ShowItems" "$QS/services/FileReveal.qml" || fail "Show in folder does not ask the file manager to select the file"
echo "ok   file notifications: Copy path and Show in folder, in app groups and in System"

command -v node > /dev/null || { echo "skip: no node for the fold check"; exit 0; }
node - "$JS" <<'JS' || fail "the file-path reading or the System fold is wrong"
const src = require("fs").readFileSync(process.argv[2], "utf8").replace(".pragma library", "");
const m = {}; new Function("m", src + "; m.filePath = filePath; m.foldRows = foldRows;")(m);
const cases = [
  ["/home/u/Pictures/Screenshots/2026-10-11/screenshot-2026-10-11_21.28.42.png", true],
  ["file:///home/u/Videos/recording.mp4", true],
  ["/home/u/My Files/report.pdf", true],
  ["Your Claude assistant needs re-authentication", false],
  ["Stopped", false],
  ["<b>/etc/passwd</b>", false],
  ["see /tmp/x for details", false],
];
let ok = true;
for (const [body, want] of cases) if ((m.filePath(body) !== "") !== want) { console.error(`'${body}' read as a file: ${!want}`); ok = false; }
const rows = m.foldRows([
  { summary: "Screenshot saved", body: "/p/a.png", notificationId: 1, time: 1 },
  { summary: "Screenshot saved", body: "/p/b.png", notificationId: 2, time: 2 },
  { summary: "Battery low", body: "10% left", notificationId: 3, time: 3 },
  { summary: "Battery low", body: "8% left", notificationId: 4, time: 4 },
]);
const shots = rows.filter(r => r.summary === "Screenshot saved");
if (shots.length !== 2 || shots[0].path !== "/p/b.png") { console.error("screenshots folded: " + JSON.stringify(shots)); ok = false; }
const low = rows.filter(r => r.summary === "Battery low");
if (low.length !== 1 || low[0].count !== 2 || low[0].path !== "") { console.error("same-summary prose stopped folding: " + JSON.stringify(low)); ok = false; }
process.exit(ok ? 0 : 1);
JS
echo "ok   one absolute path reads as a file; files are their own rows; prose still folds"
