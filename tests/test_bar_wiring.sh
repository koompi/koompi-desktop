#!/usr/bin/env bash
# J22: the bar's right end is in one fixed order and wired to the two panels.
# Left to right: mode lights, update glyph, sliders glyph, clock. The clock and the
# glyph both toggle the one right panel, and there is no
# panel button. Headless: KWin's virtual backend hosts a nested shell; the probe
# forces the modes on, clicks the real buttons (QML click()) and reads the item
# tree. BAR_SHOT=<path> keeps the bar image with every mode lit.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
BAR="$SHELL_ROOT/modules/koompi/bar"
VBAR="$SHELL_ROOT/modules/koompi/verticalBar"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

# --- source ------------------------------------------------------------------
if grep -rn 'rightSidebarButton' "$SHELL_ROOT" --include='*.qml' >&2; then
    fail "something still names rightSidebarButton, the panel button this job removes"
fi
grep -q 'sidebarRightOpen = !GlobalStates.sidebarRightOpen' "$BAR/BarContent.qml" || fail "BarContent.qml: the clock does not toggle sidebarRightOpen"
grep -q 'controlCenterOpen' "$BAR/BarContent.qml" "$VBAR/VerticalBarContent.qml" && fail "a bar button still names controlCenterOpen; there is one panel"
grep -q 'sidebarRightOpen = !GlobalStates.sidebarRightOpen' "$VBAR/VerticalBarContent.qml" || fail "VerticalBarContent.qml: the clock does not toggle sidebarRightOpen"
for f in "$BAR/ClockWidgetPopup.qml"; do
    grep -qi 'uptime' "$f" && fail "$(basename "$f") still shows uptime; it lives in About"
