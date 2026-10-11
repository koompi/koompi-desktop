#!/usr/bin/env bash
# with-nested-hyprland.sh CMD...: run CMD inside the repo's own Hyprland config, nested in a headless KWin on a private bus,
# with an isolated HOME and runtime dir. CMD sees HYPRLAND_INSTANCE_SIGNATURE, WAYLAND_DISPLAY, HOME and XDG_RUNTIME_DIR of
# that session and its exit status is the script's. Exits 77 when Hyprland or KWin is missing, so a caller can skip.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$REPO_ROOT/dots/.config/hypr"

for tool in Hyprland hyprctl kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || exit 77
done

if [[ -n ${NESTED_INNER:-} ]]; then
    # shellcheck source=nested-hyprland.sh
    source "$REPO_ROOT/tests/nested-hyprland.sh"
    unset HYPRLAND_INSTANCE_SIGNATURE
    nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || { tail -20 "$WORK/hyprland.log" >&2; exit 78; }
    bash "$WORK/cmd.sh" > "$WORK/cmd.out" 2>&1
    rc=$?
    nested_hyprland_stop "$hypr_pid" "$HYPRLAND_INSTANCE_SIGNATURE"
    echo "$rc" > "$WORK/rc"
    exit 0
fi

[[ $# -gt 0 ]] || { echo "usage: with-nested-hyprland.sh CMD..." >&2; exit 2; }
WORK="$(mktemp -d)"
# under /tmp: a unix socket path in a longer TMPDIR passes sun_path's 108 bytes
RUN="$(mktemp -d /tmp/nh.XXXXXX)"
trap 'rm -rf "$WORK" "$RUN"' EXIT
chmod 700 "$RUN"
home="$WORK/home"
mkdir -p "$home/.config/hypr" "$home/.local/state" "$home/.local/share" "$home/.cache"
cp -r -- "$HYPR/hyprland" "$home/.config/hypr/hyprland"
printf 'hl.on("hyprland.start", function() end)\n' > "$home/.config/hypr/hyprland/execs.lua"
grep -v 'custom\.' "$HYPR/hyprland.lua" > "$home/.config/hypr/hyprland.lua"
cat >> "$home/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1200", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

printf "%q " "$@" > "$WORK/cmd.sh"
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" NESTED_INNER=1 \
    HOME="$home" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
    XDG_CACHE_HOME="$home/.cache" XDG_DATA_HOME="$home/.local/share" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 240 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 2120 --height 1400 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$REPO_ROOT/tests/with-nested-hyprland.sh" \
        > "$WORK/kwin.log" 2>&1
cat -- "$WORK/cmd.out" 2> /dev/null
rc=$(cat -- "$WORK/rc" 2> /dev/null)
[[ -n $rc ]] || { echo "with-nested-hyprland: the session never ran the command" >&2; tail -20 "$WORK/kwin.log" >&2; exit 78; }
exit "$rc"
