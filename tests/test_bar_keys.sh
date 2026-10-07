#!/usr/bin/env bash
# J34: the update badge on the KOOMPI bar (O09) and bar popups by keyboard (O34).
# J01: the badge is its own item beside the panel button and opens an updates
# popup; the clock popup stays on a narrow screen. Headless: KWin's virtual
# backend hosts a nested shell with KOOMPI_UPDATES_FORCE=12 and the probe
# measures real geometry. BAR_SHOT=<path> keeps the bar image, with
# BAR_SHOT-popup.png (clock) and BAR_SHOT-updates.png beside it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
BAR="$SHELL_ROOT/modules/koompi/bar"
HYPR="$REPO_ROOT/dots/.config/hypr"
BINDS="$HYPR/hyprland/keybinds_shell_extra.lua"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

# --- lua ---------------------------------------------------------------------
if command -v luac >/dev/null 2>&1; then
    for f in "$BINDS" "$HYPR/hyprland.lua"; do
        luac -p "$f" || fail "luac rejects ${f#"$REPO_ROOT"/}"
    done
    echo "ok   luac: keybinds_shell_extra.lua and hyprland.lua parse"
else
    echo "skip: no luac, lua syntax unchecked"
fi
grep -A2 'require("hyprland.keybinds")' "$HYPR/hyprland.lua" | grep -q 'require("hyprland.keybinds_shell_extra")' \
    || fail "hyprland.lua does not require hyprland.keybinds_shell_extra right after hyprland.keybinds"
[[ -e "$HYPR/hyprland/keybinds_notifications.lua" ]] && fail "keybinds_notifications.lua still exists beside its rename"

# Nine described chords, Super+Ctrl+1..9, each calling `bar popup N`; the
# keycode twins are hidden. The loop is what makes them nine, so run it.
described="$(lua - "$BINDS" <<'LUA' 2>&1
local binds = {}
hl = { bind = function(keys, _, opts) binds[#binds + 1] = { keys = keys, desc = opts and opts.description } end,
       dsp = { exec_cmd = function(cmd) return cmd end } }
dofile(arg[1])
local n = 0
for _, b in ipairs(binds) do
    if b.desc and b.desc:find("Bar popup", 1, true) then
        n = n + 1
        assert(b.keys == "SUPER + CTRL + " .. n, "chord " .. n .. " is " .. b.keys)
    end
end
print(n)
LUA
)" || fail "keybinds_shell_extra.lua did not run under a stub hl: $described"
[[ "$described" == "9" ]] || fail "expected 9 described 'Bar popup' chords, got: $described"
for fn in 'popup(n: int): void' 'popupClose(): void'; do
    grep -qF "function $fn" "$BAR/Bar.qml" || fail "Bar.qml IpcHandler bar has no $fn"
done
grep -q '^        function popup(n: int)' "$BAR/Bar.qml" && grep -q 'target: "bar"' "$BAR/Bar.qml" \
    || fail "popup() is not inside the IpcHandler for target bar"
echo "ok   chords: 9 described Super+Ctrl+N binds, Bar.qml implements popup(n) and popupClose()"

# The popup order is one list in three places: Bar.qml's comment, the popups'
# keyIndex, and the lua descriptions.
indices="$(grep -ho '^    keyIndex: [0-9]*' "$BAR"/*Popup.qml | awk '{print $2}' | sort -n | tr '\n' ' ')"
[[ "$indices" == "1 2 3 4 " ]] || fail "popup keyIndex values are not exactly 1..4: $indices"
for pair in "1:AgentUsagePopup" "2:BatteryPopup" "3:PomodoroPopup" "4:ClockWidgetPopup"; do
    grep -q "keyIndex: ${pair%%:*}\b" "$BAR/${pair#*:}.qml" || fail "${pair#*:} is not popup ${pair%%:*}"
done
grep -q 'Keys.onEscapePressed: root.close()' "$BAR/StyledPopup.qml" || fail "StyledPopup does not close on Escape"
echo "ok   popups: keyIndex 1 agent usage, 2 battery, 3 pomodoro, 4 clock; Escape closes"

