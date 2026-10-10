#!/usr/bin/env bash
# J20: the Control Center. The real ControlCenter in a probe shell, Hyprland nested in a headless KWin on a
# private bus, real keys through wtype. It reads back, over IPC:
#   - the fixed modules, in order, and Battery absent when Battery.available is false
#   - every toggle reading "On" or "Off" in words
#   - Space on Do Not Disturb flips Notifications.silent and the row reads On
#   - module("wifi") shows the network page; Escape goes back to the list; Escape again closes
#   - the Edit page adds an optional module to the list, and it is stored in controlCenter.extraModules
#   - opening the Control Center closes the right panel, and opening the right panel closes it
#   - Reduce Motion takes the page slide away (a crossfade is all that is left)
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
CC="$SHELL_ROOT/modules/koompi/controlCenter"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$CC/ControlCenter.qml" ]] || fail "modules/koompi/controlCenter/ControlCenter.qml does not exist"
grep -q 'namespace: "quickshell:controlCenter"' "$CC/ControlCenter.qml" || fail "the layer namespace is not quickshell:controlCenter"
grep -q 'name: "controlCenterToggle"' "$CC/ControlCenter.qml" || fail "no controlCenterToggle GlobalShortcut"
grep -q 'target: "controlCenter"' "$CC/ControlCenter.qml" || fail "no controlCenter IPC target"
grep -q 'GlobalFocusGrab.addDismissable' "$CC/ControlCenter.qml" || fail "the window does not register with GlobalFocusGrab"
grep -q 'WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None' "$CC/ControlCenter.qml" || fail "keyboard focus is not gated on controlCenterOpen"
grep -q 'PanelLoader { component: ControlCenter {} }' "$SHELL_ROOT/panelFamilies/KoompiFamily.qml" || fail "KoompiFamily does not load the Control Center"
echo "ok   source: namespace, shortcut, IPC target, focus grab, gated keyboard focus, family entry"

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
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/easyeffects"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/cc_probe.qml" <<'QML'
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.controlCenter
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    ControlCenter {
        id: cc
    }

    function rows() {
        const out = [];
        const column = cc.content?.mainPage.column;
        for (const child of column?.children ?? []) {
            const row = child.objectName ? child : child.item;
            if (row && row.objectName)
                out.push(row);
        }
        return out;
    }

    function row(name) {
        return rows().find(r => r.objectName === name) ?? null;
    }

    IpcHandler {
        target: "probe"

        function modules(): string {
            return rows().map(r => r.objectName).join(",");
        }
        function words(): string {
            return rows().filter(r => r.hasToggle && r.visible).map(r => `${r.objectName}=${r.stateWord}`).join(",");
        }
        function word(name: string): string {
            return row(name)?.stateWord ?? "missing";
        }
        function focused(): string {
            const item = cc.content?.Window.window?.activeFocusItem;
            return item ? (item.objectName || `${item}`.replace(/_QMLTYPE.*/, "")) : "none";
        }
        function page(): string {
            return cc.content ? `[${cc.content.page}]` : "[nocontent]";
        }
        function pageType(): string {
            return `${cc.content?.body.item}`.replace(/_QMLTYPE.*/, "");
        }
        function flags(): string {
            return `cc=${GlobalStates.controlCenterOpen} sidebar=${GlobalStates.sidebarRightOpen} silent=${Notifications.silent}`;
        }
        function sidebar(open: bool): void {
            GlobalStates.sidebarRightOpen = open;
        }
        function extras(): string {
            return Config.options.controlCenter.extraModules.join(",");
        }
        function slide(): string {
            return `${cc.content?.slide}`;
        }
        function reduceMotion(on: bool): void {
            Config.options.appearance.reduceMotion = on;
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

call controlCenter open
sleep 2
note modules "$(call probe modules)"
note words "$(call probe words)"
note focus_open "$(call probe focused)"

keys -k Down
note focus_down1 "$(call probe focused)"
keys -k space
note dnd_after_space "$(call probe word cc-dnd) $(call probe flags)"
keys -k space
note dnd_after_second_space "$(call probe word cc-dnd) $(call probe flags)"

call controlCenter module wifi
sleep 1.5
note wifi_page "$(call probe page) $(call probe pageType)"
keys -k Escape
sleep 0.5
note wifi_escape "$(call probe page) $(call probe flags)"
keys -k Escape
sleep 0.5
note main_escape "$(call probe flags)"

call controlCenter open
sleep 1.5
keys -k Right
sleep 1
note right_opens "$(call probe page) $(call probe pageType)"
keys -k BackSpace
sleep 0.5
note backspace_back "$(call probe page) $(call probe focused)"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do keys -k Down; [[ $(call probe focused) == cc-edit ]] && break; done
note focus_edit "$(call probe focused)"
keys -k Return
sleep 1
note edit_page "$(call probe page)"
keys -k Down -k Space
sleep 1
note edit_stored "$(call probe extras)"
keys -k Escape
sleep 0.8
note modules_after_edit "$(call probe modules)"
keys -k Escape
sleep 0.5

call probe sidebar true
sleep 0.5
call controlCenter open
sleep 1
note open_closes_sidebar "$(call probe flags)"
call probe sidebar true
sleep 0.5
note sidebar_closes_cc "$(call probe flags)"
call probe sidebar false

call controlCenter open
sleep 1
note slide_default "$(call probe slide)"
call probe reduceMotion true
sleep 0.5
note slide_reduced "$(call probe slide)"

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

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }
expect() { # $1: reading, $2: wanted, $3: what it proves
    [[ "$(reading "$1")" == "$2" ]] || { dump; fail "$3: got '$(reading "$1")', wanted '$2'"; }
}

[[ -s "$WORK/readings" ]] || { dump; fail "setup: the probe recorded nothing"; }

expect modules "cc-wifi,cc-bluetooth,cc-dnd,cc-keepAwake,cc-brightness,cc-nightLight,cc-darkMode,cc-sound,cc-edit" \
    "the fixed modules, in order, with Battery and Now Playing absent"
echo "ok   probe: Wi-Fi, Bluetooth, Do Not Disturb, Keep awake, Display, Sound, Edit in order; no Battery without a battery"
expect words "cc-wifi=Off,cc-dnd=Off,cc-keepAwake=Off,cc-nightLight=Off,cc-darkMode=On" "every toggle states On or Off in words"
echo "ok   probe: every toggle row reads On or Off in words"
expect focus_open "cc-wifi" "the first module takes the keyboard when the panel opens"
expect focus_down1 "cc-dnd" "Down moves to the next visible module"
echo "ok   probe: opens on Wi-Fi, Down lands on Do Not Disturb (the hidden Bluetooth is skipped)"
expect dnd_after_space "On cc=true sidebar=false silent=true" "Space on Do Not Disturb"
expect dnd_after_second_space "Off cc=true sidebar=false silent=false" "Space on Do Not Disturb again"
echo "ok   probe: Space flips Notifications.silent and the row reads On, then Off"
expect wifi_page "[wifi] CcWifiPage" "module(\"wifi\")"
expect wifi_escape "[] cc=true sidebar=false silent=false" "Escape from a detail page"
expect main_escape "cc=false sidebar=false silent=false" "Escape from the list"
echo "ok   probe: module(\"wifi\") shows the network page, Escape goes back, Escape again closes"
expect right_opens "[wifi] CcWifiPage" "Right on the Wi-Fi row"
expect backspace_back "[] cc-wifi" "Backspace from a detail page returns to the row it left"
echo "ok   probe: Right opens a module's page, Backspace returns focus to the same row"
expect focus_edit "cc-edit" "arrows reach the Edit row"
expect edit_page "[edit]" "Enter on Edit"
expect edit_stored "screenRecord" "a checked module is stored in controlCenter.extraModules"
expect modules_after_edit "cc-wifi,cc-bluetooth,cc-dnd,cc-keepAwake,cc-brightness,cc-nightLight,cc-darkMode,cc-sound,cc-extra-screenRecord,cc-edit" "the module chosen in Edit"
echo "ok   probe: Edit lists the optional modules, Space shows one, and it joins the list above Edit"
expect open_closes_sidebar "cc=true sidebar=false silent=false" "opening the Control Center with the right panel open"
expect sidebar_closes_cc "cc=false sidebar=true silent=false" "opening the right panel with the Control Center open"
echo "ok   probe: opening either panel closes the other"
expect slide_default "36" "the page slide"
expect slide_reduced "0" "the page slide under Reduce Motion"
echo "ok   probe: Reduce Motion removes the slide, leaving a crossfade"
