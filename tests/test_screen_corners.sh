#!/usr/bin/env bash
# a corner window exists only for a job (fake rounding, hot corner); hot corners work with rounding off
# nested Hyprland in headless KWin, probe shell with ScreenCorners alone, config.json rewritten per phase
# the nested compositor has no pointer, so wl_virtual_pointer.py gives it one: hl.dsp.cursor.move sends no events
# shellcheck disable=SC2016  # the $names in the want_json filters are jq variables
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }
die() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq python3; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nested Hyprland not run"; exit 0; }
done

W=1280
H=800
WORK="$(mktemp -d)"
RUN="$WORK/no-session-yet"
trap 'rm -rf "$WORK" "$RUN"' EXIT
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$WORK/bin" "$WORK/shell" "$WORK/cfg"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<LUA
hl.monitor({ output = "", mode = "${W}x${H}", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

# shelld stub: the real one talks to the system bus
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

# each phase names all three keys, so none depends on the one before
cfg() { jq -n --argjson r "$2" --argjson e "$3" --argjson b "$4" \
    '{windows: {workspaceHelp: false}, appearance: {fakeScreenRounding: $r}, sidebar: {cornerOpen: {enable: $e, bottom: $b}}}' > "$WORK/cfg/$1.json"; }
cfg p1 0 true false
cfg p2 0 false false
cfg p3 1 false false
cfg p4 1 true true
cfg p5 0 true true
cfg p6 2 true false
cp "$WORK/cfg/p1.json" "$HOME_DIR/.config/koompi/config.json"

cat > "$WORK/shell/corner_probe.qml" <<'QML'
import qs
import qs.modules.common
import qs.panelFamilies
import qs.modules.koompi.screenCorners
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root
    property int leftToggles: 0
    property int rightToggles: 0

    PanelLoader { component: ScreenCorners {} }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() { root.leftToggles++; }
        function onSidebarRightOpenChanged() { root.rightToggles++; }
    }

    FloatingWindow {
        id: fullscreenProbe
        title: "corner-fs-probe"
        visible: false
    }

    IpcHandler {
        target: "probe"

        function sizes(): string {
            const c = Config.options.sidebar.cornerOpen;
            return `${Appearance.rounding.screenRounding} ${c.cornerRegionWidth} ${c.cornerRegionHeight}`;
        }
        function sidebars(): string {
            return `left=${GlobalStates.sidebarLeftOpen ? 1 : 0}/${root.leftToggles} right=${GlobalStates.sidebarRightOpen ? 1 : 0}/${root.rightToggles}`;
        }
        function reset(): void {
            GlobalStates.sidebarLeftOpen = false;
            GlobalStates.sidebarRightOpen = false;
            root.leftToggles = 0;
            root.rightToggles = 0;
        }
        function showWindow(): void {
            fullscreenProbe.visible = true;
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
parent=$WAYLAND_DISPLAY
Hyprland -c "$HOME/.config/hypr/hyprland.lua" > "$WORK/hyprland.log" 2>&1 &
for _ in $(seq 1 100); do sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2> /dev/null | head -1); [[ -n $sig ]] && break; sleep 0.2; done
export HYPRLAND_INSTANCE_SIGNATURE=$sig
for _ in $(seq 1 100); do d=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | grep -v "^$parent$" | head -1); [[ -n $d ]] && break; sleep 0.2; done
export WAYLAND_DISPLAY=$d

outputs() { hyprctl monitors -j 2> /dev/null | jq length; }
for _ in $(seq 1 80); do [[ $(outputs) -ge 1 ]] && break; sleep 0.5; done
if [[ $(outputs) -lt 1 ]]; then
    printf 'monitor\tmissing\n' >> "$WORK/readings"
    hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
    sleep 1
    exit 0
fi
printf 'monitor\tready\n' >> "$WORK/readings"

cd "$WORK/shell"
qs -p corner_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do qs -p corner_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done

probe() { qs -p corner_probe.qml ipc call probe "$@" 2> /dev/null; }
note() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/readings"; }
mkfifo "$WORK/pointer.fifo"
exec 7<> "$WORK/pointer.fifo"
python3 -I "$POINTER" "$WIDTH" "$HEIGHT" 7>&- < "$WORK/pointer.fifo" > "$WORK/pointer.log" 2>&1 &
pointer_pid=$!
for _ in $(seq 1 40); do grep -q '^ready' "$WORK/pointer.log" 2> /dev/null && break; sleep 0.25; done
note pointer "$(hyprctl devices -j 2> /dev/null | jq '.mice | length')"
move() { # x y: returns once the compositor has taken the move
    local before
    before=$(grep -c '^moved' "$WORK/pointer.log")
    echo "$1 $2" >&7
    for _ in $(seq 1 30); do [[ $(grep -c '^moved' "$WORK/pointer.log") -gt $before ]] && return; sleep 0.1; done
}
setcfg() {
    cp "$WORK/cfg/$1.json" "$HOME/.config/koompi/config.json.tmp" && mv "$HOME/.config/koompi/config.json.tmp" "$HOME/.config/koompi/config.json"
}
corner_layers() {
    hyprctl layers -j 2> /dev/null | jq -c '[.[].levels[][]? | select(.namespace == "quickshell:screenCorners") | {x, y, w, h}] | sort_by(.y, .x)'
}
fullscreen_state() { hyprctl activewindow -j 2> /dev/null | jq -r '(.fullscreen // 0) | tostring'; }
is_fullscreen() { case "$(fullscreen_state)" in 0 | false | '') return 1 ;; esac; }

