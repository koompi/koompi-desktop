#!/usr/bin/env bash
# Settings > Displays gets a Refresh rate row per monitor. The real page runs in
# a headless KWin with two virtual outputs on a private bus and runtime dir,
# fed through its own path: hyprctl is a PATH shim that prints the founder's two
# monitors (names mapped onto the outputs KWin made, Virtual-1 for HDMI-A-1 and
# Virtual-0 for eDP-1), and koompi-displays is a shim under a private HOME that
# logs its arguments. The item tree is read back:
#   - the HDMI-A-1 monitor lists 74.97, 60 (twice) and 59.94 at 1920x1080 and 75 Hz
#     modes at smaller sizes: its row offers 74.97, 60 and 59.94, highest first,
#     labelled "74.97 Hz", "60 Hz", "59.94 Hz", with 60 selected
#   - eDP-1 lists one mode: no row
#   - picking 74.97 runs <HOME>/.local/bin/koompi-displays rate Virtual-1 74.97,
#     and picking Left of still runs place the same way (two detached processes,
#     so the log is compared sorted)
#   - the page follows the compositor: once the koompi-displays shim has seen
#     `rate`, hyprctl reports 74.97 as running, and after the page re-reads the
#     monitors 74.97 is the selected rate and the line above the rows says @74.97Hz
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

for tool in kwin_wayland qs dbus-run-session jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/run" "$WORK/home/.local/bin" "$WORK/xdg/config/koompi" \
    "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
chmod 700 "$WORK/run"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"language": {"ui": "en_US"}, "windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"

cat > "$WORK/monitors.json" <<'JSON'
[
  {"id": 0, "name": "Virtual-0", "description": "BOE 3296", "width": 1920, "height": 1200,
   "refreshRate": 60.00300, "x": 0, "y": 0, "scale": 1.00, "transform": 0,
   "availableModes": ["1920x1200@60.00Hz"]},
  {"id": 1, "name": "Virtual-1", "description": "WAM 9088", "width": 1920, "height": 1080,
   "refreshRate": 60.00000, "x": 1920, "y": 0, "scale": 1.00, "transform": 0,
   "availableModes": ["1920x1080@60.00Hz", "1920x1080@74.97Hz", "1920x1080@59.94Hz", "1920x1080@60.00Hz",
     "1680x1050@59.95Hz", "1400x1050@59.98Hz", "1280x1024@75.03Hz", "1280x1024@60.02Hz", "1440x900@59.89Hz",
     "1280x960@60.00Hz", "1366x768@60.00Hz", "1152x864@75.00Hz", "1280x720@60.00Hz", "1280x720@59.94Hz",
     "1280x720@60.00Hz", "1024x768@60.00Hz", "1024x768@70.07Hz", "1024x768@75.03Hz", "832x624@74.55Hz",
     "800x600@56.25Hz", "800x600@60.32Hz", "800x600@72.19Hz", "800x600@75.00Hz", "640x480@59.94Hz",
     "640x480@66.67Hz", "640x480@72.81Hz", "640x480@72.01Hz", "640x480@75.00Hz", "640x480@60.00Hz",
     "720x400@70.08Hz"]}
]
JSON
jq '.[1].refreshRate = 74.97300' "$WORK/monitors.json" > "$WORK/monitors-applied.json"
cat > "$WORK/bin/hyprctl" <<SH
#!/usr/bin/env bash
case " \$* " in
    *" monitors "*) if [[ -e "$WORK/applied" ]]; then cat "$WORK/monitors-applied.json"; else cat "$WORK/monitors.json"; fi ;;
