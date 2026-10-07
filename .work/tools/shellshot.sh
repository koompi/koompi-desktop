#!/usr/bin/env bash
# Runs a shell tree in a headless KWin with a private bus and fresh XDG dirs, then plays steps:
#   shellshot.sh SHELL_ROOT OUT_DIR [WIDTHxHEIGHT] -- STEP...
# STEP is  ipc:<target> <fn> [args]  |  run:<command>  |  sleep:<s>  |  shot:<name>
# Env passes through (KOOMPI_UPDATES_FORCE etc); SHELLSHOT_CONFIG=<json> replaces the seeded config.
# Leaves OUT_DIR/qs.log and OUT_DIR/<name>.png.
set -euo pipefail

root=$(realpath "$1"); out=$(realpath -m "$2"); shift 2
size=1920x1200
if [[ ${1:-} != -- ]]; then size=$1; shift; fi
[[ ${1:-} == -- ]] || { echo "usage: shellshot.sh SHELL_ROOT OUT_DIR [WxH] -- STEP..." >&2; exit 2; }
shift
mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/xdg/config" "$work/xdg/state" "$work/xdg/cache" "$work/bin"
mkdir -p "$work/xdg/data/applications"
[[ -d $HOME/.local/share/fonts ]] && ln -s "$HOME/.local/share/fonts" "$work/xdg/data/fonts"
ln -s "$(dirname -- "$root")/../fontconfig" "$work/xdg/config/fontconfig"
# kwin authorises ScreenShot2 by the caller's desktop file
printf '[Desktop Entry]\nType=Application\nName=kwinshot\nExec=%s\nX-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2\n' \
    "$(readlink -f "$(command -v python3)")" > "$work/xdg/data/applications/kwinshot.desktop"
mkdir -p "$work/xdg/state/quickshell/user" "$work/xdg/config/koompi"
echo greeted > "$work/xdg/state/quickshell/user/first_run.txt"
if [[ -n ${SHELLSHOT_CONFIG:-} ]]; then cp -- "$SHELLSHOT_CONFIG" "$work/xdg/config/koompi/config.json"
else echo '{"windows": {"workspaceHelp": false}}' > "$work/xdg/config/koompi/config.json"; fi
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/bin/koompi-shelld"
chmod +x "$work/bin/koompi-shelld"
tools=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

{
    printf '#!/usr/bin/env bash\nset -uo pipefail\nunset HYPRLAND_INSTANCE_SIGNATURE\n'
    printf 'qs -p %q > %q 2>&1 &\n' "$root" "$out/qs.log"
    printf 'for _ in $(seq 1 80); do qs -p %q ipc show >/dev/null 2>&1 && break; sleep 0.5; done\nsleep 4\n' "$root"
    for step in "$@"; do
        case $step in
            ipc:*) read -r -a words <<< "${step#ipc:}"
                   printf 'qs -p %q ipc call' "$root"; printf ' %q' "${words[@]}"; printf ' >> %q 2>&1\n' "$out/ipc.log" ;;
            run:*) printf '%s >> %q 2>&1\n' "${step#run:}" "$out/run.log" ;;
            sleep:*) printf 'sleep %q\n' "${step#sleep:}" ;;
            shot:*) printf 'python3 -I %q %q\n' "$tools/kwinshot.py" "$out/${step#shot:}.png" ;;
            *) echo "shellshot: unknown step $step" >&2; exit 2 ;;
        esac
    done
} > "$work/inner.sh"
chmod +x "$work/inner.sh"

w=${size%x*}; h=${size#*x}
PATH="$work/bin:$PATH" KOOMPI_SHELLD="$work/bin/koompi-shelld" QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$work/xdg/config" XDG_STATE_HOME="$work/xdg/state" XDG_CACHE_HOME="$work/xdg/cache" \
    XDG_DATA_HOME="$work/xdg/data" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 180 dbus-run-session --config-file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/tests/private-bus.conf" -- kwin_wayland --virtual --width "$w" --height "$h" \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$work/inner.sh" > "$out/kwin.log" 2>&1 || true
ls "$out"/*.png 2>/dev/null || { echo "shellshot: no images; see $out/kwin.log and $out/qs.log" >&2; exit 1; }
