#!/usr/bin/env bash
# Keep awake stops only the inhibitor this session recorded: another session's survives the shell's start and the switch going off
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in kwin_wayland qs dbus-run-session unshare; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

if [[ -z "${KEEP_AWAKE_NS:-}" ]]; then
    ns=(unshare -U --map-user="$(id -u)" --map-group="$(id -g)" -p -f --mount-proc)
    "${ns[@]}" true 2> /dev/null || { echo "skip: no unprivileged PID namespace, and the old pkill -f would reach the session's own inhibitor"; exit 0; }
    exec env KEEP_AWAKE_NS=1 "${ns[@]}" bash "${BASH_SOURCE[0]}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
QS_BIN="$(command -v qs)"
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/runtime" "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
chmod 700 "$WORK/runtime"
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"

cat > "$WORK/bin/systemd-inhibit" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$$" "$*" >> "$INHIBIT_LOG"
trap 'exit 0' TERM
for _ in $(seq 1 600); do sleep 0.2; done
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/*

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
PIDFILE="$XDG_RUNTIME_DIR/koompi-keep-awake.pid"
note() { printf '%s\t%s\n' "$1" "$2" >> "$READINGS"; }
yesno() { "$@" && echo yes || echo no; }
alive() { kill -0 "$1" 2> /dev/null; }
dead() { ! alive "$1"; }
up() { "$QS_BIN" -p "$SHELL_ROOT" ipc call idle inhibit status > /dev/null 2>&1; }
inhibit() { "$QS_BIN" -p "$SHELL_ROOT" ipc call idle inhibit "$1" > /dev/null 2>&1; }
own_started() { [[ -s "$WORK/own.log" ]]; }
await() {
    local n="$1" i
    shift
    for ((i = 0; i < n * 5; i++)); do "$@" && return 0; sleep 0.2; done
    return 1
}
start_fake() {
    INHIBIT_LOG="$1" "$WORK/bin/systemd-inhibit" --what=idle:sleep:handle-lid-switch --mode=block --who=quickshell --why='Keep system awake' sleep infinity > /dev/null 2>&1 &
    printf -v "$2" '%s' "$!"
}

start_fake "$WORK/foreign.log" FOREIGN
start_fake "$WORK/leftover.log" LEFTOVER
printf '%s\n' "$LEFTOVER" > "$PIDFILE"

INHIBIT_LOG="$WORK/own.log" "$QS_BIN" -p "$SHELL_ROOT" > "$QS_LOG" 2>&1 &
qs_pid=$!
trap 'kill "$qs_pid"; wait "$qs_pid"' EXIT
await 40 up || { note started no; exit 0; }
note started yes
sleep 4
note leftover_after_start "$(yesno alive "$LEFTOVER")"
note foreign_after_start "$(yesno alive "$FOREIGN")"
note pidfile_after_start "$(yesno test -e "$PIDFILE")"

sleep 600 &
UNRELATED=$!
printf '%s\n' "$UNRELATED" > "$PIDFILE"
inhibit on
await 10 own_started
OWN="$(awk 'NR == 1 { print $1 }' "$WORK/own.log" 2> /dev/null)"
note own_args "$(yesno grep -q -- '--why=Keep system awake' "$WORK/own.log")"
note own_alive "$(yesno alive "${OWN:-999999999}")"
note pidfile_is_own "$(yesno test "$(cat "$PIDFILE" 2> /dev/null)" == "${OWN:-none}")"
note unrelated_after_on "$(yesno alive "$UNRELATED")"
note foreign_after_on "$(yesno alive "$FOREIGN")"

start_fake "$WORK/foreign2.log" FOREIGN2
inhibit off
await 10 dead "${OWN:-999999999}"
note own_after_off "$(yesno alive "${OWN:-999999999}")"
note foreign_after_off "$(yesno alive "$FOREIGN")"
note foreign2_after_off "$(yesno alive "$FOREIGN2")"
note unrelated_after_off "$(yesno alive "$UNRELATED")"
note pidfile_after_off "$(yesno test -e "$PIDFILE")"
SH
chmod +x "$WORK/inner.sh"

env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$WORK/home" WORK="$WORK" SHELL_ROOT="$SHELL_ROOT" QS_BIN="$QS_BIN" READINGS="$WORK/readings" QS_LOG="$WORK/qs.log" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    XDG_RUNTIME_DIR="$WORK/runtime" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" \
    XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" \
    timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
    --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" \
    > "$WORK/kwin.log" 2>&1

reading() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$WORK/readings" 2> /dev/null; }
expect() {
    local got
    got="$(reading "$1")"
    [[ "$got" == "$2" ]] && return 0
    cat "$WORK/readings" >&2 2> /dev/null
    sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log" 2> /dev/null | tail -20 >&2
    fail "$3: $1 is '${got:-missing}', wanted '$2'"
}

expect started yes "the shell never came up"
expect leftover_after_start no "an inhibitor an earlier shell recorded in this runtime dir was not cleaned up at start"
expect foreign_after_start yes "a shell's start killed an inhibitor it never recorded"
expect pidfile_after_start no "the cleaned up inhibitor's pid file was left behind"
expect own_args yes "the shell's own inhibitor did not start with the Keep awake command line"
expect own_alive yes "turning Keep awake on did not start an inhibitor"
expect pidfile_is_own yes "the inhibitor's pid is not recorded in the runtime dir"
expect unrelated_after_on yes "a recorded pid that is no longer an inhibitor was killed"
expect foreign_after_on yes "turning Keep awake on killed an inhibitor it never recorded"
expect own_after_off no "turning Keep awake off left the shell's own inhibitor running"
expect foreign_after_off yes "turning Keep awake off killed an inhibitor it never recorded"
expect foreign2_after_off yes "turning Keep awake off killed an inhibitor it never recorded"
expect unrelated_after_off yes "turning Keep awake off killed a process that was never an inhibitor"
expect pidfile_after_off no "the pid file outlived the inhibitor"
echo "ok   shell: Keep awake stops only the inhibitor it recorded, at start and when turned off"
