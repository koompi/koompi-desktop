#!/usr/bin/env bash
# The plate is drawn once and reused: sixteen real AppIconPlates, animated for seconds, cost one plate texture and
# one mask texture per distinct full-bleed icon, and a second grid of the same icons costs nothing. Icons the
# theme does not draw stay unmasked, and a name that resolves to nothing gets the letter. A fake WhiteSur-green
# (the one theme with body metadata) and a fake hicolor stand in for the real ones, in a headless KWin.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
for tool in qs kwin_wayland dbus-run-session; do command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }; done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/config/koompi" "$WORK/state/quickshell/user" "$WORK/cache" "$WORK/data" "$WORK/rt" && chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"; done
echo greeted > "$WORK/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld" && chmod +x "$WORK/bin/koompi-shelld"

theme_index() { # name, inherits, directory...
    local name=$1 inherits=$2; shift 2
    printf '[Icon Theme]\nName=%s\nInherits=%s\nDirectories=%s\n' "$name" "$inherits" "$(IFS=,; echo "$*")"
    for dir in "$@"; do printf '\n[%s]\nSize=128\nMinSize=16\nMaxSize=512\nType=Scalable\n' "$dir"; done
}
svg() { printf '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><rect x="%s" y="%s" width="%s" height="%s" rx="24" fill="%s"/></svg>\n' "$1" "$1" "$2" "$2" "$3"; }
mkdir -p "$WORK/data/icons/WhiteSur-green/apps/scalable" "$WORK/data/icons/hicolor/scalable/apps"
theme_index WhiteSur-green hicolor apps/scalable > "$WORK/data/icons/WhiteSur-green/index.theme"
theme_index hicolor "" scalable/apps > "$WORK/data/icons/hicolor/index.theme"
for i in $(seq 0 11); do svg 8 112 "#3a7bd5" > "$WORK/data/icons/WhiteSur-green/apps/scalable/m$i.svg"; done
for i in 0 1 2; do svg 24 80 "#d57b3a" > "$WORK/data/icons/hicolor/scalable/apps/p$i.svg"; done

cat > "$WORK/shell/plate_probe.qml" <<'QML'
import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common.widgets

ShellRoot {
    id: probe
    property bool second: false
    readonly property var names: ["m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10", "m11", "p0", "p1", "p2", "nothing-like-this"]

    component Grid16: Grid {
        id: grid
        columns: 8
        spacing: 12
        property alias plates: rep
        Repeater {
            id: rep
            model: probe.names
            AppIconPlate {
                required property string modelData
                iconName: modelData
                label: modelData
                size: 64
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.6; duration: 300 }
                    NumberAnimation { from: 0.6; to: 1; duration: 300 }
                }
            }
        }
    }

    PanelWindow {
        implicitWidth: 760
        implicitHeight: 360
        color: "#202020"
        Grid16 { id: first; x: 12; y: 12 }
        Loader {
            active: probe.second
            x: 12
            y: 190
            sourceComponent: Grid16 {}
        }
    }

    IpcHandler {
        target: "probe"
        function second(on: bool): void { probe.second = on; }
        function states(): string {
            return probe.names.map((n, i) => `${n}:${first.plates.itemAt(i)?.masked}:${first.plates.itemAt(i)?.resolved}`).join(" ");
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell" || exit 1
qs -p plate_probe.qml > "$WORK/qs.log" 2>&1 &
call() { qs -p plate_probe.qml ipc call "$@" 2> /dev/null < /dev/null; }
for _ in $(seq 1 80); do call probe states > /dev/null && break; sleep 0.5; done
for _ in $(seq 1 40); do [[ $(call appIconPlates stats) == "base=1 mask=12 "* ]] && break; sleep 0.25; done
echo "READ states $(call probe states)"
echo "READ first $(call appIconPlates stats)"
sleep 3
echo "READ animated $(call appIconPlates stats)"
call probe second true; sleep 2
echo "READ second $(call appIconPlates stats)"
echo DONE
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" \
    XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" XDG_DATA_HOME="$WORK/data" XDG_DATA_DIRS="$WORK/data" \
    QS_ICON_THEME=WhiteSur-green KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^READ' "$WORK/kwin.log"
grep -qx DONE "$WORK/kwin.log" || { cat "$WORK/qs.log" >&2; fail "the probe did not finish"; }
reading() { grep "^READ $1 " "$WORK/kwin.log" | sed "s/^READ $1 //"; }
check() { [[ $2 == "$3" ]] || fail "$1: got '$2', want '$3'"; }

masked=""; for i in $(seq 0 11); do masked+="m$i:true:true "; done
check "full-bleed icons of the theme are masked, the rest are not, a missing name is unresolved" \
    "$(reading states)" "${masked}p0:false:true p1:false:true p2:false:true nothing-like-this:false:false"
check "sixteen plates cost one plate texture and one mask per distinct icon" "$(reading first)" "base=1 mask=12 cached=13"
check "three seconds of animation render nothing more" "$(reading animated)" "base=1 mask=12 cached=13"
check "a second grid of the same icons renders nothing more" "$(reading second)" "base=1 mask=12 cached=13"
echo "ok   icon plate: one plate texture, one mask per full-bleed icon, none per frame, unmasked and letter cases"
