#!/usr/bin/env bash
# J23: an un-prefixed query asks every provider. "sound" matches an application, a
# Settings page, a command and a file in a temp HOME, and Search lists them under
# Top Hit / Applications / Commands and Settings / Files, in that order. The file
# row says its folder and when it changed; the capture command carries the keycaps
# of its Hyprland bind. On dev a file never appeared without "~".
#
# Loads the real LauncherSearch in a probe shell, headless KWin on a private bus.
# fd finds the file; the bind list is a fixture, because there is no Hyprland here.
set -uo pipefail
shopt -s extglob

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in qs kwin_wayland dbus-run-session fd; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/rt" "$WORK/home/Documents" "$WORK/config" "$WORK/state/quickshell/user" \
         "$WORK/cache" "$WORK/data/applications"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf 'x\n' > "$WORK/home/Documents/sound-notes.txt"
printf '[Desktop Entry]\nType=Application\nName=Sound Studio\nExec=studio\n' > "$WORK/data/applications/studio.desktop"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/blend_probe.qml" <<'QML'
import qs.services
import qs.modules.common
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    property string firstKeyEarly: ""

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }

    // hyprctl is absent here and its error text parses as one empty bind, so the
    // fixture goes in after that has landed, not before
    function seedBinds() {
        // SUPER + SHIFT + ALT + R, as hyprctl binds lists it for the shipped config
        HyprlandKeybinds.rawBinds = [({
                bindType: "bind", modmask: 64 + 1 + 8, submap: "", key: "R", keycode: 0, catchall: false,
                description: "Utilities: Record screen (with sound)", dispatcher: "__lua", arg: ""
            })];
        HyprlandKeybinds.merge();
    }

    Component.onCompleted: {
        LauncherSearch.query = "sound";
        probe.firstKeyEarly = LauncherSearch.results.length > 0 ? LauncherSearch.results[0].key : "";
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            const done = LauncherSearch.results.some(row => row.key.startsWith("file|"));
            if (!done && waited < 12000)
                return;
            running = false;
            probe.run();
        }
    }

    function run() {
        probe.seedBinds();
        const rows = LauncherSearch.results;
        console.log("VIEW  'sound':");
        rows.forEach(row => console.log("VIEW    " + [row.heading, row.name, row.type, JSON.stringify(row.shortcut ?? [])].join(" | ")));
        probe.check("sections: Top Hit, then Applications, Commands and Settings, Files, in that order",
            rows.filter(row => row.heading !== "").map(row => row.heading), ["Top Hit", "Applications", "Commands and Settings", "Files"]);
        probe.check("top: the Settings page that is called exactly that", rows[0].key, "settings|Sound");
        probe.check("late: the file landing after the debounce left the Top Hit where it was", rows[0].key, probe.firstKeyEarly);
        probe.check("apps: the application is listed", rows.some(row => row.name === "Sound Studio"), true);

        const file = rows.find(row => row.key.startsWith("file|"));
        probe.check("file: found without a ~ in front of the query", file ? file.name : "", "sound-notes.txt");
        probe.check("file: its folder and its date are on the row",
            /^~\/Documents  ·  Today \d\d:\d\d$/.test(file ? file.type : ""), true);
        probe.check("file: Space previews this path", file ? file.previewPath.endsWith("/Documents/sound-notes.txt") : false, true);

        const record = rows.find(row => row.name === "Record screen with sound");
        const superKey = Config.options.cheatsheet.superKey || "Super";
        probe.check("command: a capture command is in the list with its keycaps",
            record ? record.shortcut : null, [superKey, "Alt", "Shift", "R"]);
        probe.check("command: a command with no bind shows no keycaps",
            CommandTree.results("night")[0].shortcut, []);
        probe.check("tail: the web search is the last row", rows[rows.length - 1].key, "web");

        LauncherSearch.query = "~sound";
        probe.check("sigil: ~ still lists only files, under Recent / Files headings",
            LauncherSearch.results.filter(row => row.heading !== "").map(row => row.heading).every(h => h === "Recent" || h === "Files"), true);
        console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
        Qt.quit();
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
cd "$WORK/shell" || exit 1
timeout 60 qs -p blend_probe.qml > "$WORK/qs.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" WORK="$WORK" PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" \
    XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
    XDG_DATA_HOME="$WORK/data" XDG_DATA_DIRS="$WORK/data" \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

plain="$(cat -- "$WORK/qs.log" 2> /dev/null)"
plain="${plain//$'\e'\[*([0-9;])m/}"
grep -E '^ DEBUG qml: (PASS|FAIL|VIEW|PROBE)' <<< "$plain" | sed 's/^ DEBUG qml: //' || true
if ! grep -q "PROBE OK" <<< "$plain"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|^\s*$" <<< "$plain" >&2
    echo "--- kwin ---" >&2
    tail -20 "$WORK/kwin.log" >&2
    fail "the blended Search probe did not pass"
fi
echo "ok   blended: 'sound' lists Top Hit, Applications, Commands and Settings, Files in order; the file row carries its folder and date; the capture command carries its keycaps"
