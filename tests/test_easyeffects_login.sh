#!/usr/bin/env bash
# EasyEffects starts at login only if its sidebar toggle was left on; the toggle's state lives in states.json
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
EXECS="$REPO_ROOT/dots/.config/hypr/hyprland/execs.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -qi 'easyeffects' "$EXECS" && fail "execs.lua still starts easyeffects at every login"
grep -q 'EasyEffects.load()' "$SHELL_ROOT/shell.qml" || fail "shell.qml does not call EasyEffects.load() at login"
echo "ok   source: execs.lua starts no easyeffects, shell.qml loads the service at login"

for tool in kwin_wayland qs dbus-run-session jq pidof; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
QS_BIN="$(command -v qs)"
REAL_PIDOF="$(command -v pidof)"
mkdir -p "$WORK/bin" "$WORK/bin-noee" "$WORK/farm" "$WORK/shell"

for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
for tool in bash env sleep cat rm; do
    ln -s "$(command -v "$tool")" "$WORK/farm/$tool"
done

cat > "$WORK/shell/easyeffects_probe.qml" <<'QML'
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "eeprobe"
        function ping(): string { return "pong"; }
        function toggle(): void { EasyEffects.toggle(); }
        function quit(): void { Qt.quit(); }
    }
    Component.onCompleted: EasyEffects.load()
}
QML

cat > "$WORK/bin/easyeffects" <<'SH'
#!/usr/bin/env bash
printf 'started %s\n' "$*" >> "$EE_LOG"
printf '%s\n' "$$" > "$EE_PID"
trap 'rm -f "$EE_PID"; exit 0' TERM
for _ in $(seq 1 600); do sleep 0.2; done
SH
cat > "$WORK/bin/pidof" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == easyeffects ]]; then
    [[ -f "$EE_PID" ]] && kill -0 "$(cat "$EE_PID")" 2> /dev/null && { cat "$EE_PID"; exit 0; }
    exit 1
