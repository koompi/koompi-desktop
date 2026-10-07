#!/usr/bin/env bash
# J10: Reduce Motion and Game mode both want animations:enabled off, and
# services/HyprlandModes.qml is the one place that decides it. The real
# HyprlandModes, GameModeToggle and HyprlandConfig run in a headless KWin on a private
# bus and runtime dir, and the real scripts/hyprland/hyprconfigurator.py writes a
# temp shellOverrides/main.lua; the test reads that file back.
#   reduce motion on, game mode on, game mode off   -> animations stay off
#   game mode on, reduce motion on, reduce motion off -> animations stay off
#   both off                                         -> every held option is reset
#                                                       to the user's own value
#   reduce motion on, game mode off                  -> the Game mode toggle reads off
#   a restart reads game mode back from the file, rewrites nothing that already
#   agrees, and releases a hold no mode wants.
# Last, the same sequences run against a real Hyprland nested in that KWin (update news
# off, as every nested Hyprland here): the compositor itself reloads the file, and its
# animations:enabled, gaps and rounding follow, back to the user's own values at the end.
# A new mode (Reduce Transparency's blur) is one more flag and one more `by` entry in
# HyprlandModes.qml; the static half below holds every key it names to one owner.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
MODES="$SHELL_ROOT/services/HyprlandModes.qml"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

[[ -f "$MODES" ]] || { fail "missing services/HyprlandModes.qml"; exit 1; }

keys="$(sed -n '/readonly property var holds/,/^    })/p' "$MODES" | grep -oE '"[a-z_]+(:[a-z_]+)+"' | tr -d '"' | sort -u)"
[[ -n "$keys" ]] || { fail "found no held options in HyprlandModes.qml; the scan broke"; exit 1; }
for key in $keys; do
    owners="$(grep -rlF --include='*.qml' -- "\"$key\"" "$SHELL_ROOT" | sed "s|^$SHELL_ROOT/||")"
    [[ "$owners" == "services/HyprlandModes.qml" ]] || fail "$key is named outside HyprlandModes.qml: $(tr '\n' ' ' <<< "$owners")"
done
if grep -rnE 'getoption animations:enabled|keyword animations:enabled|HyprlandConfigOption' "$SHELL_ROOT/modules/koompi/sidebarRight/quickToggles" "$SHELL_ROOT/modules/common/models/quickToggles" > /dev/null; then
    fail "a quick toggle still reads or writes a held option itself"
fi
for toggle in "$SHELL_ROOT/modules/common/models/quickToggles/GameModeToggle.qml" "$SHELL_ROOT/modules/koompi/sidebarRight/quickToggles/classicStyle/GameMode.qml"; do
    grep -q 'HyprlandModes.gameMode' "$toggle" || fail "${toggle#"$SHELL_ROOT"/} does not read HyprlandModes.gameMode"
done
grep -q 'HyprlandModes.load()' "$SHELL_ROOT/shell.qml" || fail "shell.qml never loads HyprlandModes, so Reduce Motion would wait for a toggle to be built"
(( failed )) || echo "ok   source: $(wc -w <<< "$keys") held options, each named only in HyprlandModes.qml; both Game mode toggles read its flag"

for tool in kwin_wayland qs dbus-run-session python Hyprland hyprctl jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit "$failed"; }
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
RUN=""
trap 'rm -rf "$WORK"; [[ -n "$RUN" ]] && rm -rf "$RUN"' EXIT
RUN="$(mktemp -d /tmp/hr.XXXXXX)" || { fail "mktemp -d for the runtime dir failed"; exit 1; }
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/config/koompi" "$WORK/state/quickshell/user" "$WORK/cache" "$WORK/data" "$WORK/venv/bin"
chmod 700 "$RUN"
: > "$WORK/venv/bin/activate"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/state/quickshell/user/first_run.txt"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/modes_probe.qml" <<'QML'
import Quickshell
import Quickshell.Io
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles

ShellRoot {
    GameModeToggle {
        id: game
    }

    Component.onCompleted: HyprlandModes.load()

    IpcHandler {
        target: "modes"

        function reduceMotion(on: string): string {
            Config.options.appearance.reduceMotion = on === "on";
            return on;
        }

        function gameMode(): string {
            game.mainAction();
            return "ok";
        }

        function read(): string {
            return (HyprlandModes.ready ? "ready" : "loading") + " game=" + (game.toggled ? "on" : "off") + " reduce=" + (Config.options.appearance.reduceMotion ? "on" : "off");
        }
    }
}
QML

