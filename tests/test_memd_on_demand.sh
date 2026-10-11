#!/usr/bin/env bash
# koompi-agent-memd starts when the assistant is first used, not at login
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in kwin_wayland qs dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/memd-shadow" <<'SH'
#!/usr/bin/env bash
printf 'started %s\n' "$$" >> "$MEMD_MARKER"
exec cat > /dev/null
SH
chmod +x "$WORK/bin/memd-shadow"

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
note() { printf '%s\t%s\n' "$1" "$2" >> "$READINGS"; }
yesno() { "$@" && echo yes || echo no; }
marker() { [[ -s "$MEMD_MARKER" ]]; }
up() { qs -p "$SHELL_ROOT" ipc call sidebarLeft close > /dev/null 2>&1; }
await() {
    local n="$1" i
    shift
    for ((i = 0; i < n * 5; i++)); do "$@" && return 0; sleep 0.2; done
    return 1
}

qs -p "$SHELL_ROOT" > "$QS_LOG" 2>&1 &
qs_pid=$!
trap 'kill "$qs_pid"; wait "$qs_pid"' EXIT
await 40 up || { note started no; exit 0; }
note started yes
sleep 4
sleep "$IDLE_SECONDS"
note idle "$(yesno marker)"
read -r -a trigger <<< "$TRIGGER"
qs -p "$SHELL_ROOT" ipc call "${trigger[@]}" > /dev/null 2>&1
await 10 marker
note triggered "$(yesno marker)"
SH
chmod +x "$WORK/inner.sh"

run_shell() {
    local name="$1"
    rm -rf "${WORK:?}/home" "${WORK:?}/xdg" "${WORK:?}/runtime"
    mkdir -p "$WORK/home" "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/runtime"
    chmod 700 "$WORK/runtime"
    echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/easyeffects"; chmod +x "$WORK/bin/easyeffects"
    printf '{"windows": {"workspaceHelp": false}, "ai": {"memory": {"binary": "%s/bin/memd-shadow"}}}\n' "$WORK" \
        > "$WORK/xdg/config/koompi/config.json"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
    chmod +x "$WORK/bin/koompi-shelld"
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$WORK/home" SHELL_ROOT="$SHELL_ROOT" READINGS="$WORK/readings.$name" QS_LOG="$WORK/qs.$name.log" \
        MEMD_MARKER="$WORK/marker.$name" IDLE_SECONDS="$2" TRIGGER="$3" \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        XDG_RUNTIME_DIR="$WORK/runtime" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$WORK/no-system-bus" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" \
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

run_shell sidebar 10 "sidebarLeft open"
expect sidebar started yes "the shell never came up"
expect sidebar idle no "the memory daemon was started by a shell nobody had used the assistant in"
expect sidebar triggered yes "opening the left sidebar did not start the memory daemon"
echo "ok   shell: no memd after 10 s idle, started by the left sidebar opening"

run_shell intelligence 2 "intelligence open"
expect intelligence started yes "the shell never came up"
expect intelligence idle no "the memory daemon was started by a shell nobody had used the assistant in"
expect intelligence triggered yes "opening the Intelligence window did not start the memory daemon"
echo "ok   shell: started by the Intelligence window opening"

run_shell browser 2 "memory open"
expect browser started yes "the shell never came up"
expect browser idle no "the memory daemon was started by a shell nobody had used the assistant in"
expect browser triggered yes "a memory op from the memory browser did not start the memory daemon"
echo "ok   shell: started by a memory op"
