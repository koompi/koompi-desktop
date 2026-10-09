#!/usr/bin/env bash
# a pinned or saved app is the same app as the window it opens, whichever class the window reports
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in qs kwin_wayland dbus-run-session python3; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nothing probed"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
# unix socket paths cap at 108 bytes
RUNTIME="$(mktemp -d /tmp/aid.XXXXXX)" || exit 1
chmod 700 "$RUNTIME"
fake_pid=""
cleanup() {
    [[ -z $fake_pid ]] || kill "$fake_pid" 2> /dev/null
    rm -rf "$WORK" "$RUNTIME"
}
trap cleanup EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/apps/applications" "$WORK/xdg/config/koompi" \
    "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

# StartupWMClass is what maps dolphin, okular and telegram; kdialog and kdeconnect-app have none
desktop_entry() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s' "$1" "$2" "${3:+$3$'\n'}" > "$WORK/apps/applications/$1.desktop"; }
desktop_entry org.kde.dolphin 'fx-dolphin %u' 'StartupWMClass=dolphin'
desktop_entry org.kde.okular 'fx-okular %U' 'StartupWMClass=okular'
desktop_entry org.kde.kdialog 'fx-kdialog' 'NoDisplay=true'
desktop_entry org.kde.kdeconnect.app 'fx-kdeconnect-app'
desktop_entry org.telegram.desktop 'fx-telegram -- %U' 'StartupWMClass=TelegramDesktop'
desktop_entry kitty 'fx-kitty'

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/launch.log"\n' "$WORK" > "$WORK/bin/koompi-launch"
printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$(basename -- "$0")" "$*" >> "%s/direct.log"\n' "$WORK" > "$WORK/bin/fx-app"
chmod +x "$WORK/bin"/*
for app in fx-dolphin fx-okular fx-kdialog fx-kdeconnect-app fx-telegram fx-kitty; do
    ln -s fx-app "$WORK/bin/$app"
done

printf '%s\n' '{"session": {"restore": true}}' > "$WORK/xdg/config/koompi/config.json"
cat > "$WORK/xdg/state/quickshell/user/session.json" <<'JSON'
{"version": 1, "workspace": 4, "windows": [
    {"class": "dolphin", "workspace": 2},
    {"class": "dolphin", "workspace": 9},
    {"class": "org.kde.okular", "workspace": 7},
    {"class": "org.kde.kdialog", "workspace": 3},
    {"class": "TelegramDesktop", "workspace": 4},
    {"class": "org.kde.kdeconnect.app", "workspace": 5},
    {"class": "kitty", "workspace": 6},
    {"class": "ghost-app", "workspace": 8}
]}
JSON

# stands in for hyprland's request socket; every dispatch lands in hypr.log
cat > "$WORK/fake_hypr.py" <<'PY'
import os
import socket
import sys
import threading

runtime, signature, log = sys.argv[1:4]
folder = os.path.join(runtime, "hypr", signature)
os.makedirs(folder, mode=0o700)


def listen(name):
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(os.path.join(folder, name))
    server.listen(8)
    return server


requests = listen(".socket.sock")
events = listen(".socket2.sock")
held = []


def hold_events():
    while True:
        held.append(events.accept()[0])


def answer(conn):
    with conn:
        data = conn.recv(65536).decode("utf-8", "replace")
        with open(log, "a") as out:
            out.write(data + "\n")
        conn.sendall(b"[]" if data.startswith("j/") else b"ok")


threading.Thread(target=hold_events, daemon=True).start()
print("ready", flush=True)
while True:
    conn, _ = requests.accept()
    threading.Thread(target=answer, args=(conn,), daemon=True).start()
PY

cat > "$WORK/shell/identity_probe.qml" <<'QML'
import qs.services
import qs.modules.common
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    property int ticks: 0
    property int stage: 0
    property int settled: 0

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  got=" + JSON.stringify(got) + " want=" + JSON.stringify(want)));
        if (!ok)
            probe.failures++;
    }

    function run(name, step) {
        try {
            step();
        } catch (e) {
            probe.check(`${name}: ran to the end`, String(e), "no error");
        }
    }

    function fake(appClass) {
        return {
            appId: appClass
        };
    }

    function shape(entries) {
        return entries.filter(e => e.appId !== "SEPARATOR").map(e => [e.appId, e.pinned, e.toplevels.map(t => t.appId)]);
    }

    // x11 class, wayland class
    readonly property var pairs: [["dolphin", "org.kde.dolphin"], ["okular", "org.kde.okular"], ["kdialog", "org.kde.kdialog"], ["kdeconnect.app", "org.kde.kdeconnect.app"], ["TelegramDesktop", "org.telegram.desktop"]]

    function dock() {
        for (const [x11, wayland] of probe.pairs) {
            for (const [pinned, running] of [[wayland, x11], [x11, wayland]])
                probe.check(`dock: ${pinned} pinned and ${running} running are one entry`, probe.shape(TaskbarApps.entries([pinned], [probe.fake(running)], [])), [[pinned.toLowerCase(), true, [running]]]);
        }
        probe.check("dock: an app with one class is still one entry", probe.shape(TaskbarApps.entries(["kitty"], [probe.fake("kitty")], [])), [["kitty", true, ["kitty"]]]);
        probe.check("dock: two apps stay two entries", probe.shape(TaskbarApps.entries(["kitty"], [probe.fake("dolphin")], [])), [["kitty", true, []], ["dolphin", false, ["dolphin"]]]);
        probe.check("dock: an app with no entry keeps its own class", probe.shape(TaskbarApps.entries([], [probe.fake("ghost-app")], [])), [["ghost-app", false, ["ghost-app"]]]);
        probe.check("dock: one app on both platforms is one entry with both windows", probe.shape(TaskbarApps.entries([], [probe.fake("dolphin"), probe.fake("org.kde.dolphin")], [])), [["dolphin", false, ["dolphin", "org.kde.dolphin"]]]);
        probe.check("dock: the separator stays between pinned and running", TaskbarApps.entries(["kitty"], [probe.fake("dolphin")], []).map(e => e.appId), ["kitty", "SEPARATOR", "dolphin"]);
    }

    // what it checks, class the new window reports, workspace it opens on, saved windows still waiting
    readonly property var claims: [
        ["org.kde.dolphin claims the first saved dolphin", "org.kde.dolphin", "1", 6],
        ["a second window claims the next saved dolphin", "dolphin", "1", 5],
        ["a third dolphin window claims nothing", "dolphin", "1", 5],
        ["okular claims the saved org.kde.okular", "okular", "1", 4],
        ["kdialog claims the saved org.kde.kdialog", "kdialog", "1", 3],
        ["org.telegram.desktop claims the saved TelegramDesktop", "org.telegram.desktop", "1", 2],
        ["kdeconnect.app claims the saved org.kde.kdeconnect.app", "kdeconnect.app", "5", 1],
        ["a window of another app claims nothing", "firefox", "1", 1],
        ["kitty claims the saved kitty", "kitty", "6", 0]
    ]

    function restore() {
        probe.check("restore: every saved window with a desktop entry waits to be claimed", SessionRestore.pending.length, 7);
        let n = 0;
        for (const [what, windowClass, openedOn, left] of probe.claims) {
            n++;
            SessionRestore.claim("a" + n, windowClass, openedOn);
            probe.check(`restore: ${what}`, SessionRestore.pending.length, left);
        }
    }

    function pins() {
        Config.options.dock.pinnedApps = ["org.kde.dolphin", "dolphin", "kitty"];
        probe.check("pin: one app pinned under both classes is one dock entry", probe.shape(TaskbarApps.apps), [["org.kde.dolphin", true, []], ["kitty", true, []]]);
        Config.options.dock.pinnedApps = ["org.kde.dolphin"];
        probe.check("pin: a pin made under the other class is still the pin", TaskbarApps.isPinned("dolphin"), true);
        probe.check("pin: another app is not pinned", TaskbarApps.isPinned("kitty"), false);
        TaskbarApps.togglePin("dolphin");
        probe.check("pin: unpinning by the other class removes the pin", Config.options.dock.pinnedApps, []);
        TaskbarApps.togglePin("TelegramDesktop");
        probe.check("pin: pinning by one class pins the app", TaskbarApps.isPinned("org.telegram.desktop"), true);
        TaskbarApps.togglePin("org.telegram.desktop");
        probe.check("pin: unpinning by the other class leaves nothing", Config.options.dock.pinnedApps, []);
    }

    Component.onCompleted: SessionRestore.load()

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.ticks++;
            if (probe.stage === 0) {
                if (Config.ready && DesktopEntries.applications.values.length > 0) {
                    probe.run("dock", probe.dock);
                    probe.stage = 1;
                } else if (probe.ticks > 100) {
                    probe.check("config and desktop entries loaded", [Config.ready, DesktopEntries.applications.values.length], "in time");
                    probe.stage = 9;
                }
            } else if (probe.stage === 1) {
                if (SessionRestore.armed) {
                    probe.run("restore", probe.restore);
                    probe.run("pin", probe.pins);
                    probe.stage = 2;
                } else if (probe.ticks > 200) {
                    probe.check("session restore armed", SessionRestore.armed, true);
                    probe.stage = 9;
                }
            } else if (probe.stage === 2) {
                // dispatches leave on a socket
                if (++probe.settled >= 5)
                    probe.stage = 9;
            } else if (probe.stage === 9) {
                console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
                running = false;
                Qt.quit();
            }
        }
    }
}
QML

python3 -I "$WORK/fake_hypr.py" "$RUNTIME" fakehypr "$WORK/hypr.log" > "$WORK/fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 1 50); do grep -q ready "$WORK/fake.out" 2> /dev/null && break; sleep 0.1; done
grep -q ready "$WORK/fake.out" 2> /dev/null || { cat "$WORK/fake.out" >&2; fail "the stand-in for Hyprland's socket did not start"; exit 1; }

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
export HYPRLAND_INSTANCE_SIGNATURE=fakehypr
cd "$WORK/shell" || exit 1
exec timeout 60 qs -p "$WORK/shell/identity_probe.qml" > "$WORK/probe.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

# wayland, not offscreen: Idle.qml in qs.services holds a PanelWindow, which has no offscreen backend
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY HOME="$WORK/home" XDG_RUNTIME_DIR="$RUNTIME" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    XDG_DATA_HOME="$WORK/xdg/data" XDG_DATA_DIRS="$WORK/apps" PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" \
    QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

for _ in $(seq 1 30); do
    seen="$(grep -cF 'hl.dsp.focus' "$WORK/hypr.log" 2> /dev/null)"
    (( ${seen:-0} >= 2 )) && break
    sleep 0.1
done

plain="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/probe.log" 2> /dev/null)"
grep -E '^ DEBUG qml: FAIL' <<< "$plain" | sed 's/^ DEBUG qml: /     /' >&2
if ! grep -q '^ DEBUG qml: PROBE OK' <<< "$plain"; then
    grep -q '^ DEBUG qml: PROBE FAILED' <<< "$plain" || { grep -vE 'qmlscanner|^\s*$' <<< "$plain" | tail -20 >&2; fail "the probe never finished"; }
    fail "the probe found windows and saved apps matched by class instead of by app"
fi

launched="$(sort "$WORK/launch.log" 2> /dev/null)"
want_launches='--registered --id kitty -- fx-kitty
--registered --id org.kde.dolphin -- fx-dolphin
--registered --id org.kde.dolphin -- fx-dolphin
--registered --id org.kde.kdeconnect.app -- fx-kdeconnect-app
--registered --id org.kde.kdialog -- fx-kdialog
--registered --id org.kde.okular -- fx-okular
--registered --id org.telegram.desktop -- fx-telegram --'
[[ "$launched" == "$want_launches" ]] || fail "restore did not start every saved app through koompi-launch (- wanted, + saw):
$(diff <(printf '%s\n' "$want_launches") <(printf '%s\n' "$launched"))"
[[ ! -s "$WORK/direct.log" ]] || fail "restore started an app without koompi-launch, so it is outside app.slice and on the wrong platform:
$(cat "$WORK/direct.log")"

moved="$(grep -F 'hl.dsp.window.move' "$WORK/hypr.log" 2> /dev/null | sort)"
want_moves='dispatch hl.dsp.window.move({ workspace = 2, follow = false, window = "address:0xa1" })
dispatch hl.dsp.window.move({ workspace = 3, follow = false, window = "address:0xa5" })
dispatch hl.dsp.window.move({ workspace = 4, follow = false, window = "address:0xa6" })
dispatch hl.dsp.window.move({ workspace = 7, follow = false, window = "address:0xa4" })
dispatch hl.dsp.window.move({ workspace = 9, follow = false, window = "address:0xa2" })'
[[ "$moved" == "$want_moves" ]] || fail "claimed windows did not move to their saved workspaces, once each (- wanted, + saw):
$(diff <(printf '%s\n' "$want_moves") <(printf '%s\n' "$moved"))"
focuses="$(grep -cF 'hl.dsp.focus({ workspace = 4 })' "$WORK/hypr.log" 2> /dev/null)"
[[ "${focuses:-0}" == 2 ]] || fail "the saved workspace was focused ${focuses:-0} times, want 2 (before the apps start and once every window is back)"

(( failed == 0 )) || exit 1
echo "ok   identity: a pinned or saved app is one app under either class, restore starts apps through koompi-launch and moves each claimed window once"