cat > "$WORK/drive.sh" <<'DRIVE'
#!/usr/bin/env bash
set -uo pipefail
cd "$WORK/shell" || exit 1
OVR="$WORK/config/hypr/hyprland/shellOverrides/main.lua"
CFG="$WORK/config/koompi/config.json"
OUT="$WORK/result.log"
ANIM='hl.config({animations={enabled=0}})'
GAME_LINES=(
    'hl.config({decoration={blur={enabled=0}}})'
    'hl.config({decoration={shadow={enabled=0}}})'
    'hl.config({decoration={rounding=0}})'
    'hl.config({general={gaps_in=0}})'
    'hl.config({general={gaps_out=0}})'
    'hl.config({general={border_size=1}})'
    'hl.config({general={allow_tearing=1}})'
)

verdict() { if [[ $1 == ok ]]; then echo "PASS $2" >> "$OUT"; else echo "FAIL $2" >> "$OUT"; fi; }
has() { grep -qF -- "$1" "$OVR" 2> /dev/null; }
lacks() { ! has "$1"; }
all_game() { local l; for l in "${GAME_LINES[@]}"; do has "$l" || return 1; done; }
no_game() { local l; for l in "${GAME_LINES[@]}"; do has "$l" && return 1; done; return 0; }
until_ok() { local n=$(( $1 * 10 )) i; shift; for (( i = 0; i < n; i++ )); do "$@" && return 0; sleep 0.1; done; return 1; }
modes() { qs -p modes_probe.qml ipc call modes "$@" 2> /dev/null; }
is_ready() { [[ "$(modes read)" == ready* ]]; }
start_qs() {
    qs -p modes_probe.qml > "$WORK/qs-$1.log" 2>&1 &
    QS=$!
    until_ok 40 is_ready || verdict bad "$1: the probe never became ready"
}
stop_qs() { kill "$QS" 2> /dev/null; wait "$QS" 2> /dev/null; }
check() { # description, command...
    local text=$1; shift
    if "$@"; then verdict ok "$text"; else verdict bad "$text"; fi
}
reads() { [[ "$(modes read)" == *"$1"* ]]; }
inode() { stat -c %i "$OVR" 2> /dev/null; }
seed() { mkdir -p "$(dirname -- "$OVR")"; printf '%s\n' '-- managed' "$@" > "$OVR"; }
config() { printf '{"windows":{"workspaceHelp":false}%s}\n' "$1" > "$CFG"; }

# --- 1. the four sequences, on a clean start ---
config ''
rm -f "$OVR"
start_qs a
check "a clean start reads game mode off" reads game=off
check "a clean start writes nothing" lacks "$ANIM"

modes reduceMotion on
check "reduce motion on holds animations:enabled" until_ok 8 has "$ANIM"
check "reduce motion alone leaves the Game mode toggle reading off" reads game=off
modes gameMode
check "then game mode on adds its own options" until_ok 8 all_game
check "and the toggle reads on" reads game=on
modes gameMode
check "then game mode off hands its own options back" until_ok 8 no_game
check "reduce motion on, game mode off: animations stay off" has "$ANIM"
check "reduce motion on, game mode off: the Game mode toggle reads off" reads game=off
modes reduceMotion off
check "then reduce motion off resets animations:enabled" until_ok 8 lacks "$ANIM"

modes gameMode
check "game mode on: all its options held, animations among them" until_ok 8 all_game
check "game mode on alone holds animations:enabled" has "$ANIM"
modes reduceMotion on
sleep 1.2
modes reduceMotion off
sleep 1.2
check "game mode on, reduce motion on then off: animations stay off" has "$ANIM"
check "and the other options stay held" all_game
check "and the toggle still reads on" reads game=on
modes gameMode
check "both off: every held option is reset" until_ok 8 no_game
check "both off: animations:enabled is reset to the user's own value" lacks "$ANIM"
check "both off: the toggle reads off" reads game=off
stop_qs

# --- 2. a restart with game mode in the file: read back, nothing rewritten ---
config ''
seed "$ANIM" "${GAME_LINES[@]}"
before="$(inode)"
start_qs b
check "a restart reads game mode back from the file" reads game=on
sleep 2.5
check "and rewrites nothing, the file already agrees" test "$(inode)" = "$before"
modes gameMode
check "then game mode off clears every option, animations included" until_ok 8 no_game
check "and animations:enabled with them" lacks "$ANIM"
stop_qs

# --- 3. a hold no mode wants is released on start ---
config ''
seed "$ANIM"
start_qs c
check "a stale animations hold is released on start" until_ok 8 lacks "$ANIM"
check "and game mode reads off" reads game=off
stop_qs

