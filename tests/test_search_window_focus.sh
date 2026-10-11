#!/usr/bin/env bash
# Picking a window in Search must focus it. This Hyprland reads a Lua config, where
# `hyprctl dispatch "focuswindow address:0x..."` is refused (rc 7) and
# Hyprland.dispatch from QML drops the refusal silently, so the old row did nothing.
#
# Live: Hyprland nested in a headless KWin on a private bus with a minimal Lua config.
# A probe shell opens two windows, the second takes focus, and the probe runs the
# execute() of the first window's real LauncherSearch.windowResults row. The pass
# condition is hyprctl's own activewindow, not an exit code. koompi-shelld is a PATH
# shim that feeds HyprlandData the nested compositor's `clients -j`, so the rows are
# built from real addresses. Nothing here reaches the running session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SEARCH="$SHELL_ROOT/services/launcherSearch/WindowRows.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'hl\.dsp\.focus({ window = "address:' "$SEARCH" || fail "the window row does not dispatch hl.dsp.focus"
grep -q 'focuswindow' "$SEARCH" && fail "LauncherSearch still dispatches the legacy focuswindow"
echo "ok   source: the window row dispatches hl.dsp.focus, no legacy focuswindow"

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

# the daemon's wire format is shell-services/shelld/PROTOCOL.md: a hello, then state
# pushes; windows is `hyprctl clients -j` field for field
cat > "$WORK/bin/koompi-shelld" <<'SH'
#!/usr/bin/env bash
printf '{"type":"hello","protocol":1}\n'
while sleep 0.3; do
    printf '{"type":"state","service":"hyprland","state":{"windows":%s}}\n' "$(hyprctl clients -j | jq -c .)" || exit 0
done
SH
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/focus_probe.qml" <<'QML'
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    FloatingWindow {
        title: "focus-probe-a"
        visible: true
    }
    FloatingWindow {
        id: second
        title: "focus-probe-b"
        visible: false
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: second.visible = true
    }

    IpcHandler {
        target: "probe"

        function pick(title: string): string {
            const row = LauncherSearch.windowResults("").find(r => r.name === title);
            if (!row)
                return "missing";
            row.execute();
            return "executed";
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
qs -p focus_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p focus_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done

active() { hyprctl activewindow -j 2> /dev/null | jq -r '.title // ""'; }
for _ in $(seq 1 60); do [[ $(active) == focus-probe-b ]] && break; sleep 0.5; done
echo "before $(active)" >> "$WORK/readings"

for _ in $(seq 1 40); do
    r=$(qs -p focus_probe.qml ipc call probe pick focus-probe-a 2> /dev/null)
    [[ $r == executed ]] && break
    sleep 0.5
done
echo "pick ${r:-none}" >> "$WORK/readings"
for _ in $(seq 1 20); do [[ $(active) == focus-probe-a ]] && break; sleep 0.25; done
echo "after $(active)" >> "$WORK/readings"

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
    timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }

[[ "$(reading before)" == focus-probe-b ]] || { dump; fail "setup: the second window did not take focus first, got '$(reading before)'"; }
[[ "$(reading pick)" == executed ]] || { dump; fail "setup: Search never listed the first window, pick said '$(reading pick)'"; }
[[ "$(reading after)" == focus-probe-a ]] || { dump; fail "picking the first window in Search left focus on '$(reading after)'"; }
echo "ok   probe: Search's window row moved hyprctl activewindow from focus-probe-b to focus-probe-a"
