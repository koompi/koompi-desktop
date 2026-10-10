#!/usr/bin/env bash
# J21: the right panel is the Notification Center. The real SidebarRight in a probe shell, Hyprland nested in a
# headless KWin on a private bus, notifications sent with notify-send, real keys through wtype. It reads back:
#   - two app groups (two notifications each), each with a clear button, and clearing one removes only that group
#   - one collapsed System group whose row reads "Memory shortage avoided x6", from two senders
#   - no quick toggles or sliders in the panel, and the widgets in order: Up next, Weather, To-do, Timer
#   - Tab reaches a group, Enter expands it, Delete clears it, Escape closes the panel
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SR="$SHELL_ROOT/modules/koompi/sidebarRight"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -qE 'QuickSliders|QuickPanel|sidebarRightControls|ChargeLimitRow' "$SR/SidebarRightContent.qml" "$SR/SidebarRight.qml" \
    && fail "the panel still names the quick sliders, toggles or controls page"
grep -q 'systemApps' "$SHELL_ROOT/modules/common/Config.qml" || fail "Config has no notifications.systemApps"
echo "ok   source: no controls in the panel, notifications.systemApps exists"

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq wtype notify-send; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
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

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/easyeffects"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/nc_probe.qml" <<'QML'
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.sidebarRight
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    SidebarRight {
        id: sr
    }
    Component.onCompleted: void Notifications.silent

    function walk(item, out, seen) {
        if (!item || seen.has(item)) return;
        seen.add(item);
        out.push(item);
        for (const child of item.children ?? []) walk(child, out, seen);
        if (item.contentItem) walk(item.contentItem, out, seen);
    }
    function all() {
        const out = [];
        walk(sr.content, out, new Set());
        return out;
    }
    function named(prefix) {
        return all().filter(i => (i.objectName ?? "").startsWith(prefix) && i.visible);
    }

    IpcHandler {
        target: "probe"

        function groups(): string {
            return named("nc-group-").map(g => `${g.objectName.slice(9)}:${g.notificationCount}:${named("nc-clear-" + g.objectName.slice(9)).length}`).join(",");
        }
        function system(): string {
            const g = named("nc-system")[0];
            if (!g) return "none";
            return `${named("nc-system").length} expanded=${g.expanded} rows=${named("nc-sysrow-").map(r => r.label).join("|")}`;
        }
        function controls(): string {
            return `${all().filter(i => /QuickToggle|QuickSliders|QuickPanel/.test(`${i}`)).length}`;
        }
        function order(): string {
            return named("w-").sort((a, b) => a.mapToItem(sr.content, 0, 0).y - b.mapToItem(sr.content, 0, 0).y).map(w => w.objectName).join(",");
        }
        function clear(app: string): void {
            named("nc-clear-" + app)[0]?.clicked();
        }
        function focused(): string {
            const item = sr.content?.Window.window?.activeFocusItem;
            return item ? (item.objectName || `${item}`.replace(/_QMLTYPE.*/, "")) : "none";
        }
        function expanded(app: string): string {
            return `${named("nc-group-" + app)[0]?.expanded}`;
        }
        function open(): string {
            return `${GlobalStates.sidebarRightOpen}`;
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
qs -p nc_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p nc_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done
sleep 4
call() { qs -p nc_probe.qml ipc call "$@" 2> /dev/null; }
note() { printf '%s %s\n' "$1" "$2" >> "$WORK/readings"; }
keys() { wtype -k Shift_R "$@"; sleep 0.8; }

for app in alpha beta; do
    notify-send -a "$app" "$app one" "first"
    notify-send -a "$app" "$app two" "second"
done
for _ in 1 2 3; do
    notify-send -a "Linux Kernel" -h string:x-kde-appname:oom_notifier "Memory shortage avoided" "The system freed memory"
    notify-send -a KOOMPI "Memory shortage avoided" "The system freed memory"
done
sleep 1.5
call sidebarRight open
sleep 2.5
note groups "$(call probe groups)"
note system "$(call probe system)"
note controls "$(call probe controls)"
note order "$(call probe order)"

call probe clear alpha
sleep 1.5
note groups_after_clear "$(call probe groups)"

notify-send -a alpha "alpha again" "back"
sleep 1
keys -k Tab
note focus_tab "$(call probe focused)"
keys -k Return
note expanded_after_enter "$(call probe expanded alpha)"
keys -k Delete
sleep 1
note groups_after_delete "$(call probe groups)"
keys -k Escape
sleep 0.8
note open_after_escape "$(call probe open)"

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
    timeout 240 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }
expect() { [[ "$(reading "$1")" == "$2" ]] || { dump; fail "$3: got '$(reading "$1")', wanted '$2'"; }; }

[[ -s "$WORK/readings" ]] || { dump; fail "setup: the probe recorded nothing"; }

expect groups "beta:2:1,alpha:2:1" "two app groups with a clear button each, newest first"
expect system "1 expanded=false rows=Memory shortage avoided x6" "one collapsed System group, identical rows counted"
echo "ok   probe: two app groups with a clear each; one collapsed System group reading x6"
expect controls "0" "quick toggles and sliders in the panel"
expect order "w-upnext,w-weather,w-todo,w-timer" "the widget order"
echo "ok   probe: no quick toggles; Up next, Weather, To-do, Timer in order"
expect groups_after_clear "beta:2:1" "clearing alpha"
echo "ok   probe: clearing one group leaves the other"
expect focus_tab "nc-group-alpha" "Tab reaches a group"
expect expanded_after_enter "true" "Enter expands the focused group"
expect groups_after_delete "beta:2:1" "Delete clears the focused group"
expect open_after_escape "false" "Escape closes the panel"
echo "ok   probe: Tab, Enter, Delete and Escape work from the keyboard"