# --- 4. reduce motion saved in config.json is applied on start; once applied, nothing is rewritten ---
config ',"appearance":{"reduceMotion":true}'
rm -f "$OVR"
start_qs d
check "reduce motion in config.json holds animations:enabled on start" until_ok 8 has "$ANIM"
check "and reads on beside game mode off" reads "game=off reduce=on"
stop_qs
config ',"appearance":{"reduceMotion":true}'
before="$(inode)"
start_qs e
sleep 2.5
check "a restart that already agrees rewrites nothing" test "$(inode)" = "$before"
check "and the hold is still there" has "$ANIM"
stop_qs

# --- 5. the real compositor: a nested Hyprland holds what the shell wrote ---
mkdir -p "$WORK/config/hypr"
cat > "$WORK/config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({
    misc = { disable_watchdog_warning = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    animations = { enabled = true },
    general = { gaps_in = 4, gaps_out = 5 },
    decoration = { rounding = 18 },
})
require("hyprland.shellOverrides.main")
LUA
config ''
seed
parent=$WAYLAND_DISPLAY
Hyprland -c "$WORK/config/hypr/hyprland.lua" > "$WORK/hyprland.log" 2>&1 &
HYPR=$!
sig=""
for _ in $(seq 1 100); do sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2> /dev/null | head -1); [[ -n $sig ]] && break; sleep 0.2; done
disp=""
for _ in $(seq 1 100); do disp=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | grep -v "^$parent$" | head -1); [[ -n $disp ]] && break; sleep 0.2; done
export HYPRLAND_INSTANCE_SIGNATURE=$sig WAYLAND_DISPLAY=$disp
animations_is() { [[ "$(hyprctl getoption animations:enabled -j 2> /dev/null | jq -r .bool)" == "$1" ]]; }
gaps_are() { [[ "$(hyprctl getoption general:gaps_in -j 2> /dev/null | jq -r .css)" == "$1" ]]; }
rounding_is() { [[ "$(hyprctl getoption decoration:rounding -j 2> /dev/null | jq -r .int)" == "$1" ]]; }
steady() { sleep 1.5; "$@"; }

start_qs f
check "the compositor starts with animations on and the user's own gaps and rounding" animations_is true
check "and its gaps are the user's" gaps_are "4 4 4 4"
modes reduceMotion on
check "reduce motion on: Hyprland's animations are off" until_ok 8 animations_is false
modes gameMode
check "game mode on: Hyprland drops its gaps and rounding" until_ok 8 gaps_are "0 0 0 0"
check "and rounding" rounding_is 0
modes gameMode
check "game mode off: Hyprland takes its gaps back" until_ok 8 gaps_are "4 4 4 4"
check "and rounding" rounding_is 18
check "reduce motion on, game mode off: Hyprland's animations stay off" steady animations_is false
modes reduceMotion off
check "reduce motion off: Hyprland's animations are on again" until_ok 8 animations_is true
modes gameMode
check "game mode on: animations off with the rest" until_ok 8 gaps_are "0 0 0 0"
check "and animations off" animations_is false
modes reduceMotion on
sleep 1
modes reduceMotion off
check "game mode on, reduce motion on then off: Hyprland's animations stay off" steady animations_is false
modes gameMode
check "both off: Hyprland's animations are the user's again" until_ok 8 animations_is true
check "and its gaps" gaps_are "4 4 4 4"
check "and its rounding" rounding_is 18
check "and Hyprland reports no config error from any of it" test -z "$(hyprctl configerrors 2> /dev/null | tr -d '[:space:]')"
stop_qs
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
wait "$HYPR" 2> /dev/null
export WAYLAND_DISPLAY=$parent
unset HYPRLAND_INSTANCE_SIGNATURE

echo DONE >> "$OUT"
DRIVE
chmod +x "$WORK/drive.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" ILLOGICAL_IMPULSE_VIRTUAL_ENV="$WORK/venv" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
    XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$RUN" \
    timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/drive.sh" > "$WORK/kwin.log" 2>&1

[[ -f "$WORK/result.log" ]] && cat "$WORK/result.log"
if ! grep -qx DONE "$WORK/result.log" 2> /dev/null || grep -q '^FAIL' "$WORK/result.log" 2> /dev/null; then
    echo "--- last overrides file ---" >&2
    cat "$WORK/config/hypr/hyprland/shellOverrides/main.lua" >&2 2> /dev/null
    for log in "$WORK"/qs-*.log; do
        [[ -f "$log" ]] || continue
        echo "--- $(basename -- "$log") ---" >&2
        sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" | tail -15 >&2
    done
    fail "the Hyprland modes did not hold"
fi
(( failed )) && exit 1
echo "ok   modes: reduce motion and game mode hold animations:enabled between them, in either order, and the toggle shows only game mode"
