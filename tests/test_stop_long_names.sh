#!/usr/bin/env bash
# A restart stops koompi-global-menu-daemon by name before it relaunches the shell.
# The kernel keeps 15 characters of a process name ("koompi-global-m"), and
# `pgrep -x koompi-global-menu-daemon` matches nothing, so the daemon outlived
# every `koompi update`, `./setup update` and `koompi reload` that named it.
# Both copies of stop_processes (sdata/lib/common.sh for ./setup, update-lib.sh
# for koompi update and koompi reload) are run against real processes: the
# session's daemon goes; a nested test session's daemon, and a program whose
# name shares those 15 characters, stay.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
pids=()
cleanup() {
    kill "${pids[@]}" 2> /dev/null
    wait 2> /dev/null
    rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/session-rt" "$tmp/nested-rt"
cp "$(command -v sleep)" "$tmp/bin/koompi-global-menu-daemon"
cp "$(command -v sleep)" "$tmp/bin/koompi-global-menu-probe"

start() { # runtime-dir program -> pid of a process running it
    XDG_RUNTIME_DIR="$1" "$tmp/bin/$2" 300 &
    pids+=("$!")
}

for lib in sdata/lib/common.sh dots/.local/share/koompi/libexec/update-lib.sh; do
    pids=()
    start "$tmp/session-rt" koompi-global-menu-daemon; daemon=${pids[-1]}
    start "$tmp/nested-rt" koompi-global-menu-daemon; nested=${pids[-1]}
    start "$tmp/session-rt" koompi-global-menu-probe; decoy=${pids[-1]}
    for _ in $(seq 1 50); do [[ $(cat "/proc/$decoy/comm" 2> /dev/null) == koompi-global-m ]] && break; sleep 0.05; done
    [[ $(cat "/proc/$daemon/comm" 2> /dev/null) == koompi-global-m ]] \
        || fail "setup: the stand-in's process name is '$(cat "/proc/$daemon/comm" 2> /dev/null)', not the truncated koompi-global-m"

    out="$(
        # shellcheck disable=SC1090 # one of two libraries, chosen above
        source "$REPO_ROOT/$lib" > /dev/null 2>&1
        DRY_RUN=false
        XDG_RUNTIME_DIR="$tmp/session-rt"
        stop_processes koompi-global-menu-daemon 2>&1
    )"
    for _ in $(seq 1 50); do kill -0 "$daemon" 2> /dev/null || break; sleep 0.05; done
    kill -0 "$daemon" 2> /dev/null && fail "$lib: stop_processes koompi-global-menu-daemon left this session's daemon running: $out"
    kill -0 "$nested" 2> /dev/null || fail "$lib: stop_processes stopped a daemon in another runtime dir (a nested test's)"
    kill -0 "$decoy" 2> /dev/null || fail "$lib: stop_processes stopped koompi-global-menu-probe, which only shares the 15-character name"
    kill "${pids[@]}" 2> /dev/null
    wait 2> /dev/null
done

# The restart paths name the daemon the shell really runs.
for caller in sdata/lib/common.sh dots/.local/share/koompi/libexec/update dots/.local/bin/koompi-reload; do
    grep -q 'stop_processes koompi-global-menu-daemon qs quickshell' "$REPO_ROOT/$caller" \
        || fail "$caller does not stop koompi-global-menu-daemon before it restarts the shell"
done
grep -q 'killall -w koompi-global-menu-daemon qs quickshell' "$REPO_ROOT/dots/.config/hypr/hyprland/keybinds.lua" \
    || fail "the restart keybind does not stop koompi-global-menu-daemon"

(( failed == 0 )) || exit 1
echo "ok: stop_processes stops this session's koompi-global-menu-daemon and nothing else"
