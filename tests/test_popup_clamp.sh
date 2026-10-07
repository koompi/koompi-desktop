#!/usr/bin/env bash
# J01: a bar popup stays on its screen and centres on its widget, on both bars.
# Three real StyledPopups hang off targets at the start, middle and end of a
# 1280x400 KWin virtual screen, once with bar.vertical off (the popup's x is
# measured) and once on (its y). The clock popup on the real bar is measured
# in test_bar_keys.sh; no widget on a headless seat opens a vertical popup.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

if ! command -v qs >/dev/null 2>&1 || ! command -v kwin_wayland >/dev/null 2>&1; then
    echo "skip: needs qs and kwin_wayland for the headless popup measurement"
    exit 0
fi

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/clamp_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs.modules.common
import qs.modules.koompi.bar

ShellRoot {
    id: probe
    readonly property bool vertical: Quickshell.env("PROBE_VERTICAL") === "1"
    property int ticks: 0

    PanelWindow {
        id: host
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        Repeater {
            id: slots
            model: probe.vertical ? [10, 190, 385] : [10, 625, 1245]
            delegate: Item {
                id: slot
                required property int modelData
                x: probe.vertical ? 300 : modelData
                y: probe.vertical ? modelData : 100
                width: 30
                height: 30
                property alias popup: pop

                StyledPopup {
                    id: pop
                    clickToShow: true
                    pinned: true
                    hoverTarget: slot
                    Rectangle { implicitWidth: 120; implicitHeight: 160; color: "steelblue" }
                }
            }
        }
    }

    function span(popupWindow) {
        const children = popupWindow.contentItem.children;
        const bg = children[children.length - 1];
        const at = bg.mapToItem(null, 0, 0);
        const start = probe.vertical ? popupWindow.margins.top + at.y : popupWindow.margins.left + at.x;
        return { start: start, end: start + (probe.vertical ? bg.height : bg.width) };
    }

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
    }

    // config.json loads late; before it does a popup is a horizontal-bar popup
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks > 60) {
                console.log("FAIL popups never opened for vertical=" + probe.vertical);
                Qt.quit();
                return;
            }
            const items = [];
            for (let i = 0; i < slots.count; i++) items.push(slots.itemAt(i));
            if (!Config.ready || Config.options.bar.vertical !== probe.vertical || items.some(s => !s?.popup.item)) return;
            if (probe.ticks < 12) return;

            const axis = probe.vertical ? "y" : "x";
            const screenExtent = probe.vertical ? host.screen.height : host.screen.width;
            for (const s of items) {
                const got = probe.span(s.popup.item);
                probe.verdict(got.start >= 0 && got.end <= screenExtent,
                    (probe.vertical ? "vertical" : "horizontal") + " bar, target at " + axis + " " + (probe.vertical ? s.y : s.x)
                    + ": popup inside the screen, " + axis + " " + got.start + ".." + got.end + " of " + screenExtent);
            }
            const mid = items[1];
            const got = probe.span(mid.popup.item);
            const at = mid.mapToItem(null, 0, 0);
            const centre = probe.vertical ? at.y + mid.height / 2 : at.x + mid.width / 2;
            probe.verdict(Math.abs((got.start + got.end) / 2 - centre) <= 1,
                "middle popup centred on its target: popup centre " + (got.start + got.end) / 2 + ", target centre " + centre);
            console.log("PROBE DONE");
            Qt.quit();
        }
    }
}
QML

# vertical: 1 or 0; leaves the probe's PASS/FAIL lines on stdout
run_case() {
    local vertical="$1" dir="$WORK/case-$1" out
    mkdir -p "$dir/xdg/config/koompi" "$dir/xdg/state" "$dir/xdg/cache" "$dir/xdg/data" "$dir/home" "$dir/rt"
    chmod 700 "$dir/rt"
    if [[ "$vertical" == 1 ]]; then
        printf '{"bar": {"vertical": true}}\n' > "$dir/xdg/config/koompi/config.json"
    else
        printf '{"bar": {"vertical": false}}\n' > "$dir/xdg/config/koompi/config.json"
    fi
    cat > "$dir/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
unset HYPRLAND_INSTANCE_SIGNATURE
qs -p "$WORK/shell/clamp_probe.qml" > "$dir/qs.log" 2>&1
SH
    chmod +x "$dir/inner.sh"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland PROBE_VERTICAL="$vertical" \
        HOME="$dir/home" XDG_RUNTIME_DIR="$dir/rt" XDG_DATA_HOME="$dir/xdg/data" \
        XDG_CONFIG_HOME="$dir/xdg/config" XDG_STATE_HOME="$dir/xdg/state" XDG_CACHE_HOME="$dir/xdg/cache" \
        timeout 90 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 400 --no-lockscreen --no-global-shortcuts \
            --exit-with-session "$dir/inner.sh" > "$dir/kwin.log" 2>&1
    out="$(sed 's/\x1b\[[0-9;]*m//g' "$dir/qs.log")"
    grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
    if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
        echo "--- probe output, vertical=$vertical ---" >&2
        grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
        fail "popup measurement did not pass with bar.vertical=$vertical"
    fi
}

run_case 0
run_case 1
(( failed )) || echo "ok   popups: start, middle and end targets inside the screen and the middle one centred, on both bars"
exit $failed