esac
SH
cat > "$WORK/home/.local/bin/koompi-displays" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$0 \$*" >> "$WORK/displays.log"
[[ \$1 != rate ]] || : > "$WORK/applied"
SH
chmod +x "$WORK/bin"/* "$WORK/home/.local/bin"/*

cat > "$WORK/shell/rate_probe.qml" <<'QML'
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import Quickshell
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.settings

ShellRoot {
    id: probe
    property int ticks: 0
    property int actedAt: 0

    FloatingWindow {
        visible: true
        implicitWidth: 900
        implicitHeight: 1000
        DisplaysConfig {
            id: page
            anchors.fill: parent
        }
    }

    function walk(item, visit) {
        visit(item);
        for (let i = 0; i < item.children.length; i++) probe.walk(item.children[i], visit);
    }

    function rowsOf(block) {
        const rows = [];
        probe.walk(block, sub => {
            if (!String(sub).startsWith("ContentSubsection")) return;
            let array = null;
            probe.walk(sub, x => { if (!array && String(x).startsWith("ConfigSelectionArray")) array = x; });
            if (!array) return;
            rows.push({
                title: sub.title,
                shown: sub.visible,
                values: Array.from(array.options, o => o.value),
                labels: Array.from(array.options, o => o.displayName),
                current: array.currentValue,
                array: array
            });
        });
        return rows;
    }

    function blocks() {
        const found = {};
        probe.walk(page, item => {
            if (typeof item.screenInfo === "undefined") return;
            let details = "";
            probe.walk(item, x => { if (typeof x.text === "string" && /^\d+x\d+@[\d.]+Hz/.test(x.text)) details = x.text; });
            found[item.screenInfo.name] = { rows: probe.rowsOf(item), details: details };
        });
        return found;
    }

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
    }

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function check(found) {
        const hdmi = found["Virtual-1"]?.rows ?? [];
        const edp = found["Virtual-0"]?.rows ?? [];
        const title = Translation.tr("Refresh rate");
        const hdmiRate = hdmi.find(r => r.title === title);
        const edpRate = edp.find(r => r.title === title);
        probe.verdict(found["Virtual-0"] !== undefined && found["Virtual-1"] !== undefined,
            "the page has a block for each monitor, got " + JSON.stringify(Object.keys(found)));
        probe.verdict(hdmiRate?.shown === true, "HDMI-A-1 shows a Refresh rate row");
        probe.verdict(probe.same(hdmiRate?.values, [74.97, 60, 59.94]),
            "its options are 74.97, 60 and 59.94, highest first, one 60, none from another resolution, got " + JSON.stringify(hdmiRate?.values));
        probe.verdict(probe.same(hdmiRate?.labels, ["74.97 Hz", "60 Hz", "59.94 Hz"]),
            "its labels are 74.97 Hz, 60 Hz and 59.94 Hz, got " + JSON.stringify(hdmiRate?.labels));
        probe.verdict(hdmiRate?.current === 60, "60 is the selected rate, got " + hdmiRate?.current);
        probe.verdict(!edpRate || edpRate.shown === false, "eDP-1 lists one mode and shows no Refresh rate row");
        const elsewhere = { width: 1920, height: 1080, availableModes: ["1920x1080@60.00Hz", "1280x720@60.00Hz", "1280x720@50.00Hz"] };
        probe.verdict(probe.same(page.ratesAtCurrentSize(elsewhere), [60]), "rates at other resolutions do not count, so this monitor has one rate and no row");
        probe.verdict(probe.same(page.ratesAtCurrentSize({ width: 1920, height: 1080 }), []), "a monitor that lists no modes offers no rate");
        return { rate: hdmiRate, position: hdmi.find(r => probe.same(r.values, ["left", "right", "above", "below"])) };
    }

    function checkAfter(found) {
        const hdmi = found["Virtual-1"];
        const rate = hdmi?.rows.find(r => r.title === Translation.tr("Refresh rate"));
        probe.verdict(rate?.current === 74.97, "once the monitors are re-read, 74.97 is the selected rate, got " + rate?.current);
        probe.verdict(hdmi?.details.includes("@74.97Hz") === true, "the line above the rows says @74.97Hz, got " + JSON.stringify(hdmi?.details));
    }

    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            const loaded = page.hyprMonitors["Virtual-0"] !== undefined && page.hyprMonitors["Virtual-1"] !== undefined;
            if (probe.ticks > 80 && !loaded) {
                console.log("FAIL the page never read the monitors, screens are " + JSON.stringify([...Quickshell.screens].map(s => s.name)));
                Qt.quit();
                return;
            }
            if (!loaded || !Config.ready || probe.ticks < 12) return;

            if (probe.actedAt === 0) {
                const acted = probe.check(probe.blocks());
                if (acted.rate) acted.rate.array.selected(acted.rate.values[0]);
                probe.verdict(!!acted.position, "HDMI-A-1 also has the position row");
                if (acted.position) acted.position.array.selected("left");
                probe.actedAt = probe.ticks;
                return;
            }
            if (probe.ticks - probe.actedAt > 8) {
                probe.checkAfter(probe.blocks());
                console.log("PROBE DONE");
                Qt.quit();
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell"
qs -p "$WORK/shell/rate_probe.qml" > "$WORK/qs.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" HOME="$WORK/home" QT_NO_XDG_DESKTOP_PORTAL=1 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland \
    XDG_RUNTIME_DIR="$WORK/run" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" \
    XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --output-count 2 \
        --width 1920 --height 1200 --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
grep -q 'PROBE DONE' <<< "$out" || fail "the probe never finished"
grep -q '^ DEBUG qml: FAIL' <<< "$out" && fail "the Displays page does not match the contract above"

tool="$WORK/home/.local/bin/koompi-displays"
mapfile -t calls < <(sort "$WORK/displays.log" 2> /dev/null)
if (( ${#calls[@]} == 2 )) && [[ "${calls[0]}" == "$tool place Virtual-1 left" && "${calls[1]}" == "$tool rate Virtual-1 74.97" ]]; then
    echo "PASS picking 74.97 and Left of ran koompi-displays by its absolute path: rate Virtual-1 74.97, place Virtual-1 left"
else
    fail "the selections did not run koompi-displays rate and place by absolute path; displays.log: '${calls[*]:-nothing}'"
fi

if (( failed )); then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    exit 1
fi
echo "ok   displays page: a Refresh rate row for the monitor that lists several rates at its resolution, none for the one that lists one"
