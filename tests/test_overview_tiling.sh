#!/usr/bin/env bash
# The overview draws the desks in use side by side, each with its tiles where they sit, plus one
# "next free" slot. Three windows on desk 1 and one on desk 3 are tiled by a nested Hyprland; the
# real shell is opened with its own global and read through its `overview state` IPC (every desk
# and tile is an item with an objectName). Keys go in with wtype, the drag with a virtual pointer.
# Pass conditions are Hyprland's own: activeworkspace, activewindow and the clients' workspaces.
# Nothing here reaches the running session: nested in a headless KWin on a private bus.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq kitty wtype; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$(mktemp -d /tmp/hr.XXXXXX)"
trap 'rm -rf "${WORK:?}" "${RUN:?}"' EXIT
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$WORK/bin"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
printf '{"windows": {"workspaceHelp": false}}\n' > "$HOME_DIR/.config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/easyeffects"
chmod +x "$WORK/bin/easyeffects"

cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

# the daemon's wire format is shell-services/shelld/PROTOCOL.md; the state is hyprctl's own JSON
cat > "$WORK/bin/koompi-shelld" <<'SH'
#!/usr/bin/env bash
printf '{"type":"hello","protocol":1}\n'
while sleep 0.3; do
    printf '{"type":"state","service":"hyprland","state":{"connected":true,"windows":%s,"workspaces":%s,"workspaces_numbered":%s,"active_workspace":%s,"active_window":%s,"monitors":%s,"layers":{}}}\n' \
        "$(hyprctl clients -j | jq -c .)" "$(hyprctl workspaces -j | jq -c .)" \
        "$(hyprctl workspaces -j | jq -c '[.[] | select(.id >= 1 and .id <= 100)]')" \
        "$(hyprctl activeworkspace -j | jq -c .)" "$(hyprctl activewindow -j | jq -c 'if .address then . else null end')" \
        "$(hyprctl monitors -j | jq -c .)" || exit 0
done
SH
chmod +x "$WORK/bin/koompi-shelld"

have_pointer=0
"$REPO_ROOT/tests/vpointer/build.sh" "$WORK/vp" > /dev/null 2>&1 && have_pointer=1

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || exit 1

note() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/readings"; }
ov() { qs -p "$SHELL_ROOT" ipc call overview state 2> /dev/null; }
hl() { hyprctl dispatch "$1" > /dev/null 2>&1; }
toggle() { hl 'hl.dsp.global("quickshell:overviewWorkspacesToggle")'; }
await() { local i; for ((i = 0; i < 60; i++)); do "$@" && return 0; sleep 0.25; done; return 1; }
clients() { hyprctl clients -j | jq 'length'; }
has_clients() { [[ $(clients) == "$1" ]]; }
open_state() { [[ $(ov | jq '(.tiles // []) | length') -gt 0 ]]; }
closed_state() { [[ $(ov | jq 'has("desks")') == false ]]; }
active_ws() { hyprctl activeworkspace -j | jq -r .id; }
active_class() { hyprctl activewindow -j | jq -r '.class // ""'; }
ws_of() { hyprctl clients -j | jq -r --arg c "$1" '.[] | select(.class == $c) | .workspace.id'; }

cd "$WORK" || exit 1
qs -p "$SHELL_ROOT" > "$WORK/qs.log" 2>&1 &
qs_pid=$!
await_up() { qs -p "$SHELL_ROOT" ipc show > /dev/null 2>&1; }
for _ in $(seq 1 80); do await_up && break; sleep 0.5; done

for name in alpha bravo charlie; do
    hl "hl.dsp.exec_cmd(\"kitty --class $name\")"
done
await has_clients 3
hl 'hl.dsp.focus({ workspace = 3 })'
hl 'hl.dsp.exec_cmd("kitty --class delta")'
await has_clients 4
sleep 1
hl 'hl.dsp.focus({ workspace = 1 })'
sleep 1

toggle
await open_state
ov > "$WORK/state-open.json"
note ws_before "$(active_ws)"

# keyboard: two Rights from the active desk, Enter goes there
wtype -k Right
sleep 0.3
wtype -k Right
sleep 0.3
ov > "$WORK/state-moved.json"
wtype -k Return
await closed_state
sleep 0.5
note after_enter "$(active_ws)"

# Escape closes
hl 'hl.dsp.focus({ workspace = 1 })'
sleep 0.5
toggle
await open_state
wtype -k Escape
note escape_closed "$(await closed_state && echo yes || echo no)"

# typing filters, Enter focuses the first match
toggle
await open_state
wtype -s 150 bravo
sleep 1
ov > "$WORK/state-filtered.json"
wtype -k Return
await closed_state
sleep 0.5
note after_filter "$(active_class)"

