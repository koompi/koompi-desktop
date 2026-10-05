#!/usr/bin/env bash
# Start the shell at login, and say so on screen when it cannot start. Without
# the shell there is no bar, notification daemon or polkit agent, so a missing
# or broken quickshell otherwise reads as a desktop that silently died.
# hyprctl notify is drawn by the compositor itself and needs none of them.
set -uo pipefail

config="${qsConfig:-koompi}"
alert() { hyprctl notify 3 600000 "rgb(ff5555)" "KOOMPI shell: $1" >/dev/null; }

if ! command -v qs >/dev/null 2>&1; then
    alert "quickshell is not installed. Install it: sudo pacman -S quickshell"
    exit 1
fi

# The shell draws through layer-shell, which XWayland has no notion of, so it
# opts out of the session-wide xcb default that the global menu needs.
started=$SECONDS
QT_QPA_PLATFORM=wayland qs -c "$config"
status=$?
if (( status != 0 && SECONDS - started < 15 )); then
    alert "quickshell exited with status $status right after starting. See: qs log -c $config"
fi
exit "$status"
