#!/usr/bin/env bash
# J53: the quick settings head the one right panel. The real SidebarRight in a probe shell, Hyprland nested in a
# headless KWin on a private bus (1366x768), real keys through wtype. It reads back, over IPC:
#   - the Control Center rows and the notification groups in one panel, in that order, and no quickshell:controlCenter layer
#   - the first notification group on screen without scrolling at 1366x768
#   - `controlCenter module wifi` opens the panel with the Wi-Fi list expanded
#   - a click or Enter on a row with choices expands its list and does not flip it; its switch flips it
#   - one list open at a time; Escape folds the open list, a second Escape closes the panel
#   - Space on Do Not Disturb flips Notifications.silent and the row reads On
#   - the Edit page adds an optional module to the list, and it is stored in controlCenter.extraModules
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
CC="$SHELL_ROOT/modules/koompi/controlCenter"
SR="$SHELL_ROOT/modules/koompi/sidebarRight"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -e "$CC/ControlCenter.qml" ]] && fail "the standalone Control Center window still exists"
grep -rqF 'quickshell:controlCenter' "$SHELL_ROOT" "$REPO_ROOT/dots/.config/hypr" && fail "something still names the quickshell:controlCenter layer"
grep -rq 'controlCenterOpen' "$SHELL_ROOT" && fail "controlCenterOpen still exists; nothing may open a second panel"
grep -q 'ControlCenter {}' "$SHELL_ROOT/panelFamilies/KoompiFamily.qml" && fail "KoompiFamily still loads a Control Center"
grep -q 'target: "controlCenter"' "$SR/SidebarRight.qml" || fail "the controlCenter IPC alias is gone"
grep -q 'name: "controlCenterToggle"' "$SR/SidebarRight.qml" || fail "the controlCenterToggle shortcut alias is gone"
grep -qF 'SUPER + ALT + N' "$REPO_ROOT/dots/.config/hypr/hyprland/keybinds.lua" && fail "Super+Alt+N is still bound"
echo "ok   source: no standalone layer, no controlCenterOpen, IPC and shortcut kept as aliases of the one panel, no Super+Alt+N"

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq wtype; do
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
hl.monitor({ output = "", mode = "1366x768", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/easyeffects"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/cc_probe.qml" <<'QML'
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

    property int wifiFlips: 0

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
    function named(name) {
        return all().find(i => i.objectName === name) ?? null;
    }
    function rows() {
        return all().filter(i => /^cc-(extra-)?[A-Za-z]+$/.test(i.objectName ?? "") && !/^cc-(output|input)$/.test(i.objectName) && i.visible)
            .sort((a, b) => {
                const pa = a.mapToItem(sr.content, 0, 0), pb = b.mapToItem(sr.content, 0, 0);
                return Math.round(pa.y) - Math.round(pb.y) || pa.x - pb.x;
            });
    }
    function y(item) {
        return item ? Math.round(item.mapToItem(sr.content.body.contentItem, 0, 0).y) : -1;
    }

    IpcHandler {
        target: "probe"

        function modules(): string {
            return rows().map(r => r.objectName).join(",");
        }
        function words(): string {
            return rows().filter(r => r.hasToggle && !r.hasSwitch).map(r => `${r.objectName}=${r.stateWord}`).join(",");
        }
        function order(): string {
            const first = all().find(i => (i.objectName ?? "").startsWith("nc-group-") && i.visible);
            return `wifi<group:${y(named("cc-wifi")) < y(first)} group<upnext:${y(first) < y(named("w-upnext"))} edit<group:${y(named("cc-edit")) < y(first)}`;
        }
        function grid(): string {
            const p = n => named(n);
            const same = (a, b) => y(p(a)) === y(p(b));
            return `dnd|keep:${same("cc-dnd", "cc-keepAwake") && p("cc-dnd").x < p("cc-keepAwake").x} night|dark:${same("cc-nightLight", "cc-darkMode") && p("cc-nightLight").x < p("cc-darkMode").x} dnd<night:${y(p("cc-dnd")) < y(p("cc-nightLight"))} sound<dnd:${y(p("cc-sound")) < y(p("cc-dnd"))} sliders<:${y(p("cc-nightLight")) < y(p("cc-brightness")) && y(p("cc-brightness")) < y(p("cc-volume"))}`;
        }
        function wifiList(): string {
            const list = named("cc-list-wifi");
            const wifi = named("cc-wifi");
            const head = sr.content.head;
            return `fullWidth=${list.width >= head.width - 1} below=${y(list) >= y(wifi) + wifi.height - 1} pushes=${y(named("cc-sound")) >= y(list) + list.height - 1}`;
        }
        function firstGroup(): string {
            const g = all().find(i => (i.objectName ?? "").startsWith("nc-group-") && i.visible);
            if (!g) return "none";
            const body = sr.content.body;
            const bottom = y(g) + g.height - body.contentY;
            return `scrolled=${Math.round(body.contentY)} bottomGap=${Math.round(body.height - bottom)} fits=${bottom <= body.height && y(g) >= body.contentY}`;
        }
        function focused(): string {
            const item = sr.content?.Window.window?.activeFocusItem;
            return item ? (item.objectName || `${item}`.replace(/_QMLTYPE.*/, "")) : "none";
        }
        function expanded(): string {
            return `[${sr.content?.head.expanded}] open=${GlobalStates.sidebarRightOpen} drawer=[${sr.content?.drawer}]`;
        }
        function watch(): void {
            named("cc-wifi").activated.connect(() => wifiFlips++);
        }
        function word(name: string): string {
            return named(name)?.stateWord ?? "missing";
        }
        function flips(): string {
            return `${wifiFlips}`;
        }
        function click(name: string): void {
            const item = named(name);
            if (item.activate) item.activate(); else if (item.opened) item.opened(); else item.clicked();
        }
        function flags(): string {
            return `sidebar=${GlobalStates.sidebarRightOpen} silent=${Notifications.silent}`;
        }
        function extras(): string {
            return Config.options.controlCenter.extraModules.join(",");
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
qs -p cc_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p cc_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done
sleep 4
call() { qs -p cc_probe.qml ipc call "$@" 2> /dev/null; }
note() { printf '%s %s\n' "$1" "$2" >> "$WORK/readings"; }
# wtype's first keysym takes Escape's keycode, so a throwaway Shift goes first
keys() { wtype -k Shift_R "$@"; sleep 0.8; }

for app in alpha beta alpha gamma; do
    notify-send -a "$app" "$app note" "body"
done
sleep 1.5
call sidebarRight open
sleep 2.5
note modules "$(call probe modules)"
note words "$(call probe words)"
note order "$(call probe order)"
note grid "$(call probe grid)"
note group_fit "$(call probe firstGroup)"
note layers "$(hyprctl layers -j | jq -r '[.. | .namespace? // empty] | sort | join(",")')"
note focus_open "$(call probe focused)"

call probe watch
keys -k Down
note focus_down "$(call probe focused)"
keys -k Down
note focus_down2 "$(call probe focused)"
keys -k space
note dnd_after_space "$(call probe word cc-dnd) $(call probe flags)"
keys -k space
note dnd_after_second_space "$(call probe flags)"
keys -k Right
note focus_right "$(call probe focused)"
keys -k Down
note focus_grid_down "$(call probe focused)"
keys -k Left
note focus_left "$(call probe focused)"
keys -k Up
keys -k Up
keys -k Up
note focus_up "$(call probe focused)"

keys -k Return
note wifi_enter "$(call probe expanded) flips=$(call probe flips)"
keys -k Tab
note wifi_tab "$(call probe focused)"
keys -k space
note wifi_space "flips=$(call probe flips)"
keys -k Escape
note wifi_escape "$(call probe expanded)"
keys -k Escape
sleep 0.5
note panel_escape "$(call probe expanded)"

call controlCenter module wifi
sleep 1.5
note module_wifi "$(call probe expanded)"
note wifi_list "$(call probe wifiList)"
call probe click cc-sound
sleep 0.8
note one_at_a_time "$(call probe expanded)"
keys -k Escape
sleep 0.5
note sound_escape "$(call probe expanded)"
keys -k Escape
sleep 0.5

call controlCenter open
sleep 1.5
call probe click cc-edit
sleep 1.2
note edit_focus "$(call probe focused) $(call probe expanded)"
keys -k Down -k Space
sleep 1
note edit_stored "$(call probe extras)"
keys -k Escape
sleep 1
note modules_after_edit "$(call probe modules)"
call controlCenter close

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
    timeout 240 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1366 --height 768 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }
expect() { # $1: reading, $2: wanted, $3: what it proves
    [[ "$(reading "$1")" == "$2" ]] || { dump; fail "$3: got '$(reading "$1")', wanted '$2'"; }
}

[[ -s "$WORK/readings" ]] || { dump; fail "setup: the probe recorded nothing"; }

expect modules "cc-edit,cc-wifi,cc-sound,cc-extra-powerProfile,cc-dnd,cc-keepAwake,cc-nightLight,cc-darkMode,cc-brightness,cc-volume" \
    "the rows, in order, with Bluetooth, Battery and Now Playing absent"
expect words "cc-extra-powerProfile=,cc-dnd=Off,cc-keepAwake=Off,cc-nightLight=Off,cc-darkMode=On" "every plain toggle states On or Off in words"
echo "ok   probe: the Control Center rows lead the one panel, toggles read On or Off in words"
expect grid "dnd|keep:true night|dark:true dnd<night:true sound<dnd:true sliders<:true" "tiles in pairs, then the sliders"
echo "ok   probe: Do Not Disturb | Keep awake and Night Light | Dark mode in pairs, Sound above them, the sliders below"
expect order "wifi<group:true group<upnext:true edit<group:true" "rows, then notification groups, then the cards"
expect layers "quickshell:sidebarRight" "the layers: the panel is one, and no controlCenter layer"
echo "ok   probe: rows, groups and cards in that order on one layer; no quickshell:controlCenter"
group_fit="$(reading group_fit)"
[[ "$group_fit" == *"scrolled=0"*"fits=true" ]] || { dump; fail "the first notification group is not on screen unscrolled at 1366x768: '$group_fit'"; }
echo "ok   probe: the first notification group is on screen without scrolling at 1366x768 ($group_fit)"
expect focus_open "cc-wifi" "the first row takes the keyboard when the panel opens"
expect focus_down "cc-sound" "Down moves to the tile below"
expect focus_down2 "cc-dnd" "Down again"
expect focus_right "cc-keepAwake" "Right moves across the pair"
expect focus_grid_down "cc-darkMode" "Down from the right column stays in it"
expect focus_left "cc-nightLight" "Left moves back across the pair"
expect dnd_after_space "On sidebar=true silent=true" "Space on Do Not Disturb"
expect dnd_after_second_space "sidebar=true silent=false" "Space on Do Not Disturb again"
expect focus_up "cc-wifi" "Up goes back to Wi-Fi"
echo "ok   probe: opens on Wi-Fi, Down lands on Do Not Disturb, Space flips it"
expect wifi_enter "[wifi] open=true drawer=[] flips=0" "Enter on the Wi-Fi row expands its list and does not flip Wi-Fi"
expect wifi_tab "cc-wifi-switch" "Tab from the row reaches its switch"
expect wifi_space "flips=1" "Space on the switch flips Wi-Fi"
expect wifi_escape "[] open=true drawer=[]" "Escape folds the open list first"
expect panel_escape "[] open=false drawer=[]" "a second Escape closes the panel"
echo "ok   probe: Enter expands, Tab reaches the switch, Space flips only there; Escape folds, Escape closes"
expect module_wifi "[wifi] open=true drawer=[]" "controlCenter module wifi"
expect wifi_list "fullWidth=true below=true pushes=true" "the Wi-Fi list is full width under its row and pushes the rows below down"
expect one_at_a_time "[sound] open=true drawer=[]" "opening Sound folds Wi-Fi"
expect sound_escape "[] open=true drawer=[]" "Escape folds the Sound list"
echo "ok   probe: module wifi opens the panel on the Wi-Fi list; one list open at a time"
expect edit_focus "drawer-back [] open=true drawer=[edit]" "the Edit page opens over the panel"
expect edit_stored "screenRecord" "a checked module is stored in controlCenter.extraModules"
expect modules_after_edit "cc-edit,cc-wifi,cc-sound,cc-extra-powerProfile,cc-dnd,cc-keepAwake,cc-nightLight,cc-darkMode,cc-extra-screenRecord,cc-brightness,cc-volume" "the module chosen in Edit"
echo "ok   probe: Edit lists the optional modules, Space shows one, and it joins the list above Edit"
