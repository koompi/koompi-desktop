#!/usr/bin/env bash
# J46: what MprisController shows after a browser's media ends. A stub
# plasma-browser-integration player on a private session bus plays for a few
# seconds, then does what the TODO says the real one does: goes Paused with
# Position pinned at the length ("ends"), drops its bus name ("drops"), or, the
# case the activePlayerStale workaround was written for, stays Playing with a
# frozen Position ("frozen"). The probe samples the real MprisController
# singleton in a headless KWin; koompi-shelld is a PATH shim.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done
python3 -I -c 'import gi; gi.require_version("Gio", "2.0")' 2> /dev/null || { echo "skip: python3 gi not installed"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/state" "$WORK/config" "$WORK/cache" "$WORK/data" "$WORK/rt" "$WORK/home"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/*

cat > "$WORK/player.py" <<'PY'
import sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

scenario = sys.argv[1]
NAME = "org.mpris.MediaPlayer2.plasma-browser-integration"
LENGTH_US = 10_000_000
XML = """<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="CanControl" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
  </interface>
</node>"""
state = {"status": "Playing", "pos": 5_000_000}
META = {
    "xesam:title": GLib.Variant("s", "Stub clip"), "xesam:artist": GLib.Variant("as", ["Stub"]),
    "mpris:length": GLib.Variant("x", LENGTH_US), "mpris:trackid": GLib.Variant("o", "/stub/1"),
}
conn_ref = {}


def prop(c, s, p, i, n):
    table = {
        "CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", False),
        "HasTrackList": GLib.Variant("b", False),
        "Identity": GLib.Variant("s", "Stub browser"), "DesktopEntry": GLib.Variant("s", "stub"),
        "PlaybackStatus": GLib.Variant("s", state["status"]),
        "Metadata": GLib.Variant("a{sv}", META),
        "Position": GLib.Variant("x", state["pos"]),
        "CanControl": GLib.Variant("b", True), "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True),
    }
    return table[n]


def on_bus(conn, name):
    conn_ref["c"] = conn
    for iface in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
        conn.register_object("/org/mpris/MediaPlayer2", iface, None, prop, None)


def announce(**changed):
    conn_ref["c"].emit_signal(
        None, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged",
        GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", changed, [])))


def end():
    if scenario == "ends":
        state["status"], state["pos"] = "Paused", LENGTH_US
        announce(PlaybackStatus=GLib.Variant("s", "Paused"))
    elif scenario == "drops":
        Gio.bus_unown_name(owner["id"])
    return False


loop = GLib.MainLoop()
owner = {"id": Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, on_bus, None, None)}
GLib.timeout_add_seconds(4, end)
GLib.timeout_add_seconds(16, loop.quit)
loop.run()
PY

cat > "$WORK/shell/mpris_probe.qml" <<'QML'
import qs.services
import Quickshell
import QtQuick

ShellRoot {
    property int t: 0
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            t++;
            const p = MprisController.activePlayer;
            console.log("SAMPLE t=" + t + " players=" + MprisController.players.length
                + " active=" + (p ? "yes" : "no") + " playing=" + MprisController.isPlaying
                + " media=" + MprisController.hasActiveMedia + " stale=" + MprisController.activePlayerStale);
            if (t >= 14) Qt.quit();
        }
    }
}
QML

cat > "$WORK/run-probe.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
python3 -I "$WORK/player.py" "$SCENARIO" &
cd "$WORK/shell" || exit 1
timeout 60 qs -p mpris_probe.qml 2>&1
SH
chmod +x "$WORK/run-probe.sh"

run_probe() { # $1: scenario
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY HOME="$WORK/home" WORK="$WORK" SCENARIO="$1" QT_QPA_PLATFORM=wayland \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
        XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$WORK/rt" \
        timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/run-probe.sh" > "$WORK/probe-$1.log" 2>&1
    sed 's/\x1b\[[0-9;]*m//g' "$WORK/probe-$1.log" | sed -n 's/^ DEBUG qml: SAMPLE //p'
}

at() { grep -E "^t=$2 " <<< "$1"; }

want() { # $1 scenario, $2 sample time, $3 expected fields
    local line; line="$(grep -E "^t=$2 " <<< "$samples")"
    [[ "$line" == *"$3"* ]] || fail "$1 at t=$2: wanted '$3', got '$line'"
}

for scenario in ends drops frozen; do
    samples="$(run_probe "$scenario")"
    [[ -n "$samples" ]] || fail "$scenario: the probe printed no samples"
    want "$scenario" 2 "players=1 active=yes playing=true"
    case "$scenario" in
        ends)   want ends 14 "players=1 active=yes playing=false media=true stale=false" ;;
        drops)  want drops 14 "players=0 active=no playing=false media=false" ;;
        frozen) want frozen 14 "playing=true media=false stale=true" ;;
    esac
    echo "ok   $scenario"
done
