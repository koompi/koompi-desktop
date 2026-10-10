#!/usr/bin/env bash
# J23: with the keyboard cursor on a file row, Space toggles Quick Look
# (`koompi-quicklook <path>`) and Escape takes the preview down before it closes
# Search. In the text field Space types a space and previews nothing.
#
# Live: Hyprland nested in a headless KWin on a private bus, the real SearchPanel
# in a probe shell, real keys through wtype. `koompi-quicklook` is a PATH shim that
# records its argv, so no preview opens and nothing here reaches the running session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'toggleQuicklook' "$SHELL_ROOT/modules/koompi/overview/SearchItem.qml" || fail "SearchItem does not toggle Quick Look on Space"
grep -q 'closeQuicklook' "$SHELL_ROOT/modules/koompi/overview/SearchPanel.qml" || fail "Escape does not close Quick Look before Search"
echo "ok   source: Space toggles Quick Look on a file row and Escape closes it before Search"

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq wtype fd; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static check only"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$(mktemp -d /tmp/hr.XXXXXX)"
trap 'rm -rf "$WORK" "$RUN"' EXIT
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$HOME_DIR/Documents" "$WORK/bin" "$WORK/shell"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
printf '{"windows": {"workspaceHelp": false}}\n' > "$HOME_DIR/.config/koompi/config.json"
printf 'x\n' > "$HOME_DIR/Documents/zzquicklookprobe.txt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$WORK/quicklook.calls" > "$WORK/bin/koompi-quicklook"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/quicklook_probe.qml" <<'QML'
import qs
import qs.modules.koompi.overview
import Quickshell
import Quickshell.Io

ShellRoot {
    SearchPanel {
        id: panel
    }

    IpcHandler {
        target: "probe"

        function open(): string {
            panel.open();
            return "opened";
        }
        function state(): string {
            return GlobalStates.searchOpen ? "open" : "closed";
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
qs -p quicklook_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p quicklook_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done
for _ in $(seq 1 40); do
    [[ $(qs -p quicklook_probe.qml ipc call probe open 2> /dev/null) == opened ]] && break
    sleep 0.5
done
state() { qs -p quicklook_probe.qml ipc call probe state 2> /dev/null; }
calls() { cat -- "$WORK/quicklook.calls" 2> /dev/null | tr '\n' '|'; }
# wtype's first keysym takes Escape's keycode, so a throwaway Shift goes first
keys() { wtype -k Shift_R "$@"; sleep 1; }

sleep 3
keys zzquicklookprobe
sleep 2
keys -k space
echo "after-space-in-field $(calls)" >> "$WORK/readings"
keys -k BackSpace -k Down -k Up
echo "before-space-on-row $(calls)" >> "$WORK/readings"
keys -k space
echo "after-space-on-row $(calls)" >> "$WORK/readings"
keys -k Escape
echo "after-escape-1 $(state) $(calls)" >> "$WORK/readings"
keys -k Escape
echo "after-escape-2 $(state)" >> "$WORK/readings"

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
    timeout 180 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }

file="$HOME_DIR/Documents/zzquicklookprobe.txt"
[[ -s "$WORK/readings" ]] || { dump; fail "setup: the probe recorded nothing"; }
[[ "$(reading after-space-in-field)" == "" ]] || { dump; fail "Space in the text field ran koompi-quicklook: '$(reading after-space-in-field)'"; }
echo "ok   probe: Space in the text field typed a space and recorded no Quick Look"
[[ "$(reading before-space-on-row)" == "" ]] || { dump; fail "setup: a Quick Look was recorded before Space reached the file row"; }
[[ "$(reading after-space-on-row)" == "$file|" ]] || { dump; fail "Space on the focused file row recorded '$(reading after-space-on-row)', expected '$file|'"; }
echo "ok   probe: Space on the focused file row recorded koompi-quicklook <path>"
[[ "$(reading after-escape-1)" == "open $file|close|" ]] || { dump; fail "the first Escape left '$(reading after-escape-1)', expected Search open and a close recorded"; }
echo "ok   probe: the first Escape closed Quick Look and left Search open"
[[ "$(reading after-escape-2)" == "closed" ]] || { dump; fail "the second Escape left Search '$(reading after-escape-2)'"; }
echo "ok   probe: the second Escape closed Search"
