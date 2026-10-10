#!/usr/bin/env bash
# J25: the session menu labels every tile, and Shut down, Restart and Restart to firmware setup count down
# for ten seconds (Cancel focused, "... now" beside it) instead of acting at once. Escape or any other key
# cancels and nothing is called; "... now" or the end of the count calls Session once.
#
# Live: Hyprland nested in a headless KWin on a private bus, the real SessionScreen in a probe shell, real keys
# through wtype. systemctl, loginctl, reboot, kill and the rest of what Session runs are PATH stand-ins that
# append their argv to a file, so nothing here can power off, restart, suspend or log out a machine.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq wtype; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, no probe"; exit 0; }
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
STANDINS=(systemctl loginctl reboot poweroff shutdown halt kill pkill killall koompi-logout)
for name in "${STANDINS[@]}"; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >> "%s"\nexit 0\n' "$name" "$WORK/calls" > "$WORK/bin/$name"
done
touch "$WORK/calls"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/busctl"
chmod +x "$WORK/bin"/*
for name in "${STANDINS[@]}"; do
    [[ "$(PATH="$WORK/bin:$PATH" type -P "$name")" == "$WORK/bin/$name" ]] || fail "setup: the $name stand-in is not first on PATH"
done
echo "ok   setup: ${STANDINS[*]} resolve to recording stand-ins first on PATH"

cat > "$WORK/shell/session_probe.qml" <<'QML'
import qs.modules.koompi.sessionScreen
import Quickshell

ShellRoot {
    SessionScreen {}
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || exit 1

cd "$WORK/shell"
qs -p session_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p session_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done
state() { qs -p session_probe.qml ipc call session state 2> /dev/null; }
calls() { tr '\n' '|' < "$WORK/calls" 2> /dev/null; }
# wtype's first keysym takes Escape's keycode, so a throwaway Shift goes first
keys() { wtype -k Shift_R "$@"; sleep 0.7; }
note() { echo "$1 $(state) calls=$(calls)" >> "$WORK/readings"; }
focus_on() { # walk right then left until the readout names the tile
    local i
    for i in $(seq 1 9); do [[ $(state) == *"focus=$1 "* ]] && return 0; keys -k Right; done
    for i in $(seq 1 9); do [[ $(state) == *"focus=$1 "* ]] && return 0; keys -k Left; done
}
open_menu() { qs -p session_probe.qml ipc call session open > /dev/null 2>&1; sleep 2; }

sleep 3
open_menu
note idle
focus_on shutdown
keys -k Return
note shutdown-pressed
sleep 8
note after-9s
keys -k Escape
note after-escape
sleep 3
note after-escape-wait
keys -k Return
note shutdown-again
keys -k x
note after-any-key
keys -k Return
keys -k Right
note now-focused
keys -k Return
sleep 1
note shutdown-now
open_menu
focus_on restart
keys -k Return
sleep 1
keys -k Right
keys -k Return
sleep 1
note restart-now
open_menu
focus_on shutdown
keys -k Return
sleep 12
note shutdown-expired
open_menu
focus_on firmware
keys -k Return
note firmware-pressed
keys -k Escape
note firmware-escape

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
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null | sed 's/remaining=[0-9]*/remaining=N/'; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2; }
check() { # name, expected reading
    [[ "$(reading "$1")" == "$2" ]] || { dump; fail "$1 read '$(reading "$1")', expected '$2'"; }
}

[[ -s "$WORK/readings" ]] || { dump; fail "setup: the probe recorded nothing"; }
check idle "pending= remaining=N focus=lock labelled=true calls="
echo "ok   probe: the menu opens on Lock and every visible tile shows a text label"
check shutdown-pressed "pending=poweroff remaining=N focus=countdown-cancel labelled=true calls="
echo "ok   probe: Shut down starts a ten second count with Cancel focused and calls nothing"
check after-9s "pending=poweroff remaining=N focus=countdown-cancel labelled=true calls="
echo "ok   probe: nine seconds in, the count is still running and nothing was called"
check after-escape "pending= remaining=N focus=shutdown labelled=true calls="
check after-escape-wait "pending= remaining=N focus=shutdown labelled=true calls="
echo "ok   probe: Escape cancels, focus returns to Shut down, and nothing is called after the count would have ended"
check after-any-key "pending= remaining=N focus=shutdown labelled=true calls="
echo "ok   probe: any other key cancels the count"
check now-focused "pending=poweroff remaining=N focus=countdown-now labelled=true calls="
check shutdown-now "closed calls=systemctl poweroff|"
echo "ok   probe: Shut down now calls systemctl poweroff once and closes the menu"
check restart-now "closed calls=systemctl poweroff|reboot |"
echo "ok   probe: Restart then Restart now calls reboot once"
check shutdown-expired "closed calls=systemctl poweroff|reboot |systemctl poweroff|"
echo "ok   probe: left alone, the count ends in one systemctl poweroff"
check firmware-pressed "pending=firmware remaining=N focus=countdown-cancel labelled=true calls=systemctl poweroff|reboot |systemctl poweroff|"
check firmware-escape "pending= remaining=N focus=firmware labelled=true calls=systemctl poweroff|reboot |systemctl poweroff|"
echo "ok   probe: Restart to firmware setup counts down and Escape cancels it"
