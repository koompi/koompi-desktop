#!/usr/bin/env bash
# J03: the media panel with nothing playing says "Nothing playing" and, when a
# player was active earlier in the session, offers "Open <player>" in place of
# the MPRIS troubleshooting text. The probe runs the real MediaControls scope
# in a headless KWin on a private session bus beside a fixture MPRIS player: the player's identity
# and desktop entry must be remembered, survive the player quitting, and the
# remembered entry must launch through koompi-launch. koompi-launch and
# koompi-shelld are PATH shims, so nothing here reaches the live session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
MEDIA="$SHELL_ROOT/modules/koompi/mediaControls/MediaControls.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$MEDIA" ]] || fail "missing $MEDIA"
grep -q 'Translation.tr("Nothing playing")' "$MEDIA" || fail "the empty panel does not say Nothing playing"
grep -qE 'MPRIS support|duplicate player filtering|No active player' "$MEDIA" && fail "the MPRIS troubleshooting text is back in the empty panel"
# Assigning the loader's active breaks its binding to GlobalStates.mediaControlsOpen,
# and the shortcut and the bar button drive that.
grep -qE 'mediaControlsLoader\.active[[:space:]]*=[^=]' "$MEDIA" && fail "an IPC handler assigns mediaControlsLoader.active, which breaks the shortcut"
echo "ok   static: Nothing playing, no troubleshooting text, IPC drives GlobalStates"

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi
for tool in kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done
python3 -I -c 'import gi; gi.require_version("Gio", "2.0")' 2> /dev/null || { echo "skip: python3 gi not installed, static checks only"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/data/applications" "$WORK/state" "$WORK/config" "$WORK/cache" "$WORK/rt" "$WORK/home"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '[Desktop Entry]\nType=Application\nName=Alpha\nExec=alpha\n' > "$WORK/data/applications/alpha.desktop"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nprintf "%%s " "$@" >> "%s/launch.log"\nprintf "\\n" >> "%s/launch.log"\n' "$WORK" "$WORK" > "$WORK/bin/koompi-launch"
chmod +x "$WORK/bin"/*

cat > "$WORK/player.py" <<'PY'
import sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

lifetime = int(sys.argv[1])
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
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>"""
PROPS = {
    "CanQuit": GLib.Variant("b", True), "CanRaise": GLib.Variant("b", True),
    "HasTrackList": GLib.Variant("b", False),
    "Identity": GLib.Variant("s", "Alpha Player"), "DesktopEntry": GLib.Variant("s", "alpha"),
    "PlaybackStatus": GLib.Variant("s", "Playing"),
    "Metadata": GLib.Variant("a{sv}", {"xesam:title": GLib.Variant("s", "Fixture track")}),
    "CanControl": GLib.Variant("b", True),
}


def on_bus(conn, name):
    for iface in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
        conn.register_object("/org/mpris/MediaPlayer2", iface, None, lambda c, s, p, i, n: PROPS[n], None)


loop = GLib.MainLoop()
Gio.bus_own_name(Gio.BusType.SESSION, "org.mpris.MediaPlayer2.alpha", Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.timeout_add_seconds(lifetime, loop.quit)
loop.run()
PY

cat > "$WORK/shell/media_probe.qml" <<'QML'
import qs.services
import qs.modules.koompi.mediaControls
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    property int stage: 0
    property int waited: 0
    readonly property bool wantPlayer: Quickshell.env("PROBE_PLAYER") === "1"

    MediaControls { id: media }

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }

    function finish() {
        console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
        Qt.quit();
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.waited += interval;
            if (!probe.wantPlayer) {
                if (probe.waited < 3000)
                    return;
                probe.check("no player ever active: nothing remembered, no button", [media.lastPlayer, !!media.lastEntry], [null, false]);
                probe.finish();
                running = false;
            } else if (probe.stage === 0 && media.lastPlayer) {
                probe.check("the active player's identity and desktop entry are remembered", media.lastPlayer, {
                    name: "Alpha Player",
                    entry: "alpha"
                });
                probe.stage = 1;
            } else if (probe.stage === 1 && MprisController.players.length === 0) {
                probe.check("the player has quit and the panel is in its empty state", media.meaningfulPlayers.length, 0);
                probe.check("what it was is still known", [media.lastPlayer?.name, media.lastEntry?.name], ["Alpha Player", "Alpha"]);
                probe.stage = 2;
                probe.waited = 0;
                media.openLastPlayer();
            } else if (probe.stage === 2 && probe.waited >= 500) {
                probe.finish();
                running = false;
            } else if (probe.waited >= 15000) {
                probe.check("probe finished in time, stage", probe.stage, 2);
                probe.finish();
                running = false;
            }
        }
    }
}
QML

cat > "$WORK/run-probe.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
if [[ $PROBE_PLAYER == 1 ]]; then
    python3 -I "$WORK/player.py" 6 &
    sleep 1
fi
cd "$WORK/shell" || exit 1
timeout 60 qs -p media_probe.qml 2>&1
SH
chmod +x "$WORK/run-probe.sh"

run_probe() { # $1: 1 when a fixture player is on the bus
    rm -f "$WORK/launch.log"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY HOME="$WORK/home" WORK="$WORK" PROBE_PLAYER="$1" QT_QPA_PLATFORM=wayland \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
        XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$WORK/rt" \
        timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/run-probe.sh" > "$WORK/probe-$1.log" 2>&1
    cat -- "$WORK/probe-$1.log"
}

for run in 0 1; do
    out="$(run_probe "$run")"
    plain="$(sed 's/\x1b\[[0-9;]*m//g' <<< "$out")"
    if (( run == 1 )); then label="a player that quits"; else label="no player at all"; fi
    printf -- '--- %s ---\n' "$label"
    grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$plain" | sed 's/^ DEBUG qml: //' || true
    if ! grep -q "PROBE OK" <<< "$plain"; then
        echo "--- probe output ---" >&2
        grep -vE "qmlscanner|^\s*$" <<< "$plain" >&2
        fail "the media probe did not pass with $label"
    fi
    if (( run == 1 )); then
        grep -qxF -- '--registered --id alpha -- alpha ' "$WORK/launch.log" 2> /dev/null \
            || fail "Open <player> did not launch the remembered app through koompi-launch: $(cat "$WORK/launch.log" 2> /dev/null)"
    else
        [[ -e "$WORK/launch.log" ]] && fail "something launched with no player ever active"
    fi
done

echo "ok   media: the last active player is remembered from MPRIS, outlives the player, and launches through koompi-launch; with none there is no button"
