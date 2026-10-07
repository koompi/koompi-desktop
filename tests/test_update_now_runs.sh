#!/usr/bin/env bash
# J01: "Update now" in the updates popup opens a floating terminal that runs
# `koompi update`. Hyprland here reads Lua, so the dispatch must be a
# hl.dsp.exec_cmd call: a legacy `exec [float]` string returns an error and
# starts nothing, and nothing in QML shows it. The whole path is real: a nested
# Hyprland inside headless KWin on a private bus and runtime dir, the real bar
# with KOOMPI_UPDATES_FORCE=12, the badge clicked, the button clicked, and the
# answer read from `hyprctl clients -j`. `koompi` is a shadow that records its
# arguments. UPDATE_SHOT=<path> keeps the nested screen after the click, with
# <path>-popup.png from just before it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in qs kwin_wayland Hyprland hyprctl dbus-run-session jq grim; do
    command -v "$tool" >/dev/null 2>&1 || { echo "skip: $tool not installed, nothing to run Update now in"; exit 0; }
done
terminal=""
for t in wezterm foot kitty alacritty konsole kgx uxterm xterm; do
    command -v "$t" >/dev/null 2>&1 && { terminal="$t"; break; }
done
[[ -n "$terminal" ]] || { echo "skip: no terminal installed, Update now has nothing to open"; exit 0; }

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
# socket paths must fit 108 bytes, so the runtime dir is short
RUN="$(mktemp -d /tmp/hr.XXXXXX)" || { fail "mktemp -d /tmp/hr failed"; exit 1; }
trap '(( failed )) && echo "kept $WORK and $RUN" >&2 || rm -rf "$WORK" "$RUN"' EXIT
mkdir -p "$WORK/shell" "$WORK/home/.config/hypr" "$WORK/xdg/config/koompi" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/bin"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
cat > "$WORK/bin/koompi" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/koompi.ran"
echo "fake update"
SH
chmod +x "$WORK/bin"/*

cat > "$WORK/home/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true } })
LUA

cat > "$WORK/shell/update_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs.modules.koompi.bar

ShellRoot {
    id: probe
    property int ticks: 0
    property int stage: 0

    Bar { id: bar }

    function findNamed(obj, name) {
        if (obj.objectName === name) return obj;
        const list = obj.data;
        for (let i = 0; list && i < list.length; i++) {
            const found = probe.findNamed(list[i], name);
            if (found) return found;
        }
        return null;
    }

    function popupButton() {
        const win = bar.focusedBarWindow();
        return probe.findNamed(probe.findNamed(win.contentItem, "updatesPopup").item.contentItem, "updateNow");
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
            const badge = probe.findNamed(win.contentItem, "updateBadge");
            const popup = probe.findNamed(win.contentItem, "updatesPopup");
            if (!badge || !popup) return;

            if (probe.stage === 0) {
                if (!badge.visible || badge.width < 24) return;
                badge.click();
                probe.stage = 1;
            } else if (probe.stage === 1) {
                const button = popup.item ? probe.findNamed(popup.item.contentItem, "updateNow") : null;
                if (!button) return;
                console.log("PASS updates popup open with an Update now button");
                Quickshell.execDetached(["grim", Quickshell.env("PROBE_OUT") + "/popup.png"]);
                probe.stage = 2;
            } else if (probe.stage === 2) {
                probe.popupButton().click();
                probe.stage = 3;
            } else if (probe.stage === 3) {
                if (popup.active) return;
                console.log("PASS Update now closed the popup");
                console.log("PROBE DONE");
                Qt.quit();
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
parent=\$WAYLAND_DISPLAY
Hyprland -c "$WORK/home/.config/hypr/hyprland.lua" > "$WORK/hyprland.log" 2>&1 &
for _ in \$(seq 1 100); do sig=\$(ls "$RUN/hypr" 2>/dev/null | head -1); [[ -n "\$sig" ]] && break; sleep 0.2; done
export HYPRLAND_INSTANCE_SIGNATURE=\$sig
for _ in \$(seq 1 100); do d=\$(ls "$RUN" | grep -E '^wayland-[0-9]+\$' | grep -v "^\$parent\$" | head -1); [[ -n "\$d" ]] && break; sleep 0.2; done
export WAYLAND_DISPLAY=\$d
for _ in \$(seq 1 100); do hyprctl monitors -j 2>/dev/null | jq -e 'length > 0' >/dev/null 2>&1 && break; sleep 0.2; done
cd "$WORK/shell"
qs -p "$WORK/shell/update_probe.qml" > "$WORK/qs.log" 2>&1 &
qs_pid=\$!
for _ in \$(seq 1 120); do grep -q -e 'PROBE DONE' -e 'qml: FAIL' "$WORK/qs.log" && break; sleep 0.5; done
for _ in \$(seq 1 120); do
    hyprctl clients -j > "$WORK/clients.json" 2>&1
    jq -e 'length > 0' "$WORK/clients.json" >/dev/null 2>&1 && break
    sleep 0.5
done
sleep 1
hyprctl clients -j > "$WORK/clients.json" 2>&1
grim "$WORK/screen.png" 2> "$WORK/grim.log"
hyprctl dispatch "hl.dsp.exit()" > /dev/null 2>&1
kill "\$qs_pid" 2>/dev/null
sleep 1
SH
chmod +x "$WORK/inner.sh"

# QT_QPA_PLATFORM=wayland on purpose: see test_bar_keys.sh
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY -u XDG_CURRENT_DESKTOP \
    HOME="$WORK/home" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$WORK/xdg/config" \
    XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    PATH="$WORK/bin:$PATH" PROBE_OUT="$WORK" KOOMPI_UPDATES_FORCE=12 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" \
    QT_QPA_PLATFORM=wayland \
    timeout 200 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 --no-lockscreen \
        --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log" 2>/dev/null)"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -30 >&2
    fail "the probe did not click through to Update now"
fi

if jq -e 'type == "array"' "$WORK/clients.json" >/dev/null 2>&1; then
    n="$(jq 'length' "$WORK/clients.json")"
    if (( n == 0 )); then
        fail "Update now opened no window (hyprctl clients is empty)"
    else
        jq -r '.[] | "client: \(.class) floating=\(.floating) size=\(.size[0])x\(.size[1]) at=\(.at[0]),\(.at[1])"' "$WORK/clients.json"
        jq -e 'any(.[]; .floating == true)' "$WORK/clients.json" >/dev/null 2>&1 \
            || fail "Update now opened a window but it is not floating"
    fi
else
    cat "$WORK/clients.json" >&2
    fail "hyprctl clients -j did not answer in the nested Hyprland"
fi
grep -qx 'update' "$WORK/koompi.ran" 2>/dev/null \
    || fail "the terminal never ran 'koompi update' (koompi.ran: $(cat "$WORK/koompi.ran" 2>/dev/null || echo missing))"
if [[ -n "${UPDATE_SHOT:-}" && -s "$WORK/screen.png" ]]; then
    cp "$WORK/screen.png" "$UPDATE_SHOT"
    [[ -s "$WORK/popup.png" ]] && cp "$WORK/popup.png" "${UPDATE_SHOT%.png}-popup.png"
    echo "     screens at $UPDATE_SHOT and ${UPDATE_SHOT%.png}-popup.png"
fi
(( failed )) || echo "ok   Update now opened a floating $terminal window that ran 'koompi update', through the Lua dispatch"
exit $failed