# --- bar files ---------------------------------------------------------------
lines="$(wc -l < "$BAR/BarContent.qml")"
(( lines <= 400 )) || fail "BarContent.qml is $lines lines, cap is 400"
refs="$(grep -c 'UpdateBadge {' "$BAR/BarContent.qml")"
(( refs == 1 )) || fail "BarContent.qml references UpdateBadge $refs times, expected 1"
grep -q 'KOOMPI_UPDATES_FORCE' "$SHELL_ROOT/services/Updates.qml" || fail "Updates.qml lost the KOOMPI_UPDATES_FORCE hook"
grep -q 'Battery.isLow' "$SHELL_ROOT/services/Updates.qml" || fail "Updates.qml no longer gates the check on Battery.isLow"
echo "ok   BarContent.qml: $lines lines, badge referenced once"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in "$BAR"/{Bar,BarContent,UpdateBadge,UpdatesPopup,StyledPopup,AgentUsagePopup,BatteryPopup,PomodoroPopup,ClockWidgetPopup}.qml "$SHELL_ROOT/services/Updates.qml"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects ${f#"$SHELL_ROOT"/}"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in ${f#"$SHELL_ROOT"/}"; }
    done
    rm -rf "$LINT"
    echo "ok   qmllint: 10 bar files parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

# --- live binds --------------------------------------------------------------
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && hyprctl binds >/dev/null 2>&1; then
    if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland/keybinds_shell_extra.lua" ]]; then
        live="$(hyprctl binds | grep -ci 'description: Shell: bar popup')"
        (( live == 9 )) || fail "hyprctl binds lists $live 'Bar popup' chords, expected 9 (hyprctl reload?)"
        echo "ok   hyprctl binds: 9 bar popup chords described"
    else
        echo "skip: keybinds_shell_extra.lua is not installed in the live config, hyprctl binds not checked"
    fi
else
    echo "skip: no Hyprland session, hyprctl binds not checked"
fi

# --- headless bar with a forced update count --------------------------------
if ! command -v qs >/dev/null 2>&1 || ! command -v kwin_wayland >/dev/null 2>&1; then
    echo "skip: needs qs and kwin_wayland for the headless bar capture"
    exit $failed
fi

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/bin" "$WORK/out"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/bar_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs.modules.koompi.bar

ShellRoot {
    id: probe
    property string out: Quickshell.env("PROBE_OUT")
    property int ticks: 0
    property int stage: 0
    property int mark: -1

    Bar { id: bar }

    // The StyledPopup for keyIndex n is a LazyLoader somewhere under the bar
    // window; its item is the popup PanelWindow while open, null otherwise.
    function findPopup(obj, index) {
        if (obj.keyIndex !== undefined && obj.keyIndex === index) return obj;
        const list = obj.data;
        for (let i = 0; list && i < list.length; i++) {
            const found = probe.findPopup(list[i], index);
            if (found) return found;
        }
        return null;
    }

    function findNamed(obj, name) {
        if (obj.objectName === name) return obj;
        const list = obj.data;
        for (let i = 0; list && i < list.length; i++) {
            const found = probe.findNamed(list[i], name);
            if (found) return found;
        }
        return null;
    }

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
    }

    // A window's contentItem is Quickshell's proxy and cannot be grabbed, so
    // grab a child: the bar's first child is the hover region that fills it,
    // the popup's last child is its background (the first is the shadow).
    function grab(win, name, last, next) {
        const children = win?.contentItem?.children ?? [];
        const item = children.length ? children[last ? children.length - 1 : 0] : null;
        if (!item) { console.log("FAIL no item for " + name); next(); return; }
        const scheduled = item.grabToImage(result => {
            console.log((result.saveToFile(probe.out + "/" + name) ? "PASS " : "FAIL ") + "saved " + name + " " + item.width + "x" + item.height);
            next();
        });
        if (!scheduled) { console.log("FAIL grabToImage refused " + name); next(); }
    }

    function backgroundSpan(popupWindow) {
        const children = popupWindow.contentItem.children;
        const bg = children[children.length - 1];
        const left = popupWindow.margins.left + bg.mapToItem(null, 0, 0).x;
        return { left: left, right: left + bg.width };
    }

    function checkInside(label, popupWindow, screenWidth) {
        const span = probe.backgroundSpan(popupWindow);
        probe.verdict(span.left >= 0 && span.right <= screenWidth,
            label + " background inside the screen: x " + span.left + ".." + span.right + " of " + screenWidth);
    }

    function checkBadge(win) {
        const badge = probe.findNamed(win.contentItem, "updateBadge");
        const panel = probe.findNamed(win.contentItem, "rightSidebarButton");
        if (!badge || !panel) {
            probe.verdict(false, "badge and panel button found: badge=" + !!badge + " panel=" + !!panel);
            return;
        }
        const b = badge.mapToItem(null, 0, 0);
        const p = panel.mapToItem(null, 0, 0);
        const gap = p.x - (b.x + badge.width);
        probe.verdict(badge.visible && badge.width >= 24 && badge.height >= 24, "badge lit with a hit area of " + badge.width + "x" + badge.height);
        probe.verdict(gap >= 0 && gap <= 20, "badge sits left of the panel button, outside it: gap " + gap + "px (badge x " + b.x + ".." + (b.x + badge.width) + ", panel x " + p.x + ".." + (p.x + panel.width) + ")");
        probe.verdict(typeof badge.middleClickAction === "function", "middle-click on the badge still checks again");
    }

    // state-driven: inner.sh sends `bar popup 4` twice, the probe clicks the badge twice
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks > 200) {
                console.log("FAIL probe timed out in stage " + probe.stage);
                Qt.quit();
                return;
            }
            const win = bar.focusedBarWindow();
            if (!win) return;
            const clock = probe.findPopup(win.contentItem, 4);
            const updates = probe.findNamed(win.contentItem, "updatesPopup");
            const badge = probe.findNamed(win.contentItem, "updateBadge");

            if (probe.stage === 0) {
                if (clock?.keyboardOpen && clock.item) {
                    probe.verdict(true, "popup 4 keyboardOpen after ipc, window mapped");
                    probe.stage = 1;
                    probe.mark = probe.ticks;
                }
            } else if (probe.stage === 1) {
                if (probe.ticks - probe.mark < 2) return;
                probe.stage = 99;
                probe.checkBadge(win);
                probe.checkInside("clock popup", clock.item, win.screen.width);
                probe.grab(clock.item, "popup.png", true, () => probe.grab(win, "bar.png", false, () => { probe.stage = 2; }));
            } else if (probe.stage === 2) {
                if (!clock.keyboardOpen && !clock.item) {
                    probe.verdict(true, "popup 4 closed by the second call");
                    if (!badge) {
                        probe.verdict(false, "no badge to click");
                        Qt.quit();
                        return;
                    }
                    badge.click();
                    probe.stage = 3;
                    probe.mark = -1;
                }
            } else if (probe.stage === 3) {
                if (updates?.item && probe.mark < 0) probe.mark = probe.ticks;
                if (probe.mark < 0 || probe.ticks - probe.mark < 2) return;
                probe.stage = 99;
                probe.verdict(updates.active, "badge click opened the updates popup");
                probe.checkInside("updates popup", updates.item, win.screen.width);
                probe.grab(updates.item, "updates.png", true, () => {
                    badge.click();
                    probe.stage = 4;
                });
            } else if (probe.stage === 4) {
                if (!updates.active && !updates.item) {
                    probe.verdict(true, "second badge click closed the updates popup");
                    console.log("PROBE DONE");
                    Qt.quit();
                }
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
unset HYPRLAND_INSTANCE_SIGNATURE
probe="$WORK/shell/bar_probe.qml"
qs -p "\$probe" > "$WORK/qs.log" 2>&1 &
for _ in \$(seq 1 60); do qs -p "\$probe" ipc show > /dev/null 2>&1 && break; sleep 0.5; done
sleep 3
qs -p "\$probe" ipc call bar popup 4 > "$WORK/ipc.log" 2>&1
sleep 8
qs -p "\$probe" ipc call bar popup 4 >> "$WORK/ipc.log" 2>&1
wait
SH
chmod +x "$WORK/inner.sh"

# pinned to wayland: a probe on xcb gets no layershell and the bar never maps
mkdir -p "$WORK/xdg/data" "$WORK/home" "$WORK/rt" && chmod 700 "$WORK/rt"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" KOOMPI_UPDATES_FORCE=12 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" PROBE_OUT="$WORK/out" \
    QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" XDG_DATA_HOME="$WORK/xdg/data" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 90 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 400 --no-lockscreen --no-global-shortcuts \
        --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    cat "$WORK/ipc.log" >&2
    fail "headless bar probe did not pass"
fi
if loops="$(grep -E 'Binding loop' <<< "$out")"; then
    echo "$loops" >&2
    fail "the bar has a QML binding loop"
fi
[[ -s "$WORK/out/bar.png" ]] || fail "no bar.png from the headless bar"
[[ -s "$WORK/out/popup.png" ]] || fail "no popup.png from the keyboard-opened clock popup"
[[ -s "$WORK/out/updates.png" ]] || fail "no updates.png from the badge-opened updates popup"
if [[ -n "${BAR_SHOT:-}" ]]; then
    cp "$WORK/out/bar.png" "$BAR_SHOT"
    cp "$WORK/out/popup.png" "${BAR_SHOT%.png}-popup.png"
    cp "$WORK/out/updates.png" "${BAR_SHOT%.png}-updates.png"
    echo "     bar image at $BAR_SHOT, popups at ${BAR_SHOT%.png}-popup.png and ${BAR_SHOT%.png}-updates.png"
fi
(( failed )) || echo "ok   headless: 12 forced updates, badge beside the panel button, popups inside the screen, clock popup over IPC, updates popup over clicks"
exit $failed
