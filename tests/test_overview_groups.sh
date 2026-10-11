#!/usr/bin/env bash
# J55: a group is one tile in the overview, with a badge counting its tabs. Three windows are grouped by
# Hyprland's own dispatchers in a nested Hyprland, a fourth is left alone, and the real shell reads them
# through its `overview state` IPC (every tile is an item with an objectName).
# GROUP_SHOTS=<dir> keeps what the screen showed. Nested in a headless KWin on a private bus.
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
dofile("@ROOT@/dots/.config/hypr/hyprland/groups.lua")
dofile("@COLORS@")
LUA
sed -i "s|@COLORS@|${GROUP_COLORS:-$REPO_ROOT/dots/.config/hypr/hyprland/colors.lua}|; s|@ROOT@|$REPO_ROOT|g" "$HOME_DIR/.config/hypr/hyprland.lua"

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

addr() { hyprctl clients -j | jq -r --arg c "$1" '.[] | select(.class == $c) | .address'; }
focus() { hl "hl.dsp.focus({ window = \"address:$(addr "$1")\" })"; sleep 0.4; }
for name in alpha bravo charlie delta; do
    hl "hl.dsp.exec_cmd(\"kitty --class $name --title $name\")"
    sleep 1
done
await has_clients 4
sleep 1
focus alpha
hl 'hl.dsp.group.toggle()'
sleep 0.4
focus bravo
hl 'hl.dsp.window.move({ into_group = "left" })'
sleep 0.4
focus charlie
hl 'hl.dsp.window.move({ into_group = "left" })'
sleep 1
focus bravo
hl 'hl.dsp.group.next()'
sleep 1
hyprctl clients -j | jq -c '[.[] | {class, g: (.grouped | length), hidden}]' > "$WORK/clients.json"
hyprctl activewindow -j | jq -r .class > "$WORK/active.txt"
for opt in 'group:groupbar:col.active' 'group:groupbar:col.inactive' 'group:groupbar:text_color' 'group:col.border_active'; do
    printf '%s %s\n' "$opt" "$(hyprctl getoption "$opt" -j 2>&1 | tr -d '\n')" >> "$WORK/options.txt"
done
shot() { [[ -n ${GROUP_SHOTS:-} ]] && grim "$GROUP_SHOTS/$1.png" 2>> "$WORK/grim.err"; return 0; }
sleep 1
shot group
toggle
await open_state
sleep 3
ov > "$WORK/state-open.json"
shot overview
toggle
await closed_state
[[ -n ${GROUP_SHOTS:-} ]] && cp "$WORK/options.txt" "$WORK/clients.json" "$GROUP_SHOTS/" 2> /dev/null

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
jq -e 'map(select(.g == 3)) | length == 3' "$WORK/clients.json" > /dev/null || { dump; cat "$WORK/clients.json" >&2; fail "setup: alpha, bravo and charlie are not one group of three"; }
check state-open.json '[.tiles[] | select(.visible)] | length' "2" "three grouped windows and one alone are not two tiles"
check state-open.json '[.tiles[] | select(.visible and .tabs == 3)] | length' "1" "the group's tile does not carry a badge of 3"
check state-open.json '[.tiles[] | select(.visible and .tabs == 1)] | length' "1" "the window alone carries a badge"
check state-open.json '[.tiles[] | select(.visible and .tabs == 3) | .class] | join(",")' "charlie" "the group tile is not the tab on show (charlie)"
echo "ok   overview: a group of three and one window alone are two tiles; the group's tile is the tab on show and counts 3, the lone window counts nothing"