# drag alpha's tile onto the empty slot between desk 1 and desk 3
if [[ -d "$WORK/vp" ]]; then
    hl 'hl.dsp.focus({ workspace = 1 })'
    sleep 0.5
    toggle
    await open_state
    ov > "$WORK/state-drag.json"
    read -r fx fy tx ty < <(jq -r '(.origin) as $o
        | (.tiles[] | select(.class == "alpha")) as $t
        | (.desks[] | select(.isNew)) as $d
        | "\(($o.x + $t.x + $t.w / 2) | floor) \(($o.y + $t.y + $t.h / 2) | floor) \(($o.x + $d.x + $d.w / 2) | floor) \(($o.y + $d.y + $d.h / 2) | floor)"' "$WORK/state-drag.json")
    "$WORK/vp/vpointer" 1280 800 drag "$fx" "$fy" "$tx" "$ty" > "$WORK/vpointer.log" 2>&1
    note drag_rc "$?"
    await_moved() { [[ $(ws_of alpha) == 2 ]]; }
    await await_moved
    note drag_alpha_ws "$(ws_of alpha)"
    note drag_focus_stayed "$(active_ws)"
    toggle
fi

cp "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" "$WORK/hyprland-run.log" 2> /dev/null
hyprctl -j clients 2> /dev/null | jq -r '.[] | select(.pid > 0) | .pid' | xargs -r kill -TERM 2> /dev/null
sleep 1
kill "$qs_pid" 2> /dev/null
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" REPO_ROOT="$REPO_ROOT" SHELL_ROOT="$SHELL_ROOT" \
    HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$RUN/no-system-bus" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
    --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$WORK/readings" 2> /dev/null; }
dump() {
    echo "--- readings ---" >&2
    cat -- "$WORK/readings" >&2 2> /dev/null
    echo "--- qs.log ---" >&2
    sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log" 2> /dev/null | grep -vE 'qmlscanner|^\s*$' | tail -25 >&2
}
check() { # check <json> <jq filter> <expected> <message>
    local got
    got="$(jq -r "$2" "$WORK/$1" 2> /dev/null)"
    [[ "$got" == "$3" ]] && return 0
    dump
    fail "$4: got '$got', wanted '$3'"
}

[[ -s "$WORK/state-open.json" ]] || { dump; fail "setup: the overview never listed its tiles"; }
check state-open.json '[.desks[].id] | join(",")' "1,2,3" "the strip is not desks 1, the next free slot (2) and 3"
check state-open.json '[.desks[] | select(.isNew) | .id] | join(",")' "2" "the next free slot is not desk 2"
check state-open.json '[.tiles[] | select(.visible) | .desk] | sort | join(",")' "1,1,1,3" "the tiles are not three on desk 1 and one on desk 3"
check state-open.json '[.tiles[] | select(.desk == 1 and .visible)] as $t | [range(0; $t | length) as $i | range($i + 1; $t | length) as $j | $t[$i] as $a | $t[$j] as $b | select($a.x < $b.x + $b.w - 0.5 and $b.x < $a.x + $a.w - 0.5 and $a.y < $b.y + $b.h - 0.5 and $b.y < $a.y + $a.h - 0.5)] | length' "0" "tiles on desk 1 overlap"
check state-open.json '[.tiles[] | select(.w < 320 and .live)] | length' "0" "a tile narrower than 320 px is live"
check state-open.json '[.tiles[] | select(.w >= 320 and (.live | not))] | length' "0" "a tile 320 px or wider is not live"
check state-open.json '[.tiles[] | select(.w >= 320)] | length > 0' "true" "setup: no tile is wide enough to prove the live side of the rule"
echo "ok   overview: desks 1, next free 2, 3; three tiles on desk 1 that do not overlap, one on desk 3; live only at 320 px and up"

check state-moved.json '[.desks[] | select(.selected) | .id] | join(",")' "3" "two Rights did not select desk 3"
[[ "$(reading ws_before)" == 1 ]] || { dump; fail "setup: desk 1 was not active"; }
[[ "$(reading after_enter)" == 3 ]] || { dump; fail "Right, Right, Enter left desk '$(reading after_enter)' active, wanted 3"; }
[[ "$(reading escape_closed)" == yes ]] || { dump; fail "Escape did not close the overview"; }
echo "ok   keys: Right, Right selects desk 3 and Enter goes there; Escape closes"

check state-filtered.json '[.tiles[] | select(.visible) | .class] | join(",")' "bravo" "typing bravo did not leave exactly the bravo tile"
[[ "$(reading after_filter)" == bravo ]] || { dump; fail "Enter after typing bravo focused '$(reading after_filter)'"; }
echo "ok   filter: typing a window's class leaves its tile, Enter focuses it"

if [[ -d "$WORK/vp" ]]; then
    [[ "$(reading drag_rc)" == 0 ]] || { dump; cat "$WORK/vpointer.log" >&2; fail "the virtual pointer failed, rc $(reading drag_rc)"; }
    [[ "$(reading drag_alpha_ws)" == 2 ]] || { dump; fail "dragging alpha's tile onto the new-desk slot left it on desk '$(reading drag_alpha_ws)'"; }
    [[ "$(reading drag_focus_stayed)" == 1 ]] || { dump; fail "the drag followed the window to desk '$(reading drag_focus_stayed)'"; }
    echo "ok   drag: alpha's tile dropped on the new-desk slot moved the window to desk 2 without following"
else
    echo "skip: no gcc or wayland-scanner, the drag was not run"
fi