note sizes "$(probe sizes)"

# wait for a change, then 1 s of quiet
prev='[]'
await_layers() {
    local now
    for _ in $(seq 1 40); do
        now=$(corner_layers)
        [[ -n $now && $now != "$prev" ]] && break
        sleep 0.5
    done
    sleep 1
    prev=$(corner_layers)
    note "layers.$1" "$prev"
}

# from the middle, so the pointer enters the corner window instead of starting in it
hover() { # tag, x, y
    local state=''
    probe reset > /dev/null
    move $((WIDTH / 2)) $((HEIGHT / 2))
    move "$2" "$3"
    for _ in $(seq 1 20); do
        state=$(probe sidebars)
        [[ $state != 'left=0/0 right=0/0' ]] && break
        sleep 0.25
    done
    sleep 1
    note "hover.$1" "$(probe sidebars)"
    note "cursor.$1" "$(hyprctl cursorpos 2> /dev/null)"
}

# a pointer resting in the corner is moved again inside the 2 px that trigger: it must not toggle twice
jiggle() { # tag, x, y
    move "$2" "$3"
    sleep 1
    note "jiggle.$1" "$(probe sidebars)"
}

await_layers p1
hover p1.topright $((WIDTH - 1)) 3
jiggle p1.topright $((WIDTH - 2)) 3
hover p1.topleft 0 3

setcfg p2; await_layers p2
setcfg p3; await_layers p3
setcfg p4; await_layers p4
hover p4.bottomright $((WIDTH - 1)) $((HEIGHT - 3))
setcfg p5; await_layers p5
hover p5.bottomleft 0 $((HEIGHT - 3))

setcfg p6; await_layers p6
probe showWindow > /dev/null
for _ in $(seq 1 40); do [[ $(hyprctl activewindow -j 2> /dev/null | jq -r '.title // ""') == corner-fs-probe ]] && break; sleep 0.5; done
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })' > /dev/null 2>&1
for _ in $(seq 1 20); do is_fullscreen && break; sleep 0.5; done
note fullscreen "$(fullscreen_state)"
await_layers p6.fullscreen
hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })' > /dev/null 2>&1
await_layers p6.windowed

kill -0 "$qs_pid" 2> /dev/null && note qs alive || note qs dead
exec 7>&-
kill "$pointer_pid" 2> /dev/null
kill "$qs_pid" 2> /dev/null
sleep 1
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
SH
chmod +x "$WORK/inner.sh"

reading() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$WORK/readings" 2> /dev/null; }

run_session() {
    RUN="$(mktemp -d /tmp/hr.XXXXXX)"
    chmod 700 "$RUN"
    rm -f "$WORK/readings"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" WIDTH="$W" HEIGHT="$H" POINTER="$REPO_ROOT/tests/wl_virtual_pointer.py" \
        HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
        XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width "$((W + 200))" --height "$((H + 200))" \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
    rm -rf "$RUN"
}

dump() {
    echo "--- readings ---" >&2
    cat -- "$WORK/readings" >&2 2> /dev/null
    echo "--- pointer.log ---" >&2
    tail -n 5 -- "$WORK/pointer.log" >&2 2> /dev/null
    echo "--- qs.log ---" >&2
    grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2
    echo "--- hyprland.log ---" >&2
    grep -vE '^\s*$' "$WORK/hyprland.log" 2> /dev/null | tail -10 >&2
}

for attempt in 1 2 3; do
    run_session
    [[ "$(reading monitor)" == ready ]] && break
    echo "attempt $attempt: KWin gave the nested Hyprland no output, starting the session again" >&2
done
[[ "$(reading monitor)" == ready ]] || { dump; die "setup: the nested Hyprland never got an output from KWin, so no window can map"; }

read -r R RW RH <<< "$(reading sizes)"
[[ -n ${RH:-} ]] || { dump; die "setup: the probe shell never answered over IPC, so its windows cannot be read"; }
[[ "$(reading pointer)" -ge 1 ]] 2> /dev/null || { dump; die "setup: the nested compositor has no pointer, so nothing can hover"; }
BW=$(( R > RW ? R : RW ))
BH=$(( R > RH ? R : RH ))

