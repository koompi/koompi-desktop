#!/usr/bin/env bash
# Repo Hyprland config + shell, nested in a headless KWin, private bus, temp HOME and runtime dir.
#   hyprshot.sh REPO_ROOT OUT_DIR [WIDTHxHEIGHT] -- STEP...
# STEP: ipc:<target> <fn> [args] | hypr:<lua dispatch expr> | run:<cmd> | sleep:<s> | shot:<name>
# execs.lua is replaced by a launcher for the shell alone: the real one talks to the user's systemd and PipeWire.
set -euo pipefail
[[ -n ${KOOMPI_HEAVY_LOCKED:-} ]] || KOOMPI_HEAVY_LOCKED=1 exec flock /tmp/koompi-heavy.lock "${BASH_SOURCE[0]}" "$@"

repo=$(realpath "$1"); out=$(realpath -m "$2"); shift 2
size=1920x1200
if [[ ${1:-} != -- ]]; then size=$1; shift; fi
[[ ${1:-} == -- ]] || { echo "usage: hyprshot.sh REPO_ROOT OUT_DIR [WxH] -- STEP..." >&2; exit 2; }
shift
mkdir -p "$out"
work=$(mktemp -d)
# socket paths must fit 108 bytes
run=$(mktemp -d /tmp/hr.XXXXXX)
trap 'rm -rf "$work" "$run" 2>/dev/null || true' EXIT
home="$work/home"
mkdir -p "$home/.config/hypr/hyprland" "$home/.config/quickshell" "$home/.config/koompi" \
    "$home/.local/state/quickshell/user" "$home/.cache" "$work/bin"
chmod 700 "$run"

hypr_src="$repo/dots/.config/hypr"
for entry in "$hypr_src"/*; do
    name=$(basename -- "$entry")
    [[ $name == hyprland || $name == hyprland.lua || $name == custom ]] && continue
    ln -s "$entry" "$home/.config/hypr/$name"
done
for entry in "$hypr_src"/hyprland/*; do
    [[ $(basename -- "$entry") == execs.lua ]] && continue
    ln -s "$entry" "$home/.config/hypr/hyprland/$(basename -- "$entry")"
done
cat > "$home/.config/hypr/hyprland/execs.lua" <<'LUA'
hl.on("hyprland.start", function()
    hl.exec_cmd("env QT_QPA_PLATFORM=wayland qs -c koompi")
end)
LUA
grep -v 'custom\.' "$hypr_src/hyprland.lua" > "$home/.config/hypr/hyprland.lua"
w=${size%x*}; h=${size#*x}
printf 'hl.monitor({ output = "", mode = "%sx%s", position = "auto", scale = 1 })\n' "$w" "$h" >> "$home/.config/hypr/hyprland.lua"
echo 'hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })' >> "$home/.config/hypr/hyprland.lua"
ln -s "$repo/dots/.config/quickshell/koompi" "$home/.config/quickshell/koompi"
mkdir -p "$home/.local/share"
[[ -d $HOME/.local/share/fonts ]] && ln -s "$HOME/.local/share/fonts" "$home/.local/share/fonts"
ln -s "$repo/dots/.config/fontconfig" "$home/.config/fontconfig"
echo greeted > "$home/.local/state/quickshell/user/first_run.txt"
if [[ -n ${HYPRSHOT_CONFIG:-} ]]; then cp -- "$HYPRSHOT_CONFIG" "$home/.config/koompi/config.json"
else echo '{"windows": {"workspaceHelp": false}}' > "$home/.config/koompi/config.json"; fi
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/bin/koompi-shelld"
chmod +x "$work/bin/koompi-shelld"

{
    printf '#!/usr/bin/env bash\nset -uo pipefail\nunset HYPRLAND_INSTANCE_SIGNATURE\nparent=$WAYLAND_DISPLAY\n'
    printf 'Hyprland -c %q > %q 2>&1 &\n' "$home/.config/hypr/hyprland.lua" "$out/hyprland.log"
    printf 'for _ in $(seq 1 100); do sig=$(ls %q/hypr 2>/dev/null | head -1); [[ -n $sig ]] && break; sleep 0.2; done\n' "$run"
    printf 'export HYPRLAND_INSTANCE_SIGNATURE=$sig\n'
    printf 'for _ in $(seq 1 100); do d=$(ls %q | grep -E "^wayland-[0-9]+$" | grep -v "^$parent$" | head -1); [[ -n $d ]] && break; sleep 0.2; done\nexport WAYLAND_DISPLAY=$d\n' "$run"
    printf 'for _ in $(seq 1 100); do qs -c koompi ipc show >/dev/null 2>&1 && break; sleep 0.5; done\nsleep 5\n'
    for step in "$@"; do
        case $step in
            ipc:*) read -r -a words <<< "${step#ipc:}"
                   printf 'qs -c koompi ipc call'; printf ' %q' "${words[@]}"; printf ' >> %q 2>&1\n' "$out/ipc.log" ;;
            hypr:*) printf 'hyprctl dispatch %q >> %q 2>&1\n' "${step#hypr:}" "$out/ipc.log" ;;
            run:*) printf '%s >> %q 2>&1\n' "${step#run:}" "$out/run.log" ;;
            sleep:*) printf 'sleep %q\n' "${step#sleep:}" ;;
            shot:*) printf 'grim %q 2>> %q\n' "$out/${step#shot:}.png" "$out/run.log" ;;
            *) echo "hyprshot: unknown step $step" >&2; exit 2 ;;
        esac
    done
    printf 'echo "display=$WAYLAND_DISPLAY sig=$HYPRLAND_INSTANCE_SIGNATURE" >> %q\ncp "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log %q 2>/dev/null\ncp "$XDG_RUNTIME_DIR"/quickshell/by-id/*/log.qslog %q 2>/dev/null\nhyprctl dispatch "hl.dsp.exit()" >/dev/null 2>&1\nsleep 1\n' "$out/run.log" "$out/hyprland-run.log" "$out/qs.qslog"
} > "$work/inner.sh"
chmod +x "$work/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    HOME="$home" XDG_RUNTIME_DIR="$run" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
    XDG_CACHE_HOME="$home/.cache" PATH="$work/bin:$PATH" KOOMPI_SHELLD="$work/bin/koompi-shelld" \
    timeout 240 dbus-run-session --config-file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/tests/private-bus.conf" -- kwin_wayland --virtual --width "$((w + 200))" --height "$((h + 200))" \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$work/inner.sh" > "$out/kwin.log" 2>&1 || true
ls "$out"/*.png 2>/dev/null || { echo "hyprshot: no images; see $out/kwin.log and $out/hyprland.log" >&2; exit 1; }
