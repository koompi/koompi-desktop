#!/usr/bin/env bash
# a screen that goes away under Brightness must not log a TypeError for the monitor that outlived it
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

for tool in kwin_wayland qs dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/run" "$WORK/home" "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
chmod 700 "$WORK/run"
for entry in "$SHELL_ROOT"/*; do
    [[ "$(basename -- "$entry")" == shell.qml ]] || ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
cat > "$WORK/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    Timer {
        interval: 500
        running: true
        onTriggered: console.log("BRIGHTNESS monitors " + Brightness.monitors.length)
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell"
qs -p "$WORK/shell/shell.qml" > "$WORK/qs.log" 2>&1 &
for _ in \$(seq 1 80); do grep -q 'BRIGHTNESS monitors' "$WORK/qs.log" && break; sleep 0.25; done
sleep 1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" HOME="$WORK/home" QT_NO_XDG_DESKTOP_PORTAL=1 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland \
    XDG_RUNTIME_DIR="$WORK/run" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" \
    XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual \
        --width 1280 --height 800 --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

for _ in $(seq 1 40); do grep -q 'Wayland connection broke' "$WORK/qs.log" && break; sleep 0.25; done
out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -q 'BRIGHTNESS monitors 1' <<< "$out" || fail "the shell never built a Brightness monitor for the screen"
grep -q 'Wayland connection broke' <<< "$out" || fail "the screen never went away, so nothing was tested"
grep -q 'TypeError' <<< "$out" && fail "a screen that went away logged: $(grep -m1 'TypeError' <<< "$out")"
(( failed )) && exit 1
echo "ok   brightness: a screen that goes away leaves no TypeError"
