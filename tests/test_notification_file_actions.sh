#!/usr/bin/env bash
# A notification about a file (a screenshot's "Screenshot saved" with its path as the body) offers
# Copy path and Show in folder, so the file can be found again from the panel.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ITEM="$REPO_ROOT/dots/.config/quickshell/koompi/modules/common/widgets/NotificationItem.qml"
SHOT="$REPO_ROOT/dots/.config/quickshell/koompi/modules/common/utils/ScreenshotAction.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q "notify-send 'Screenshot saved' \"\$savePath\"" "$SHOT" || fail "the snip no longer names the saved file as the notification body"
grep -q 'objectName: "notificationCopyPath"' "$ITEM" || fail "file notifications have no Copy path button"
grep -q 'Quickshell.clipboardText = root.filePath' "$ITEM" || fail "Copy path does not copy the file's path"
grep -q 'objectName: "notificationShowInFolder"' "$ITEM" || fail "file notifications have no Show in folder button"
grep -q 'FileManager1.ShowItems' "$ITEM" || fail "Show in folder does not ask the file manager to select the file"
echo "ok   file notifications: Copy path and Show in folder"

# the same test the QML runs on the body, on real and false bodies
re=$(sed -n 's|.*return /\(.*\)/\.test(body).*|\1|p' "$ITEM")
[[ -n $re ]] || fail "cannot read the file-path test from NotificationItem.qml"
check() { # check <body> <want 1|0>
  local got=0
  printf '%s' "$1" | grep -qP "^${re#^}" && got=1
  [[ $got == "$2" ]] || fail "body '$1' read as a file: $got, wanted $2"
}
check "/home/u/Pictures/Screenshots/2026-10-11/screenshot-2026-10-11_21.28.42.png" 1
check "/home/u/My Files/report.pdf" 1
check "Your Claude assistant needs re-authentication" 0
check "Stopped" 0
check "<b>/etc/passwd</b>" 0
echo "ok   a body that is one absolute path reads as a file; prose and markup do not"
