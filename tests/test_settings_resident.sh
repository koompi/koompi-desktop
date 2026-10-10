#!/usr/bin/env bash
# Settings opens in the running shell. Two halves:
#   - koompi-settings with `qs` shadowed: it asks the shell over IPC first, and starts the standalone
#     settings.qml only when that call fails (no shell, or one without the target)
#   - the real SettingsWindow in a headless KWin: the settings IPC target builds a visible window,
#     page <name> lands on that page, close hides it
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
LAUNCHER="$REPO_ROOT/dots/.local/bin/koompi-settings"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home/.config/quickshell/koompi"
touch "$WORK/home/.config/quickshell/koompi/settings.qml"

cat > "$WORK/bin/qs" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QS_LOG"
case "$*" in
    *"ipc call"*) [[ -z ${QS_IPC_FAIL:-} ]] || exit 1 ;;
esac
exit 0
SH
cat > "$WORK/bin/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$WORK/bin"/*

launch() { # $1: QS_IPC_FAIL value, rest: arguments
    local fail_ipc="$1"; shift
    : > "$WORK/qs.log"
    env HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" PATH="$WORK/bin:$PATH" QS_LOG="$WORK/qs.log" QS_IPC_FAIL="$fail_ipc" \
        "$LAUNCHER" "$@" > /dev/null 2>&1
}

launch ""
[[ "$(cat "$WORK/qs.log")" == "-c koompi ipc call settings toggle" ]] || fail "a bare call must toggle over IPC and stop there, got: $(cat "$WORK/qs.log")"
launch "" bluetooth
[[ "$(cat "$WORK/qs.log")" == "-c koompi ipc call settings page bluetooth" ]] || fail "a page call must go over IPC and stop there, got: $(cat "$WORK/qs.log")"
launch 1
[[ "$(tail -n 1 "$WORK/qs.log")" == "-p $WORK/home/.config/quickshell/koompi/settings.qml" ]] || fail "with no shell the standalone window must start, got: $(cat "$WORK/qs.log")"
launch 1 bluetooth
[[ "$(tail -n 1 "$WORK/qs.log")" == "-p $WORK/home/.config/quickshell/koompi/settings.qml" ]] || fail "with no shell a page call must start the standalone window, got: $(cat "$WORK/qs.log")"
echo "ok   koompi-settings: IPC when the shell answers, standalone when it does not"

for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

mkdir -p "$WORK/shell" "$WORK/state/quickshell/user" "$WORK/config/koompi" "$WORK/cache" "$WORK/data" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"; done
echo greeted > "$WORK/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"
rm -f "$WORK/bin/qs" "$WORK/bin/pgrep"

cat > "$WORK/shell/settings_probe.qml" <<'QML'
import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.koompi.settings

ShellRoot {
    SettingsWindow { id: settings }
    IpcHandler {
        target: "probe"
        function state(): string { return `${settings.built} ${settings.shown} ${settings.pageShown}`; }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell" || exit 1
qs -p settings_probe.qml > "$WORK/qs.log" 2>&1 &
trap 'kill $!; wait $!' EXIT
call() { qs -p settings_probe.qml ipc call "$@" 2> /dev/null < /dev/null; }
check() { if [[ "$2" == "$3" ]]; then echo "PASS $1"; else echo "FAIL $1: got '$2', wanted '$3'"; fi; }
for _ in $(seq 1 80); do call probe state > /dev/null && break; sleep 0.5; done
sleep 2
check "nothing is built while closed" "$(call probe state)" "false false -1"
call settings toggle; sleep 1.5
check "toggle builds and shows the window on the first page" "$(call probe state)" "true true 0"
call settings close; sleep 0.5
check "close hides it and keeps it warm" "$(call probe state)" "true false 0"
call settings page bluetooth; sleep 1
check "page opens the warm window on that page" "$(call probe state)" "true true 9"
call settings toggle; sleep 0.5
check "toggle closes it" "$(call probe state)" "true false 9"
call settings page sound; sleep 0.5
check "page on a warm closed window shows it on that page" "$(call probe state)" "true true 10"
echo DONE
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" \
    XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" XDG_DATA_HOME="$WORK/data" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 240 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep -E '^(PASS|FAIL) ' "$WORK/kwin.log"
grep -qx DONE "$WORK/kwin.log" || { cat "$WORK/qs.log" >&2; fail "the probe did not finish"; }
! grep -q '^FAIL ' "$WORK/kwin.log" || fail "the settings IPC does not drive the resident window"
echo "ok   settings window: built on IPC, page <name>, close, kept warm"