fi
exec "$REAL_PIDOF" "$@"
SH
cat > "$WORK/bin/pkill" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == easyeffects && -f "$EE_PID" ]]; then kill "$(cat "$EE_PID")" 2> /dev/null; fi
exit 0
SH
cat > "$WORK/bin/flatpak" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FLATPAK_LOG"
exit 1
SH
cp "$WORK/bin/flatpak" "$WORK/bin-noee/flatpak"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/* "$WORK/bin-noee"/*

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
note() { printf '%s\t%s\n' "$1" "$2" >> "$READINGS"; }
yesno() { "$@" && echo yes || echo no; }
starts() { grep -c '^started' "$EE_LOG" 2> /dev/null || true; }
alive() { [[ -f "$EE_PID" ]] && kill -0 "$(cat "$EE_PID")" 2> /dev/null; }
dead() { ! alive; }
state() { jq -r 'if (.easyEffects.enabled | type) == "boolean" then (.easyEffects.enabled | tostring) else "absent" end' "$STATE_FILE" 2> /dev/null || echo absent; }
starts_is() { [[ "$(starts)" == "$1" ]]; }
state_is() { [[ "$(state)" == "$1" ]]; }
ipc() { "$QS_BIN" -p "$TARGET" ipc call "$@" > /dev/null 2>&1; }
up() { read -r -a call <<< "$UP_CALL"; ipc "${call[@]}"; }
await() {
    local n="$1" i
    shift
    for ((i = 0; i < n * 5; i++)); do "$@" && return 0; sleep 0.2; done
    return 1
}

: > "$EE_LOG"
: > "$FLATPAK_LOG"
env PATH="$QS_PATH" "$QS_BIN" -p "$TARGET" > "$QS_LOG" 2>&1 &
qs_pid=$!
trap 'kill "$qs_pid"; wait "$qs_pid"; alive && kill "$(cat "$EE_PID")"; true' EXIT
await 40 up || { note started no; exit 0; }
note started yes

case "$SCENARIO" in
fresh)
    sleep 10
    note login_starts "$(starts)"
    ;;
flip)
    sleep 6
    note login_starts "$(starts)"
    note login_state "$(state)"
    ipc eeprobe toggle
    await 8 starts_is 1
    await 8 state_is true
    note on_starts "$(starts)"
    note on_args "$(yesno grep -qx 'started --hide-window --service-mode' "$EE_LOG")"
    note on_state "$(state)"
    ipc eeprobe toggle
    await 8 dead
    await 8 state_is false
    note off_alive "$(yesno alive)"
    note off_state "$(state)"
    ipc eeprobe toggle
    await 8 starts_is 2
    await 8 state_is true
    note again_starts "$(starts)"
    note again_state "$(state)"
    ;;
lefton)
    await 10 starts_is 1
    sleep 6
    note login_starts "$(starts)"
    note login_alive "$(yesno alive)"
    ;;
notinstalled)
    sleep 12
    note probed "$(yesno grep -q '^info com.github.wwmm.easyeffects' "$FLATPAK_LOG")"
    note flatpak_run "$(yesno grep -q '^run ' "$FLATPAK_LOG")"
    note state_after "$(state)"
    ;;
esac
SH
chmod +x "$WORK/inner.sh"

run_session() {
    local name="$1" scenario="$2" state="$3" seed="$4" target="$5" up="$6" qs_path="$7"
    local state_dir="$WORK/xdg/state-$state"
    rm -rf "${WORK:?}/home" "${WORK:?}/runtime"
    mkdir -p "$WORK/home" "$WORK/runtime" "$WORK/xdg/config/koompi" "$WORK/xdg/cache" "$WORK/xdg/data" "$state_dir/quickshell/user"
    chmod 700 "$WORK/runtime"
    echo greeted > "$state_dir/quickshell/user/first_run.txt"
    echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
    [[ -z "$seed" ]] || printf '%s\n' "$seed" > "$state_dir/quickshell/states.json"
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$WORK/home" SCENARIO="$scenario" TARGET="$target" UP_CALL="$up" QS_BIN="$QS_BIN" QS_PATH="$qs_path" \
        READINGS="$WORK/readings.$name" QS_LOG="$WORK/qs.$name.log" STATE_FILE="$state_dir/quickshell/states.json" \
        EE_LOG="$WORK/easyeffects.$name.log" EE_PID="$WORK/easyeffects.$name.pid" FLATPAK_LOG="$WORK/flatpak.$name.log" REAL_PIDOF="$REAL_PIDOF" \
        KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        XDG_RUNTIME_DIR="$WORK/runtime" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$state_dir" \
        XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" \
        timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" \
        > "$WORK/kwin.$name.log" 2>&1
}

reading() { awk -F'\t' -v k="$2" '$1 == k { print $2 }' "$WORK/readings.$1" 2> /dev/null; }
expect() {
    local got
    got="$(reading "$1" "$2")"
    [[ "$got" == "$3" ]] && return 0
    cat "$WORK/readings.$1" >&2 2> /dev/null
    sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.$1.log" 2> /dev/null | tail -20 >&2
    fail "$4: $2 is '${got:-missing}', wanted '$3'"
}

FULL_PATH="$WORK/bin:$PATH"
PROBE="$WORK/shell/easyeffects_probe.qml"

run_session fresh fresh fresh "" "$SHELL_ROOT" "sidebarLeft close" "$FULL_PATH"
expect fresh started yes "the shell never came up"
expect fresh login_starts 0 "a fresh profile's login started easyeffects"
echo "ok   shell: a fresh profile's login starts nothing"

run_session flip flip flip "" "$PROBE" "eeprobe ping" "$FULL_PATH"
expect flip started yes "the probe shell never came up"
expect flip login_starts 0 "the service started easyeffects at login with the toggle never turned on"
expect flip login_state false "a fresh profile does not start with the toggle off"
expect flip on_starts 1 "turning the toggle on did not start easyeffects"
expect flip on_args yes "easyeffects was not started hidden, in service mode"
expect flip on_state true "turning the toggle on was not stored in states.json"
expect flip off_alive no "turning the toggle off left easyeffects running"
expect flip off_state false "turning the toggle off was not stored in states.json"
expect flip again_starts 2 "turning the toggle on again did not start easyeffects"
expect flip again_state true "turning the toggle on again was not stored in states.json"
echo "ok   probe: the toggle stores on, off and on again in states.json"

run_session lefton lefton flip "" "$SHELL_ROOT" "sidebarLeft close" "$FULL_PATH"
expect lefton started yes "the shell never came up"
expect lefton login_starts 1 "a login with the toggle left on did not start easyeffects exactly once"
expect lefton login_alive yes "easyeffects is not running after a login with the toggle left on"
echo "ok   shell: a login after the toggle was left on starts easyeffects once"

run_session notinstalled notinstalled ni '{"easyEffects": {"enabled": true}}' "$SHELL_ROOT" "sidebarLeft close" "$WORK/farm:$WORK/bin-noee"
expect notinstalled started yes "the shell never came up without easyeffects installed"
expect notinstalled probed yes "the shell never looked for easyeffects"
expect notinstalled flatpak_run no "a remembered on without easyeffects installed tried to start it"
expect notinstalled state_after true "a remembered on was forgotten because easyeffects is not installed"
echo "ok   shell: a remembered on with easyeffects not installed does nothing"
