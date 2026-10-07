#!/usr/bin/env bash
# Quickshell's FileView applies what a finished write wrote back to the adapter, so an
# edit made while Config's or Persistent's own write is in flight is undone when that
# write lands, and the follow-up write finds nothing changed and does nothing: the
# setting is lost in memory and on disk. Both singletons therefore write synchronously
# (blockWrites), and an edit can no longer fall inside a write.
# Each probe edits in a real qs, in a headless KWin on a private bus and runtime dir,
# at a time around where a write is in flight, then reads the value back from memory and
# from the file once things settle. On the old asynchronous writes the edit is lost at
# every delay inside the window (measured on dev: 50 to 64 ms after Config's first load,
# 50 to 66 ms after a first edit, 100 to 118 ms for Persistent; the window is the flight
# of a write, which is the fsync, so it moves with the disk).
#   config-startup  an edit N ms after Config's first load, around its startup write
#   config-second   a second edit N ms after a first one, around the first one's write
#   persist-second  the same for Persistent, whose timers wait 100 ms
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in kwin_wayland qs dbus-run-session jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/config/koompi" "$WORK/state/quickshell/user" "$WORK/cache" "$WORK/data" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/state/quickshell/user/first_run.txt"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/inflight_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs.modules.common

ShellRoot {
    id: probe
    readonly property string mode: Quickshell.env("PROBE_MODE")
    readonly property int delay: parseInt(Quickshell.env("PROBE_DELAY_MS"))
    property bool armed: false

    function later(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", probe);
        t.interval = ms;
        t.triggered.connect(() => { t.destroy(); fn(); });
        t.start();
    }

    function finish() {
        let kept = false;
        if (probe.mode === "config-startup")
            kept = Config.options.appearance.reduceMotion === true;
        else if (probe.mode === "config-second")
            kept = Config.options.appearance.reduceMotion === true && Config.options.appearance.fonts.baseSize === 21;
        else
            kept = Persistent.states.sidebar.pinned === true && Persistent.states.cheatsheet.tabIndex === 2;
        console.warn("RESULT memory=" + (kept ? "kept" : "lost"));
        Qt.quit();
    }

    Connections {
        target: probe.mode === "persist-second" ? null : Config

        function onReloaded() {
            if (probe.armed)
                return;
            probe.armed = true;
            if (probe.mode === "config-startup") {
                probe.later(probe.delay, () => {
                    Config.options.appearance.reduceMotion = true;
                    probe.later(600, probe.finish);
                });
            } else {
                probe.later(300, () => {
                    Config.options.appearance.reduceMotion = true;
                    probe.later(probe.delay, () => {
                        Config.options.appearance.fonts.baseSize = 21;
                        probe.later(600, probe.finish);
                    });
                });
            }
        }
    }

    Connections {
        target: probe.mode === "persist-second" ? Persistent : null

        function onReadyChanged() {
            if (probe.armed || !Persistent.ready)
                return;
            probe.armed = true;
            probe.later(300, () => {
                Persistent.states.sidebar.pinned = true;
                probe.later(probe.delay, () => {
                    Persistent.states.cheatsheet.tabIndex = 2;
                    probe.later(700, probe.finish);
                });
            });
        }
    }
}
QML

cat > "$WORK/drive.sh" <<'DRIVE'
#!/usr/bin/env bash
set -uo pipefail
cd "$WORK/shell" || exit 1
CFG="$WORK/config/koompi/config.json"
STATES="$WORK/state/quickshell/states.json"
OUT="$WORK/result.log"

sweep() { # mode, jq filter that holds on disk, delays...
    local mode=$1 filter=$2 file memory disk d
    shift 2
    [[ $mode == persist-second ]] && file=$STATES || file=$CFG
    for d in "$@"; do
        printf '{"windows":{"workspaceHelp":false}}\n' > "$CFG"
        rm -f "$STATES"
        PROBE_MODE=$mode PROBE_DELAY_MS=$d timeout 30 qs -p inflight_probe.qml > "$WORK/qs.log" 2>&1
        memory="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log" | grep -o 'RESULT memory=[a-z]*' | head -1)"
        if jq -e "$filter" "$file" > /dev/null 2>&1; then disk=kept; else disk=lost; fi
        if [[ $memory == "RESULT memory=kept" && $disk == kept ]]; then
            echo "PASS $mode: an edit $d ms in is kept, in memory and on disk" >> "$OUT"
        else
            echo "FAIL $mode: an edit $d ms in is not kept (${memory:-no result}, disk $disk)" >> "$OUT"
        fi
    done
}

sweep config-startup '.appearance.reduceMotion == true' 40 44 46 48 50 52 54 56 58 60 62 64 66 70
sweep config-second '.appearance.reduceMotion == true and .appearance.fonts.baseSize == 21' 44 46 48 50 52 54 56 58 60 62 64 66
sweep persist-second '.sidebar.pinned == true and .cheatsheet.tabIndex == 2' 94 97 100 103 106 109 112 115 118
echo DONE >> "$OUT"
DRIVE
chmod +x "$WORK/drive.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
    XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$WORK/rt" \
    timeout 280 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/drive.sh" > "$WORK/kwin.log" 2>&1

[[ -f "$WORK/result.log" ]] && cat "$WORK/result.log"
if ! grep -qx DONE "$WORK/result.log" 2> /dev/null || grep -q '^FAIL' "$WORK/result.log" 2> /dev/null; then
    fail "an edit made around a Config or Persistent write was lost"
fi
(( failed )) && exit 1
echo "ok   config and persistent: an edit made around a write is kept, in memory and on disk, at every delay swept"