want_json() { jq -cn --argjson W "$W" --argjson H "$H" --argjson R "$R" --argjson RW "$RW" --argjson RH "$RH" --argjson BW "$BW" --argjson BH "$BH" "$1"; }
check_layers() { # phase, what, jq array of {x,y,w,h} sorted by y then x
    local got want
    got="$(reading "layers.$1" | jq -c . 2> /dev/null)"
    want="$(want_json "$3")"
    if [[ "$got" == "$want" ]]; then echo "ok   layers: $2"; else fail "$2: corner windows are ${got:-missing}, want $want"; fi
}
check_hover() { # phase, what, want, x, y
    local got at
    at="$(reading "cursor.$1")"
    if [[ "$at" != "$4, $5" ]]; then fail "setup: moving the pointer into the corner left it at '${at:-nowhere}', want '$4, $5'"; return; fi
    got="$(reading "hover.$1")"
    if [[ "$got" == "$3" ]]; then echo "ok   hover: $2"; else fail "$2: sidebars read '${got:-missing}', want '$3'"; fi
}

TOP_BOTH='[{x:0,y:0,w:$BW,h:$BH},{x:($W-$BW),y:0,w:$BW,h:$BH},{x:0,y:($H-$R),w:$R,h:$R},{x:($W-$R),y:($H-$R),w:$R,h:$R}]'

check_layers p1 "rounding off, corners on: only the top pair exists, each the size of its region" \
    '[{x:0,y:0,w:$RW,h:$RH},{x:($W-$RW),y:0,w:$RW,h:$RH}]'
check_hover p1.topright "the pointer in the top-right corner opens the right sidebar with the rounding off" 'left=0/0 right=1/1' $((W - 1)) 3
check_hover p1.topleft "the pointer in the top-left corner opens the left sidebar with the rounding off" 'left=1/1 right=0/0' 0 3
check_jiggle="$(reading jiggle.p1.topright)"
if [[ "$check_jiggle" == 'left=0/0 right=1/1' ]]; then echo "ok   hover: a second move inside the trigger zone leaves the sidebar alone"; else fail "a second move inside the trigger zone toggled the sidebar again: sidebars read '${check_jiggle:-missing}', want 'left=0/0 right=1/1'"; fi
check_layers p2 "rounding off, corners off: no corner window" '[]'
check_layers p3 "rounding always, corners off: four rounding-sized windows" \
    '[{x:0,y:0,w:$R,h:$R},{x:($W-$R),y:0,w:$R,h:$R},{x:0,y:($H-$R),w:$R,h:$R},{x:($W-$R),y:($H-$R),w:$R,h:$R}]'
check_layers p4 "rounding always, corners at the bottom: the bottom pair grows to hold its region" \
    '[{x:0,y:0,w:$R,h:$R},{x:($W-$R),y:0,w:$R,h:$R},{x:0,y:($H-$BH),w:$BW,h:$BH},{x:($W-$BW),y:($H-$BH),w:$BW,h:$BH}]'
check_hover p4.bottomright "the pointer in the bottom-right corner opens the right sidebar through a window that also draws the rounding" 'left=0/0 right=1/1' $((W - 1)) $((H - 3))
check_layers p5 "rounding off, corners at the bottom: only the bottom pair exists" \
    '[{x:0,y:($H-$RH),w:$RW,h:$RH},{x:($W-$RW),y:($H-$RH),w:$RW,h:$RH}]'
check_hover p5.bottomleft "the pointer in the bottom-left corner opens the left sidebar" 'left=1/1 right=0/0' 0 $((H - 3))
check_layers p6 "rounding when not fullscreen, corners on top: the top pair holds both jobs" "$TOP_BOTH"
case "$(reading fullscreen)" in 0 | false | '') fail "setup: the probe window never went fullscreen" ;; esac
check_layers p6.fullscreen "a fullscreen window takes every corner window down" '[]'
check_layers p6.windowed "leaving fullscreen brings them back" "$TOP_BOTH"
if [[ "$(reading qs)" == alive ]]; then echo "ok   probe shell: still running after every window came and went"; else fail "the shell died while corner windows came and went"; fi
errors="$(grep -E 'screenCorners/.*(TypeError|ReferenceError|Cannot assign|Binding loop|ERROR)|(TypeError|ReferenceError|Cannot assign|Binding loop|ERROR).*screenCorners/' "$WORK/qs.log" 2> /dev/null)"
if [[ -z "$errors" ]]; then echo "ok   probe shell: no QML errors from the corner windows"; else fail "QML errors from the corner windows:
$errors"; fi

(( failed == 0 )) || { dump; exit 1; }
