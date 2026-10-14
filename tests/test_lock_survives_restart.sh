#!/usr/bin/env bash
# The lock outlives the shell process (modules/koompi/lock/Lock.qml).
#   1. A shell that starts and finds lock-state.json for its own Hyprland instance locks at
#      once and takes back where each monitor came from, so a crash or a restart under the
#      lock lands on the lock screen, not on Hyprland's "lockscreen app died" screen.
#   2. A state file from another Hyprland instance (an old login) does not lock.
#   3. Unlocking clears the state file and runs a restart an update deferred.
# Headless qs in a virtual KWin, on a private bus with its own HOME and runtime dir.
# hyprctl, busctl and koompi-reload are stubs: nothing reaches the live session or logind.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/home" "$WORK/bin"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
for stub in hyprctl busctl; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/%s.log"\n' "$WORK" "$stub" > "$WORK/bin/$stub"
done
printf '#!/usr/bin/env bash\n: > "%s/reloaded"\n' "$WORK" > "$WORK/bin/koompi-reload"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/koompi-shelld"
chmod +x "$WORK/bin/"* "$WORK/koompi-shelld"

cat > "$WORK/shell/lock_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs
import qs.modules.koompi.lock

ShellRoot {
    id: probe
    property int ticks: 0
    Lock { id: lock }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks === 4) {
                console.log("LOCKED " + GlobalStates.screenLocked);
                console.log("SAVED " + JSON.stringify(lock.savedWorkspaces));
            }
            if (probe.ticks === 5) GlobalStates.screenLocked = false;
            if (probe.ticks === 12) { console.log("PROBE DONE"); Qt.quit(); }
        }
    }
}
QML
# one run: $1 = the instance the state file names, $2 = the instance the shell runs in
run_probe() {
    local rt="$WORK/rt-$3"
    mkdir -p "$rt/koompi" && chmod 700 "$rt"
    printf '{"instance":"%s","workspaces":{"probe-1":4}}' "$1" > "$rt/koompi/lock-state.json"
    : > "$rt/koompi/shell-restart-pending"
    rm -f "$WORK/reloaded"
    cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
timeout 40 qs -p "$WORK/shell/lock_probe.qml" > "$WORK/qs-$3.log" 2>&1
SH
    chmod +x "$WORK/inner.sh"
    env -u WAYLAND_DISPLAY -u DISPLAY HYPRLAND_INSTANCE_SIGNATURE="$2" PATH="$WORK/bin:$PATH" \
        KOOMPI_SHELLD="$WORK/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$rt" \
        XDG_DATA_HOME="$WORK/xdg/data" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
        timeout 90 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 800 --height 600 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin-$3.log" 2>&1
    sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs-$3.log" | grep -oE '(LOCKED|SAVED) .*$|PROBE DONE'
}

same="$(run_probe probe-instance probe-instance same)"
grep -q "PROBE DONE" <<< "$same" || { fail "the probe did not finish"; grep -E "ERROR|TypeError|ReferenceError" "$WORK/qs-same.log" | head -20 >&2; }
grep -q "LOCKED true" <<< "$same" || fail "a shell started under its own instance's lock did not lock again"
grep -q 'SAVED .*"probe-1":4' <<< "$same" || fail "the relocked shell lost where the monitors came from: $(grep SAVED <<< "$same")"
[[ -e "$WORK/rt-same/koompi/lock-state.json" ]] && fail "unlocking left lock-state.json behind"
[[ -e "$WORK/rt-same/koompi/shell-restart-pending" ]] && fail "unlocking did not take the deferred restart"
[[ -e "$WORK/reloaded" ]] || fail "the restart an update deferred did not run after the unlock"

other="$(run_probe old-instance probe-instance other)"
grep -q "PROBE DONE" <<< "$other" || fail "the second probe did not finish"
grep -q "LOCKED false" <<< "$other" || fail "a state file from another Hyprland instance locked the screen"

(( failed )) || echo "ok   lock: a restarted shell locks again under its own instance only, keeps the desktop to restore, and runs a deferred restart on unlock"
exit $failed
