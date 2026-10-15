#!/usr/bin/env bash
# The bar shows the workspaces in use. With windows on desks 1, 2 and 5 the real
# Workspaces.qml draws 1, 2, 5 and an empty "new desk" 3, not a row of ten;
# focusing desk 8 adds 8; closing 5's window drops 5 once focus is elsewhere.
# Desk numbers never move. A desk with a window shows the app's icon, an empty
# one its number. The probe reads the widget's own slot delegates.
#
# Live: Hyprland nested in a headless KWin on a private bus with a minimal Lua
# config; windows are moved with the Lua hl.dsp.window.move. Nothing here reaches
# the running session. koompi-shelld is a PATH shim that feeds HyprlandData.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'property bool dynamic: true' "$SHELL_ROOT/modules/common/Config.qml" || fail "bar.workspaces.dynamic is not on by default"
grep -q 'bar.workspaces.dynamic' "$SHELL_ROOT/modules/settings/BarConfig.qml" || fail "Settings has no switch for bar.workspaces.dynamic"
echo "ok   source: bar.workspaces.dynamic defaults on and has a Settings switch"

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static check only"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$(mktemp -d /tmp/hr.XXXXXX)"
trap 'rm -rf "$WORK" "$RUN"' EXIT
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$WORK/bin" "$WORK/shell"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
printf '{"windows": {"workspaceHelp": false}}\n' > "$HOME_DIR/.config/koompi/config.json"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

cat > "$WORK/bin/koompi-shelld" <<'SH'
#!/usr/bin/env bash
printf '{"type":"hello","protocol":1}\n'
while sleep 0.3; do
    printf '{"type":"state","service":"hyprland","state":{"windows":%s}}\n' "$(hyprctl clients -j | jq -c .)" || exit 0
done
SH
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/slots_probe.qml" <<'QML'
import qs.modules.koompi.bar
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    FloatingWindow {
        title: "slots-host"
        visible: true
        implicitWidth: 600
        implicitHeight: 60
        Workspaces {
            id: bar
            anchors.centerIn: parent
        }
    }
    FloatingWindow {
        id: two
        title: "slots-two"
        visible: true
    }
    FloatingWindow {
        id: five
        title: "slots-five"
        visible: true
    }

    IpcHandler {
        target: "probe"

        function slots(): string {
            return bar.drawnIds().join(",") + "|new=" + bar.newSlotId;
        }

        function faces(): string {
            return bar.drawnIds(true).join(",");
        }

        function closeFive(): string {
            five.visible = false;
            return "closed";
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || exit 1

cd "$WORK/shell"
qs -p slots_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p slots_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done

slots() { qs -p slots_probe.qml ipc call probe slots 2> /dev/null; }
faces() { qs -p slots_probe.qml ipc call probe faces 2> /dev/null; }
# poll until the widget reads $1 through $3 (slots by default), then record what it read last
await() {
    local want=$1 got=""
    for _ in $(seq 1 40); do
        got=$("${3:-slots}")
        [[ $got == "$want" ]] && break
        sleep 0.5
    done
    echo "$2 $got" >> "$WORK/readings"
}
move() {
    local addr
    for _ in $(seq 1 40); do
        addr=$(hyprctl clients -j | jq -r --arg t "$1" '.[] | select(.title == $t) | .address' | head -1)
        [[ -n $addr ]] && break
        sleep 0.5
    done
    hyprctl dispatch "hl.dsp.window.move({ workspace = $2, follow = false, window = \"address:$addr\" })" > /dev/null 2>&1
}

move slots-two 2
move slots-five 5
await "1,2,3,5|new=3" base
await "1:icon,2:icon,3:number,5:icon" basefaces faces
hyprctl dispatch 'hl.dsp.focus({ workspace = 8 })' > /dev/null 2>&1
await "1,2,3,5,8|new=3" focus8
await "1:icon,2:icon,3:number,5:icon,8:number" focus8faces faces
qs -p slots_probe.qml ipc call probe closeFive > /dev/null 2>&1
await "1,2,3,8|new=3" closed5

cp "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" "$WORK/hyprland-run.log" 2> /dev/null
kill "$qs_pid" 2> /dev/null
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" REPO_ROOT="$REPO_ROOT" \
    HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 180 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }

[[ "$(reading base)" == "1,2,3,5|new=3" ]] || { dump; fail "desks 1, 2 and 5 in use should draw 1,2,3,5 with 3 new, the bar drew '$(reading base)'"; }
echo "ok   probe: windows on 1, 2 and 5 draw 1, 2, 5 and the empty new desk 3"
[[ "$(reading basefaces)" == "1:icon,2:icon,3:number,5:icon" ]] || { dump; fail "desks with windows should show app icons and the new desk its number, the bar drew '$(reading basefaces)'"; }
echo "ok   probe: desks 1, 2 and 5 show their app's icon, the new desk 3 its number"
[[ "$(reading focus8)" == "1,2,3,5,8|new=3" ]] || { dump; fail "focusing desk 8 should add 8, the bar drew '$(reading focus8)'"; }
echo "ok   probe: focusing desk 8 adds 8 and nothing is renumbered"
[[ "$(reading focus8faces)" == "1:icon,2:icon,3:number,5:icon,8:number" ]] || { dump; fail "the empty active desk 8 should show its number, the bar drew '$(reading focus8faces)'"; }
echo "ok   probe: the empty active desk 8 shows its number"
[[ "$(reading closed5)" == "1,2,3,8|new=3" ]] || { dump; fail "closing 5's window should drop 5, the bar drew '$(reading closed5)'"; }
echo "ok   probe: closing the window on desk 5 drops 5 once focus is on 8"
