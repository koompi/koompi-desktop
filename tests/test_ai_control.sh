#!/usr/bin/env bash
# The Control session's surface: while the assistant has its own browser open a pill
# says so (modules/koompi/aiControl/AiControl.qml), Pause makes every browser step
# wait for the user and Resume undoes it, and the stop (the aiControl IPC target, as
# Super+Shift+Escape's global shortcut calls) closes the browser and releases the pill.
#
# The approval card loads for a browser step (the step as the engine described it,
# nothing to remember) and for a command. Source checks, then a probe in a virtual
# kwin with throwaway HOME and XDG dirs. The browser is headless Chrome and opens
# nothing but about:blank. Skips the probe with no qs, kwin_wayland or Chrome.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
CONTROL="$SHELL_ROOT/modules/koompi/aiControl/AiControl.qml"
KEYBINDS="$REPO_ROOT/dots/.config/hypr/hyprland/keybinds_ai.lua"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

# --- source ------------------------------------------------------------------
[[ -f $CONTROL ]] || { fail "missing $CONTROL"; exit 1; }
grep -q 'hl.bind("SUPER + SHIFT + Escape", hl.dsp.global("quickshell:aiControlStop")' "$KEYBINDS" \
    || fail "Super+Shift+Escape is not bound to quickshell:aiControlStop"
grep -q '^require("hyprland.keybinds_ai")$' "$REPO_ROOT/dots/.config/hypr/hyprland.lua" \
    || fail "hyprland.lua does not require hyprland.keybinds_ai, so the stop key is never bound"
grep -q '"hyprland.keybinds_ai"' "$SHELL_ROOT/services/HyprlandKeybinds.qml" \
    || fail "HyprlandKeybinds.qml does not replay hyprland.keybinds_ai, so the cheatsheet would not list the stop key"
grep -q 'name: "aiControlStop"' "$CONTROL" || fail "AiControl.qml has no aiControlStop global shortcut"
grep -q 'target: "aiControl"' "$CONTROL" || fail "AiControl.qml has no aiControl IPC target"
for family in KoompiFamily WaffleFamily; do
    grep -q 'PanelLoader { component: AiControl {} }' "$SHELL_ROOT/panelFamilies/$family.qml" \
        || fail "$family does not load AiControl, so its stop key would not exist there"
done
(( $(wc -l < "$CONTROL") <= 400 )) || fail "AiControl.qml is over the 400-line cap"
(( failed )) || echo "ok   source: the key, the shortcut, the IPC target, both families"

