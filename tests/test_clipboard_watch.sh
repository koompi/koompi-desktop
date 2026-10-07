#!/usr/bin/env bash
# the shell watches cliphist's db: a store from outside shows on the next open and costs it nothing while closed
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
EXECS="$REPO_ROOT/dots/.config/hypr/hyprland/execs.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for kind in text image; do
    grep -qF "hl.exec_cmd(\"wl-paste --type $kind --watch cliphist store\")" "$EXECS" \
        || fail "execs.lua does not run 'wl-paste --type $kind --watch cliphist store' directly"
done
grep -E 'wl-paste' "$EXECS" | grep -qE 'bash|ipc call|qs ' \
    && fail "a wl-paste hook in execs.lua still starts bash or a qs client per copy"
echo "ok   source: both wl-paste hooks run cliphist store and nothing else"

for tool in kwin_wayland qs cliphist dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
REAL_CLIPHIST="$(command -v cliphist)"
mkdir -p "$WORK/bin" "$WORK/shell"

for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$WORK/shell/clipboard_probe.qml" <<'QML'
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    IpcHandler {
        target: "clipprobe"
        function entries(): string { return JSON.stringify(Cliphist.entries); }
        function flag(name: string, on: bool): void { GlobalStates[name] = on; }
        function quit(): void { Qt.quit(); }
    }
    Component.onCompleted: Cliphist.refresh()
}
QML

cat > "$WORK/bin/cliphist" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${1:-}" >> "$CALLS_LOG"
exec "$REAL_CLIPHIST" "$@"
SH
chmod +x "$WORK/bin/cliphist"

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
mode="$CLIP_MODE"
note() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/readings.$mode"; }
yesno() { "$@" && echo yes || echo no; }
ipc() { qs -p "$PROBE" ipc call clipprobe "$@" 2> /dev/null; }
store() { printf '%s' "$1" | "$REAL_CLIPHIST" store; }
lists() { grep -c '^list$' "$CALLS_LOG" 2> /dev/null || true; }
up() { qs -p "$PROBE" ipc show > /dev/null 2>&1; }
listed() { (( $(lists) >= 1 )); }
has() { [[ "$(ipc entries)" == *"$1"* ]]; }
await() {
    local n="$1" i
    shift
    for ((i = 0; i < n * 5; i++)); do "$@" && return 0; sleep 0.2; done
    return 1
}

qs -p "$PROBE" > "$WORK/qs.$mode.log" 2>&1 &
qs_pid=$!
trap 'ipc quit; wait "$qs_pid"' EXIT
await 40 up || { note started no; exit 0; }
note started yes
await 10 listed
sleep 1

if [[ "$mode" == default ]]; then
    note lists_at_start "$(lists)"
    store "probe entry one"
    sleep 1.5
    note lists_while_closed "$(lists)"
    note closed_has_one "$(yesno has 'probe entry one')"
    ipc flag searchOpen true
    await 6 has "probe entry one"
    note open_has_one "$(yesno has 'probe entry one')"
    store "probe entry two"
    await 6 has "probe entry two"
    note watch_has_two "$(yesno has 'probe entry two')"
    sleep 1.5
    note lists_settled_a "$(lists)"
    sleep 1.5
    note lists_settled_b "$(lists)"
    ipc flag searchOpen false
    store "probe entry three"
    sleep 1.5
    note lists_after_closed_store "$(lists)"
    ipc flag searchOpen true
    await 6 has "probe entry three"
    note reopen_has_three "$(yesno has 'probe entry three')"
    ipc flag searchOpen false
    for surface in sidebarLeftOpen wallpaperSelectorOpen; do
        store "probe entry $surface"
        sleep 1
        ipc flag "$surface" true
        await 6 has "probe entry $surface"
        note "has_$surface" "$(yesno has "probe entry $surface")"
        ipc flag "$surface" false
    done
else
    ipc flag searchOpen true
    store "configured entry"
    await 6 has "configured entry"
    note configured_has "$(yesno has 'configured entry')"
    note default_db_absent "$(yesno test ! -e "$XDG_CACHE_HOME/cliphist/db")"
fi
SH
chmod +x "$WORK/inner.sh"

run_scenario() {
    local mode="$1"
    rm -rf "${WORK:?}/home" "${WORK:?}/xdg" "${WORK:?}/runtime"
    mkdir -p "$WORK/home" "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/runtime"
    chmod 700 "$WORK/runtime"
    echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
    echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
    if [[ "$mode" == configured ]]; then
        mkdir -p "$WORK/xdg/config/cliphist"
        printf '# where the history lives\ndb-path %s/custom/db\n' "$WORK" > "$WORK/xdg/config/cliphist/config"
    fi
    : > "$WORK/calls.$mode"
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$WORK/home" CLIP_MODE="$mode" WORK="$WORK" PROBE="$WORK/shell/clipboard_probe.qml" \
        REAL_CLIPHIST="$REAL_CLIPHIST" CALLS_LOG="$WORK/calls.$mode" PATH="$WORK/bin:$PATH" \
        QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 XDG_RUNTIME_DIR="$WORK/runtime" \
        XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" \
        timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" \
        > "$WORK/kwin.$mode.log" 2>&1
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

run_scenario default
expect default started yes "the probe shell never came up"
expect default closed_has_one no "a store while nothing was open changed the list (it should wait for the next open)"
(( $(reading default lists_while_closed) == $(reading default lists_at_start) )) \
    || fail "the shell ran cliphist list for a copy nobody was looking at ($(reading default lists_at_start) -> $(reading default lists_while_closed))"
expect default open_has_one yes "the clipboard list did not show a copy made while it was closed, when it opened"
expect default watch_has_two yes "a copy made while the clipboard list was open never reached it"
[[ "$(reading default lists_settled_a)" == "$(reading default lists_settled_b)" ]] \
    || fail "cliphist list keeps running with nothing changing ($(reading default lists_settled_a) -> $(reading default lists_settled_b))"
[[ "$(reading default lists_after_closed_store)" == "$(reading default lists_settled_b)" ]] \
    || fail "a copy made after the list closed still ran cliphist list"
expect default reopen_has_three yes "the clipboard list did not show a copy made while it was closed, on reopen"
expect default has_sidebarLeftOpen yes "the chat composer reads entries[0] on Ctrl+V, and the left sidebar opening did not relist"
expect default has_wallpaperSelectorOpen yes "the wallpaper picker reads entries[0] on Ctrl+V, and its opening did not relist"
if ! grep -q . "$WORK/calls.default" || grep -qvE '^list$' "$WORK/calls.default"; then
    fail "the shell ran something other than cliphist list: $(sort -u "$WORK/calls.default" | tr '\n' ' ')"
fi
echo "ok   probe: a store from outside waits for the next open, lands while open, and costs the shell nothing while closed (cliphist list runs: $(reading default lists_at_start) at start, $(reading default lists_settled_b) after open and one copy while open, $(reading default lists_after_closed_store) after a copy while closed)"

run_scenario configured
expect configured started yes "the probe shell never came up with a configured db-path"
expect configured configured_has yes "a copy made while open never reached the list when cliphist's config moves its db"
expect configured default_db_absent yes "the store landed in the default db, so the config was not in effect"
echo "ok   probe: the watch follows a db-path set in cliphist's own config"
