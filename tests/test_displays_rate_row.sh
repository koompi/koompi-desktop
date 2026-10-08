#!/usr/bin/env bash
# Settings > Displays offers a refresh rate per monitor, asks Keep or Revert after a switch, and shows what the tool says when it fails
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

for tool in kwin_wayland qs dbus-run-session jq setsid; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/run" "$WORK/home/.local/bin" "$WORK/xdg/config/koompi" "$WORK/xdg/config/hypr" \
    "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
chmod 700 "$WORK/run"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"language": {"ui": "en_US"}, "windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"

jq 'map(.name |= (if . == "eDP-1" then "Virtual-0" else "Virtual-1" end))' "$REPO_ROOT/tests/displays-monitors.json" > "$WORK/state.json"
cp "$REPO_ROOT/tests/displays-hyprctl" "$WORK/bin/hyprctl"
cat > "$WORK/bin/luac" <<SH
#!/usr/bin/env bash
[[ -e "$WORK/luac.fail" ]] && exit 1
exec $(command -v luac || command -v true) "\$@"
SH
chmod +x "$WORK/bin"/*
cat > "$WORK/home/.local/bin/koompi-displays" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/tool.log"
exec "$REPO_ROOT/dots/.local/bin/koompi-displays" "\$@"
SH
chmod +x "$WORK/home/.local/bin/koompi-displays"

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
    property int step: 0
    property int stepStarted: 0
    property string rateError: ""
    property int pendingEnded: 0
    readonly property string flags: Quickshell.env("PROBE_DIR")
    readonly property string cannotSave: flags + "/luac.fail"
    readonly property string ignored: flags + "/state.json.ignore"

    Connections {
        target: page
        function onPendingChanged() {
            if (page.pending === null)
                probe.pendingEnded = probe.ticks;
        }
    }

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

    function find(root, type, test) {
        let hit = null;
        probe.walk(root, x => { if (!hit && String(x).startsWith(type) && (!test || test(x))) hit = x; });
        return hit;
    }

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
    }

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function block(name) {
        let found = null;
        probe.walk(page, item => { if (item.screenInfo !== undefined && item.screenInfo.name === name) found = item; });
        return found;
    }

    function row(name, title) {
        const sub = probe.find(probe.block(name), "ContentSubsection", x => x.title === title);
        return sub ? { sub: sub, array: probe.find(sub, "ConfigSelectionArray") } : null;
    }

    function rateRow() { return probe.row("Virtual-1", Translation.tr("Refresh rate")); }

    function placeRow() { return probe.row("Virtual-1", Translation.tr("Position relative to %1").arg(page.anchorName)); }

    function pills(group) {
        const found = [];
        probe.walk(group.array, x => { if (String(x).startsWith("SelectionGroupButton")) found.push(x); });
        return found;
    }

    function pill(group, text) { return probe.pills(group).find(x => x.buttonText === text); }

    function toggledText(group) { return probe.pills(group).filter(x => x.toggled).map(x => x.buttonText).join(","); }

    function bar() { return probe.find(probe.block("Virtual-1"), "NoticeBox"); }

    function details(name) {
        let text = "";
        probe.walk(probe.block(name), x => { if (typeof x.text === "string" && /^\d+x\d+@[\d.]+Hz/.test(x.text)) text = x.text; });
        return text;
    }

    function shows(message) {
        let seen = false;
        probe.walk(page, x => { if (x.text === message && x.visible) seen = true; });
        return seen;
    }

    function waits() { return probe.bar() !== null && probe.bar().visible; }

    function settled(rate) {
        return page.pending === null && page.busy === 0 && probe.rateRow()?.array.currentValue === rate;
    }

    function touch(...paths) { Quickshell.execDetached(["touch", ...paths]); }

    function remove(...paths) { Quickshell.execDetached(["rm", "-f", ...paths]); }

    function loaded() {
        return page.hyprMonitors["Virtual-0"] !== undefined && page.hyprMonitors["Virtual-1"] !== undefined
            && Config.ready && probe.ticks > 24 && probe.block("Virtual-1") !== null;
    }

    function checkRows() {
        const hdmi = probe.rateRow();
        const edp = probe.row("Virtual-0", Translation.tr("Refresh rate"));
        probe.verdict(hdmi?.sub.visible === true, "HDMI-A-1 shows a Refresh rate row");
        probe.verdict(probe.same(Array.from(hdmi?.array.options ?? [], o => o.value), [74.97, 60, 59.94]),
            "its options are 74.97, 60 and 59.94, highest first, one 60, none from another resolution");
        probe.verdict(probe.same(Array.from(hdmi?.array.options ?? [], o => o.displayName), ["75 Hz", "60 Hz", "59.94 Hz"]),
            "its labels are whole hertz unless two rates round alike: 75 Hz, 60 Hz and 59.94 Hz");
        probe.verdict(hdmi?.array.currentValue === 60, "60 is the selected rate");
        probe.verdict(!edp || edp.sub.visible === false, "eDP-1 lists one mode and shows no Refresh rate row");
        probe.verdict(probe.details("Virtual-1").includes("@60Hz"), "the line above the rows says @60Hz, got " + JSON.stringify(probe.details("Virtual-1")));
        probe.verdict(probe.same([74.97, 75, 60].map(r => page.rateLabel(r, [74.97, 75, 60])), ["74.97 Hz", "75 Hz", "60 Hz"]),
            "74.97 and 75 on one monitor keep their decimals");
        const elsewhere = { width: 1920, height: 1080, availableModes: ["1920x1080@60.00Hz", "1280x720@60.00Hz", "1280x720@50.00Hz"] };
        probe.verdict(probe.same(page.ratesAtCurrentSize(elsewhere), [60]), "rates at other resolutions do not count");
        probe.verdict(probe.same(page.ratesAtCurrentSize({ width: 1920, height: 1080 }), []), "a monitor that lists no modes offers no rate");
        hdmi.array.selected(74.97);
    }

    function checkBar() {
        const notice = probe.bar();
        probe.verdict(notice.text.includes(Translation.tr("Keep this refresh rate?")), "the bar asks Keep this refresh rate?, got " + JSON.stringify(notice.text));
        probe.verdict(page.secondsLeft > 0 && page.secondsLeft <= 8, "it counts down from the seconds the tool gave, got " + page.secondsLeft);
        probe.verdict(notice.text.includes("75 Hz now") && notice.text.includes("back to 60 Hz"), "it names the rate now and the rate it goes back to");
        const rate = probe.rateRow();
        const place = probe.placeRow();
        probe.verdict(rate.array.enabled && place.array.enabled && probe.pills(rate).every(x => x.enabled) && probe.pills(place).every(x => x.enabled),
            "both groups and every pill in them stay enabled while it waits");
        probe.verdict(probe.toggledText(rate) === "75 Hz", "the toggled rate pill is the new rate, got " + JSON.stringify(probe.toggledText(rate)));
        probe.verdict(probe.toggledText(place) === "Right of", "the toggled position pill is Right of, got " + JSON.stringify(probe.toggledText(place)));
        probe.pill(rate, "60 Hz").clicked();
        probe.pill(place, "Left of").clicked();
        probe.verdict(page.busy === 0, "a click on another rate and on another position starts no tool call");
    }

    function checkIgnored() {
        probe.verdict(page.busy === 0 && page.failure === null && page.pending !== null, "and nothing came of them: no failure, the question is still up");
        probe.verdict(probe.toggledText(probe.rateRow()) === "75 Hz" && probe.toggledText(probe.placeRow()) === "Right of", "and the same pills are toggled");
        probe.find(probe.bar(), "RippleButtonWithIcon", x => x.mainText === Translation.tr("Keep")).clicked();
    }

    function checkKept() {
        probe.verdict(!probe.waits(), "Keep closes the bar");
        probe.verdict(probe.details("Virtual-1").includes("@75Hz"), "the line above the rows says @75Hz, got " + JSON.stringify(probe.details("Virtual-1")));
        probe.verdict(probe.toggledText(probe.rateRow()) === "75 Hz", "75 Hz is still the toggled pill");
        probe.rateRow().array.selected(59.94);
    }

    function checkTimedOut() {
        probe.verdict(!probe.waits(), "with no answer the bar goes away by itself");
        probe.verdict(probe.rateRow().array.currentValue === 74.97, "and 74.97 is the selected rate again");
        const lag = probe.ticks - probe.pendingEnded;
        probe.verdict(lag <= 3, "the pill followed the monitor within 3 ticks of the question ending, took " + lag);
        probe.touch(probe.ignored);
    }

    function checkRateError() {
        const message = page.failure.message;
        probe.verdict(message === "Virtual-1 did not switch to 60 Hz", "a switch the compositor ignored says so under the row, got " + JSON.stringify(message));
        probe.verdict(probe.shows(message), "and the message is on screen");
        probe.verdict(!probe.waits() && page.busy === 0, "nothing is left waiting");
        probe.rateError = message;
        probe.remove(probe.ignored);
        probe.touch(probe.cannotSave);
    }

    function checkPlaceError() {
        const message = page.failure.message;
        probe.verdict(message.includes("failed lua validation"), "a placement that could not be saved says so under its row, got " + JSON.stringify(message));
        probe.verdict(probe.shows(message), "and the message is on screen");
        probe.verdict(!probe.shows(probe.rateError), "the earlier rate error is gone once another command ran");
        probe.remove(probe.cannotSave);
    }

    function failed(row) { return () => page.failure !== null && page.failure.row === row; }

    function delayed(ticks) { return () => probe.ticks - probe.stepStarted >= ticks; }

    readonly property var steps: [
        { until: () => probe.loaded(), run: () => probe.checkRows() },
        { until: () => probe.waits(), run: () => probe.checkBar() },
        { until: probe.delayed(6), run: () => probe.checkIgnored() },
        { until: () => probe.settled(74.97), run: () => probe.checkKept() },
        { until: () => probe.waits(), run: () => {} },
        { until: () => probe.settled(74.97), run: () => probe.checkTimedOut(), max: 120 },
        { until: probe.delayed(6), run: () => probe.rateRow().array.selected(60) },
        { until: probe.failed("Virtual-1/rate"), run: () => probe.checkRateError() },
        { until: probe.delayed(6), run: () => probe.placeRow().array.selected("left") },
        { until: probe.failed("Virtual-1/place"), run: () => probe.checkPlaceError() },
        { until: probe.delayed(6), run: () => probe.rateRow().array.selected(59.94) },
        { until: () => probe.waits(), run: () => { probe.touch(probe.flags + "/closed"); console.log("PROBE DONE"); Qt.quit(); } }
    ]

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            probe.ticks++;
            const current = probe.steps[probe.step];
            if (!current) return;
            if (current.until()) {
                probe.step++;
                probe.stepStarted = probe.ticks;
                current.run();
            } else if (probe.ticks - probe.stepStarted > (current.max ?? 80)) {
                console.log("FAIL step " + probe.step + " never happened, pending " + JSON.stringify(page.pending) + ", failure " + JSON.stringify(page.failure));
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
    HYPRCTL_STATE="$WORK/state.json" HYPRCTL_EVAL_LOG="$WORK/eval.log" PROBE_DIR="$WORK" KOOMPI_DISPLAYS_CONFIRM_SECONDS=8 \
    timeout 180 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --output-count 2 \
        --width 1920 --height 1200 --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
grep -q 'PROBE DONE' <<< "$out" || fail "the probe never finished"
grep -q '^ DEBUG qml: FAIL' <<< "$out" && fail "the Displays page does not match the contract above"

hdmi_rate() { jq -r '.[1].refreshRate' "$WORK/state.json"; }
saved=$'hl.monitor({\n    output = "desc:BOE 0x0CE0",\n    mode = "1920x1200@60",\n    position = "0x0",\n    scale = 1,\n    transform = 0\n})\nhl.monitor({\n    output = "desc:WAM HDMI 18250023",\n    mode = "1920x1080@74.97",\n    position = "1920x0",\n    scale = 1.25,\n    transform = 0\n})'
[[ "$(tail -n +3 "$WORK/xdg/config/hypr/monitors.lua" 2> /dev/null)" == "$saved" ]] \
    || fail "monitors.lua is not exactly the layout of the one rate that was kept: $(cat "$WORK/xdg/config/hypr/monitors.lua" 2> /dev/null)"
first="$(sed -n 1p "$WORK/eval.log")"
[[ "$first" == 'hl.monitor({output = "Virtual-1", mode = "1920x1080@74.97", position = "1920x0", scale = 1.25})' ]] \
    || fail "the page's first request was not the tool's switch to 74.97 by its absolute path: '$first'"
for _ in $(seq 1 60); do [[ "$(hdmi_rate)" == 74.97 && ! -e "$WORK/run/koompi-displays/pending" ]] && break; sleep 0.25; done
[[ "$(hdmi_rate)" == 74.97 ]] || fail "closing Settings with a change waiting left the monitor on $(hdmi_rate)"
[[ ! -e "$WORK/run/koompi-displays/pending" ]] || fail "a change is still waiting 15 s after Settings closed"
lag="$(( $(stat -c %Y "$WORK/state.json") - $(stat -c %Y "$WORK/closed") ))"
(( lag < 4 )) || fail "the old rate came back ${lag} s after Settings closed, which is the 8 s timer and not the window closing"
calls=$'rate Virtual-1 74.97\nkeep\nrate Virtual-1 59.94\nrevert\nrate Virtual-1 60\nplace Virtual-1 left\nrate Virtual-1 59.94\nrevert'
[[ "$(cat "$WORK/tool.log" 2> /dev/null)" == "$calls" ]] || fail "the page ran other tool calls than these, in this order: $(tr '\n' '|' < "$WORK/tool.log" 2> /dev/null)"

if (( failed )); then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    exit 1
fi
echo "ok   displays page: a Refresh rate row per monitor with several rates, Keep or Revert after a switch, the tool's errors under the row"
