#!/usr/bin/env bash
# A pinned side panel is docked, not a popup: it takes no keyboard until it is clicked, Esc inside it closes
# nothing, and a click outside leaves it open. Unpinned, it keeps taking the keyboard and a click away closes it.
# The left sidebar and the right panel, real surfaces in Hyprland nested in headless KWin, a virtual pointer.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
HYPR="$REPO_ROOT/dots/.config/hypr"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session python3; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nested Hyprland not run"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$(mktemp -d /tmp/ppf.XXXXXX)"
trap 'rm -rf "$WORK" "$RUN"' EXIT
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$WORK/bin" "$WORK/shell"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$HOME_DIR/.config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld" && chmod +x "$WORK/bin/koompi-shelld"
for entry in "$SHELL_ROOT"/*; do ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"; done

cp -r -- "$HYPR/hyprland" "$HOME_DIR/.config/hypr/hyprland"
printf 'hl.on("hyprland.start", function() end)\n' > "$HOME_DIR/.config/hypr/hyprland/execs.lua"
grep -v 'custom\.' "$HYPR/hyprland.lua" > "$HOME_DIR/.config/hypr/hyprland.lua"
cat >> "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1200", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

cat > "$WORK/shell/pin_probe.qml" <<'QML'
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.sidebarLeft
import qs.modules.koompi.sidebarRight
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    SidebarLeft { id: left }
    SidebarRight { id: right }

    function panelOf(side) { return side === "left" ? left.panel : right.panel; }
    function listed(side) { return GlobalFocusGrab.dismissable.indexOf(panelOf(side)) >= 0; }
    function mode(side) {
        const m = panelOf(side)?.WlrLayershell.keyboardFocus;
        return m === WlrKeyboardFocus.None ? "none" : m === WlrKeyboardFocus.OnDemand ? "ondemand" : "other";
    }

    IpcHandler {
        target: "probe"
        function ping(): int { return 1; }
        function pin(side: string, on: bool): void {
            if (side === "left") left.pin = on;
            else Persistent.states.sidebar.pinned = on;
        }
        function esc(side: string): void { if (side === "left") left.panel.hide(); else right.hide(); }
        function state(side: string): string {
            const open = side === "left" ? GlobalStates.sidebarLeftOpen : GlobalStates.sidebarRightOpen;
            return `open=${open} focus=${mode(side)} listed=${listed(side)}`;
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
log() { printf '%s\n' "$*" >> "$WORK/readings"; }

source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || { log "dead nested Hyprland did not start"; exit 0; }

cd "$WORK/shell" || exit 1
qs -p pin_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
call() { qs -p pin_probe.qml ipc call "$@" 2> /dev/null < /dev/null; }
for _ in $(seq 1 80); do call probe ping > /dev/null && break; sleep 0.5; done
sleep 3

click() { python3 "$REPO_ROOT/tests/wl_virtual_click.py" 1920 1200 "$1" "$2" >> "$WORK/click.log" 2>&1; sleep 1.5; }

# click points: inside each panel, and on empty desktop
declare -A INSIDE=([left]="150 600" [right]="1700 600")
declare -A OUTSIDE=([left]="1000 1150" [right]="1000 1150")
for side in left right; do
    ipc_target=sidebar${side^}
    call "$ipc_target" open > /dev/null; sleep 2
    log "$side unpinned open: $(call probe state "$side")"
    call probe pin "$side" true; sleep 1
    log "$side pinned: $(call probe state "$side")"
    call probe esc "$side"; sleep 1
    log "$side pinned after Esc: $(call probe state "$side")"
    click ${OUTSIDE[$side]}
    log "$side pinned after click outside: $(call probe state "$side")"
    click ${INSIDE[$side]}
    log "$side pinned after click inside: $(call probe state "$side")"
    call probe pin "$side" false; sleep 1
    log "$side unpinned again: $(call probe state "$side")"
    click ${OUTSIDE[$side]}
    log "$side unpinned after click outside: $(call probe state "$side")"
    call "$ipc_target" close > /dev/null; sleep 1
done

kill "$qs_pid" 2> /dev/null
cp "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log "$WORK/hyprland-run.log" 2> /dev/null
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
log done
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" \
    REPO_ROOT="$REPO_ROOT" HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 2120 --height 1400 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

dump() {
    echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null
    echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2
}

grep -q '^dead' "$WORK/readings" 2> /dev/null && { dump; fail "setup: the nested Hyprland did not start"; }
grep -q '^done$' "$WORK/readings" 2> /dev/null || { dump; fail "setup: the probe session did not finish"; }

failed=0
expect() {
    local label=$1 want=$2
    if grep -qF -- "$label: $want" "$WORK/readings"; then
        echo "ok   $label: $want"
    else
        printf 'FAIL: %s: wanted "%s", got "%s"\n' "$label" "$want" "$(grep -F -- "$label:" "$WORK/readings" | head -1)" >&2
        failed=1
    fi
}
for side in left right; do
    expect "$side unpinned open" "open=true focus=ondemand listed=true"
    expect "$side pinned" "open=true focus=none listed=false"
    expect "$side pinned after Esc" "open=true focus=none listed=false"
    expect "$side pinned after click outside" "open=true focus=none listed=false"
    expect "$side pinned after click inside" "open=true focus=ondemand listed=false"
    expect "$side unpinned again" "open=true focus=ondemand listed=true"
    expect "$side unpinned after click outside" "open=false"
done
(( failed == 0 )) || { dump; exit 1; }