# --- headless ----------------------------------------------------------------
for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null || { echo "skip: needs $tool for the headless probe"; exit $failed; }
done
command -v google-chrome-stable > /dev/null || command -v chromium > /dev/null \
    || { echo "skip: no google-chrome-stable or chromium for the headless probe"; exit $failed; }

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
cleanup() {
    pkill -f -- "--user-data-dir=$WORK/" 2>/dev/null
    (( failed )) && echo "kept $WORK" >&2 || rm -rf -- "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/bin" "$WORK/out" "$WORK/home" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/control_probe.qml" <<'QML'
import Quickshell
import Quickshell.Io
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.aiControl
import qs.modules.koompi.sidebarLeft.aiChat.approval

ShellRoot {
    id: probe
    property int stage: 0
    property int ticks: 0
    property var reply: null

    AiControl { id: control }

    // the cards a browser step and a command ask through
    ApprovalCard {
        id: browserCard
        messageData: ({ "functionCall": { "name": "browser", "args": { "op": "click", "ref": "4" },
            "summary": "click [4] button \"Place order\" (submits form)" }, "functionPending": true, "rawContent": "", "content": "" })
    }
    ApprovalCard {
        id: shellCard
        messageData: ({ "functionCall": { "name": "run_shell_command", "args": { "command": "uptime" } },
            "functionPending": true, "rawContent": "", "content": "" })
    }

    FileView {
        id: ready
        path: Quickshell.env("PROBE_OUT") + "/ready"
        blockWrites: true
    }

    function findNamed(obj, name) {
        if (!obj) return null;
        if (obj.objectName === name) return obj;
        const list = obj.data;
        for (let i = 0; list && i < list.length; i++) {
            const found = probe.findNamed(list[i], name);
            if (found) return found;
        }
        return null;
    }
    function verdict(ok, text) { console.log((ok ? "PASS " : "FAIL ") + text); }
    function stateText() { return probe.findNamed(control.window?.contentItem, "aiControlState")?.text ?? "(none)"; }
    function done() { console.log("PROBE DONE"); Qt.quit(); }

    function step() {
        if (++probe.ticks > 300) { probe.verdict(false, `timed out at stage ${probe.stage}`); probe.done(); return; }
        switch (probe.stage) {
        case 0:
            if (!Config.ready) return;
            probe.verdict(control.window === null && !Ai.browserActive, "no pill while the assistant has no browser");
            probe.verdict(browserCard.isBrowser && browserCard.target === "click [4] button \"Place order\" (submits form)",
                `a browser card shows the step as the engine described it: ${browserCard.target}`);
            probe.verdict(!browserCard.canRemember && browserCard.rule === "", "a browser card offers nothing to remember");
            probe.verdict(shellCard.isCommand && shellCard.rule === "uptime" && shellCard.canRemember && !shellCard.tainted,
                "a command card in a clean turn keeps its rule and Always allow");
            Ai.browserTool.service.request("tabs", {}, r => probe.reply = r);
            probe.stage = 1;
            return;
        case 1:
            if (!probe.reply || !control.window) return;
            probe.verdict(probe.reply.ok === true, `the driver answered the first step: ${JSON.stringify(probe.reply).slice(0, 160)}`);
            probe.verdict(Ai.browserActive && Ai.browserPid > 0, `the browser is up and its pid is known (${Ai.browserPid})`);
            console.log(`CHROME ${Ai.browserPid}`);
            probe.verdict(control.window.visible, "the pill shows while the browser runs");
            probe.verdict(probe.stateText() === "The assistant is using its browser", `the pill says so: ${probe.stateText()}`);
            probe.verdict(probe.findNamed(control.window.contentItem, "aiControlStop") !== null, "the pill carries Stop");
            probe.verdict(Ai.isPreApproved("browser", { "op": "snapshot" }), "before a pause a snapshot runs without asking");
            Ai.pauseControl();
            probe.stage = 2;
            return;
        case 2:
            probe.verdict(Ai.browserPaused && probe.stateText() === "Paused", `Pause marks the session paused: ${probe.stateText()}`);
            probe.verdict(!Ai.isPreApproved("browser", { "op": "snapshot" }), "while paused even a snapshot asks");
            Ai.resumeControl();
            probe.verdict(!Ai.browserPaused && Ai.isPreApproved("browser", { "op": "snapshot" }), "Resume lets steps run again");
            ready.setText("1\n");
            probe.stage = 3;
            return;
        case 3: // the stop arrives over IPC from inner.sh
            if (Ai.browserActive) return;
            probe.verdict(Ai.browserPid === 0, "the stop closed the browser");
            probe.stage = 4;
            return;
        case 4:
            if (control.window !== null) return;
            probe.verdict(true, "the pill is released once the browser is gone");
            probe.done();
        }
    }

    Timer { interval: 200; repeat: true; running: true; onTriggered: probe.step() }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
unset HYPRLAND_INSTANCE_SIGNATURE
probe="$WORK/shell/control_probe.qml"
qs -p "\$probe" > "$WORK/qs.log" 2>&1 &
qspid=\$!
for _ in \$(seq 1 300); do [[ -e "$WORK/out/ready" ]] && break; sleep 0.2; done
qs -p "\$probe" ipc call aiControl stop > "$WORK/ipc.log" 2>&1
wait \$qspid
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" PROBE_OUT="$WORK/out" \
    KOOMPI_AI_BROWSER_HEADLESS=1 TMPDIR="$WORK" \
    QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" XDG_DATA_HOME="$WORK/xdg/data" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 --no-lockscreen --no-global-shortcuts \
        --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log" 2>/dev/null)"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    fail "the control probe did not pass"
fi
if errors="$(grep -E 'Binding loop|TypeError|ReferenceError' <<< "$out" | grep -i 'aiControl\|BrowserTool\|BrowserService\|ToolApproval')"; then
    echo "$errors" >&2
    fail "the Control session logged a binding loop or a script error"
fi
chrome="$(sed -n 's/^ DEBUG qml: CHROME //p' <<< "$out")"
if [[ -n $chrome ]] && kill -0 "$chrome" 2>/dev/null; then
    fail "Chrome $chrome outlived the stop"
fi
(( failed )) || echo "ok   headless: the pill shows with the browser, Pause makes steps ask, Resume undoes it, the IPC stop closes the browser and the pill"
exit $failed