done
grep -q 'DateTime.uptime' "$SHELL_ROOT/modules/settings/About.qml" || fail "About.qml has no uptime row"
for f in "$BAR"/*.qml "$VBAR"/*.qml; do
    n="$(wc -l < "$f")"
    (( n <= 400 )) || fail "${f#"$REPO_ROOT"/} is $n lines, cap is 400"
done
echo "ok   source: no rightSidebarButton, clock and glyph toggle their panels in both bars, uptime in About only"

# --- headless ----------------------------------------------------------------
if ! command -v qs >/dev/null 2>&1 || ! command -v kwin_wayland >/dev/null 2>&1; then
    echo "skip: needs qs and kwin_wayland for the headless bar probe"
    exit $failed
fi

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/bin" "$WORK/out" "$WORK/home" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
ln -s "$(command -v sleep)" "$WORK/bin/wf-recorder"
chmod +x "$WORK/bin"/koompi-shelld

cat > "$WORK/shell/wiring_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs
import qs.services
import qs.modules.koompi.bar

ShellRoot {
    id: probe
    property string out: Quickshell.env("PROBE_OUT")
    property int ticks: 0
    property int stage: 0
    property int mark: 0

    Bar { id: bar }
    BatteryIndicator { id: battery }

    function findNamed(obj, name) {
        if (obj.objectName === name) return obj;
        const list = obj.data;
        for (let i = 0; list && i < list.length; i++) {
            const found = probe.findNamed(list[i], name);
            if (found) return found;
        }
        return null;
    }

    function verdict(ok, text) { console.log((ok ? "PASS " : "FAIL ") + text); }

    function span(win, name) {
        const item = probe.findNamed(win.contentItem, name);
        if (!item) return null;
        const p = item.mapToItem(null, 0, 0);
        return { item: item, left: p.x, right: p.x + item.width, shown: item.visible && item.width > 0 };
    }

    function checkOrder(win) {
        const names = ["modeRecording", "modeKeepAwake", "modeNightLight", "modeDoNotDisturb", "modeDictation",
                       "updateBadge", "controlCenterButton", "clockButton"];
        let prev = null;
        let ok = true;
        let line = "";
        for (const name of names) {
            const s = probe.span(win, name);
            if (!s || !s.shown) { probe.verdict(false, name + " is not on the bar: found=" + !!s + (s ? " visible=" + s.item.visible + " w=" + s.item.width : "")); ok = false; continue; }
            line += name + " " + Math.round(s.left) + ".." + Math.round(s.right) + "  ";
            if (prev && s.left < prev.right - 0.5) { probe.verdict(false, name + " starts at " + s.left + " before " + prev.name + " ends at " + prev.right); ok = false; }
            prev = { name: name, right: s.right };
        }
        probe.verdict(ok, "order and no overlap, left to right: " + line);
        probe.verdict(probe.findNamed(win.contentItem, "rightSidebarButton") === null, "no panel button on the bar");
        const cc = probe.span(win, "controlCenterButton");
        const clock = probe.span(win, "clockButton");
        probe.verdict(cc.item.width >= 24 && cc.item.height >= 24 && clock.item.width >= 24 && clock.item.height >= 24,
            "glyph " + cc.item.width + "x" + cc.item.height + " and clock " + clock.item.width + "x" + clock.item.height + " are separate hit areas of 24px or more");
    }

    function checkClicks(win) {
        const clock = probe.findNamed(win.contentItem, "clockButton");
        const cc = probe.findNamed(win.contentItem, "controlCenterButton");
        GlobalStates.sidebarRightOpen = false;
        clock.click();
        probe.verdict(GlobalStates.sidebarRightOpen, "clock click opens the one panel");
        probe.verdict(clock.toggled && cc.toggled, "clock and glyph are both drawn toggled while it is open");
        clock.click();
        probe.verdict(!GlobalStates.sidebarRightOpen && !clock.toggled && !cc.toggled, "a second clock click closes it");
        cc.click();
        probe.verdict(GlobalStates.sidebarRightOpen && clock.toggled && cc.toggled, "glyph click opens the same panel");
        cc.click();
        probe.verdict(!GlobalStates.sidebarRightOpen, "a second glyph click closes it");

        // the Wi-Fi glyph asks the panel for its network list; the panel itself is not in this probe
        const net = probe.findNamed(win.contentItem, "networkIndicator");
        let asked = "";
        const take = name => asked = name;
        GlobalStates.sidebarRightModuleRequested.connect(take);
        const area = net ? Array.from(net.data).find(o => o.cursorShape === Qt.PointingHandCursor) : null;
        if (area) area.clicked(null);
        GlobalStates.sidebarRightModuleRequested.disconnect(take);
        probe.verdict(asked === "wifi", "a Wi-Fi glyph click asks for the network list: '" + asked + "'");
    }

    function checkDot(win) {
        const dot = probe.findNamed(win.contentItem, "unreadDot");
        Notifications.silent = false;
        Notifications.unread = 0;
        probe.verdict(dot && !dot.visible, "no dot with nothing unread");
        Notifications.unread = 3;
        probe.verdict(dot && dot.visible && dot.width <= 8, "unread notifications show a small dot, " + (dot ? dot.width : -1) + "px, no count");
        Notifications.unread = 0;
        Notifications.silent = true;
    }

    function checkBattery() {
        const text = probe.findNamed(battery, "batteryPercent");
        probe.verdict(text && /^[0-9]+%$/.test(text.text), "battery shows a percent beside its glyph: '" + (text ? text.text : "none") + "'");
    }

    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks > 120) {
                console.log("FAIL probe timed out in stage " + probe.stage);
                Qt.quit();
                return;
            }
            const win = bar.focusedBarWindow();
            if (!win) return;
            if (probe.stage === 0) {
                Idle.inhibit = true;
                Hyprsunset.temperatureActive = true;
                Notifications.silent = true;
                probe.stage = 1;
                probe.mark = probe.ticks;
            } else if (probe.stage === 1) {
                if (probe.ticks - probe.mark < 8) return;
                probe.stage = 99;
                probe.checkOrder(win);
                probe.checkBattery();
                probe.checkClicks(win);
                probe.checkDot(win);
                const item = win.contentItem.children[0];
                item.grabToImage(result => {
                    console.log((result.saveToFile(probe.out + "/bar.png") ? "PASS " : "FAIL ") + "saved bar.png");
                    console.log("PROBE DONE");
                    Qt.quit();
                });
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
unset HYPRLAND_INSTANCE_SIGNATURE
echo \$\$ > "$WORK/rt/kiri-voice.pid"
wf-recorder 120 &
rec=\$!
probe="$WORK/shell/wiring_probe.qml"
qs -p "\$probe" > "$WORK/qs.log" 2>&1 &
wait \$!
kill "\$rec" 2>/dev/null
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" KOOMPI_UPDATES_FORCE=3 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" PROBE_OUT="$WORK/out" \
    QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" XDG_DATA_HOME="$WORK/xdg/data" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 90 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1600 --height 400 --no-lockscreen --no-global-shortcuts \
        --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    fail "headless wiring probe did not pass"
fi
if loops="$(grep -E 'Binding loop|TypeError|ReferenceError' <<< "$out")"; then
    echo "$loops" >&2
    fail "the bar logged a binding loop or a script error"
fi
[[ -n "${BAR_SHOT:-}" && -s "$WORK/out/bar.png" ]] && cp "$WORK/out/bar.png" "$BAR_SHOT"
(( failed )) || echo "ok   headless: modes, update glyph, Control Center glyph, clock in order; clicks wired; dot, no count; battery percent"
exit $failed
