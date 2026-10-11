#!/usr/bin/env bash
# Grouped windows (J55): the group chords are declared once, described, and bound to nothing else; a nested
# Hyprland registers them under those keys; and the dispatcher each one is declared with, run in that Hyprland,
# groups windows, moves them in, cycles the tabs, pulls one out and dissolves the group. A bind is run by the
# expression it was declared with (the recorder's `expr`, which is how the cheatsheet runs a row), because a
# key typed through wtype never reaches a compositor bind. Pass conditions are Hyprland's own `clients`.
# Nested in a headless KWin on a private bus; nothing here reaches the running session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$REPO_ROOT/dots/.config/hypr"
RECORDER="$REPO_ROOT/dots/.config/quickshell/koompi/services/hyprlandKeybinds/recorder.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$HYPR/hyprland/keybinds_groups.lua" ]] || fail "dots/.config/hypr/hyprland/keybinds_groups.lua is missing"
grep -q 'require("hyprland.keybinds_groups")' "$HYPR/hyprland.lua" || fail "hyprland.lua does not require hyprland.keybinds_groups"
grep -q 'hyprland.keybinds_groups' "$REPO_ROOT/dots/.config/quickshell/koompi/services/HyprlandKeybinds.qml" \
    || fail "HyprlandKeybinds.qml does not replay hyprland.keybinds_groups, so the cheatsheet would not list the chords"
for tool in lua jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, the group chords were not read"; exit 0; }
done

# description|modifier mask (Super 64 + Alt 8, or + Shift 1)|key
WANT="Window: Group or ungroup|72|G
Window: Pull out of its group|65|G
Window: Move into the group left|72|Left
Window: Move into the group right|72|Right
Window: Move into the group up|72|Up
Window: Move into the group down|72|Down
Window: Next tab in the group|72|BracketRight
Window: Previous tab in the group|72|BracketLeft"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}" "${RUN:-$WORK/none}"' EXIT
lua "$RECORDER" "$HYPR" hyprland.keybinds hyprland.keybinds_shell_extra hyprland.keybinds_groups custom.keybinds > "$WORK/all.json" 2> "$WORK/err" \
    || { cat "$WORK/err" >&2; fail "recorder could not replay the shipped keybinds"; }
lua "$RECORDER" "$HYPR" hyprland.keybinds_groups > "$WORK/binds.json" || fail "recorder could not replay keybinds_groups.lua"
while IFS='|' read -r desc mask key; do
    got="$(jq -r --arg d "$desc" '[.[] | select(.description == $d)] | map("\(.modmask)|\(.key)") | join(",")' "$WORK/all.json")"
    [[ "$got" == "$mask|$key" ]] || fail "'$desc' is bound as '$got', wanted '$mask|$key'"
    others="$(jq -r --arg d "$desc" --argjson m "$mask" --arg k "$key" '[.[] | select(.modmask == $m and (.key | ascii_downcase) == ($k | ascii_downcase) and .description != $d and (.description | length) > 0)] | length' "$WORK/all.json")"
    [[ "$others" == 0 ]] || fail "the chord of '$desc' is bound to $others other action(s)"
done <<< "$WANT"
echo "ok   binds: eight described group chords, each bound once and to nothing else"

for tool in Hyprland hyprctl kwin_wayland dbus-run-session kitty; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, the nested group run was skipped"; exit 0; }
done

RUN="$(mktemp -d /tmp/hr.XXXXXX)"
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.local/share" "$HOME_DIR/.cache"
printf '%s\n' "$WANT" > "$WORK/want.txt"

cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<LUA
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
dofile("$HYPR/hyprland/keybinds_groups.lua")
LUA

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || exit 1

note() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/readings"; }
hl() { hyprctl dispatch "$1" > /dev/null 2>&1; }
await() { local i; for ((i = 0; i < 60; i++)); do "$@" && return 0; sleep 0.25; done; return 1; }
has_clients() { [[ $(hyprctl clients -j | jq 'length') == "$1" ]]; }
addr_of() { hyprctl clients -j | jq -r --arg c "$1" '.[] | select(.class == $c) | .address'; }
focus() { hl "hl.dsp.focus({ window = \"address:$(addr_of "$1")\" })"; sleep 0.3; }
press() { # press <description>: the dispatcher that bind was declared with
    local expr
    expr="$(jq -r --arg d "$1" '.[] | select(.description == $d) | .expr' "$WORK/binds.json")"
    [[ -n $expr && $expr != null ]] || { note missing "$1"; return 1; }
    hl "$expr"
    sleep 0.5
}
active() { hyprctl activewindow -j | jq -r '.class'; }
size_of() { hyprctl clients -j | jq -r --arg c "$1" '.[] | select(.class == $c) | .grouped | length'; }
sizes() { printf '%s,%s,%s' "$(size_of a)" "$(size_of b)" "$(size_of c)"; }

# every chord is registered under its key, as `hyprctl binds` reports it
missing=""
while IFS='|' read -r desc mask key; do
    hyprctl binds -j | jq -e --arg d "$desc" --argjson m "$mask" --arg k "$key" \
        'any(.[]; .description == $d and .modmask == $m and (.key | ascii_downcase) == ($k | ascii_downcase))' > /dev/null || missing+="$desc; "
done < "$WORK/want.txt"
note unregistered "$missing"

cd "$WORK" || exit 1
for name in a b c; do hl "hl.dsp.exec_cmd(\"kitty --class $name\")"; sleep 1; done
await has_clients 3
sleep 1
note start "$(sizes)"

focus a
press "Window: Group or ungroup"
note after_toggle "$(sizes)"
focus c
press "Window: Move into the group left"
note after_c_in "$(sizes)"
focus b
press "Window: Move into the group left"
note after_b_in "$(sizes)"

seq=("$(active)")
for _ in 1 2 3; do press "Window: Next tab in the group"; seq+=("$(active)"); done
note next_cycle "${seq[*]}"
seq=("$(active)")
for _ in 1 2 3; do press "Window: Previous tab in the group"; seq+=("$(active)"); done
note prev_cycle "${seq[*]}"

pulled="$(active)"
press "Window: Pull out of its group"
note pulled_class "$pulled"
note after_pull "$(sizes)"
note pulled_alone "$(size_of "$pulled")"

focus "$(hyprctl clients -j | jq -r '[.[] | select(.grouped | length > 1)][0].class')"
press "Window: Group or ungroup"
note after_dissolve "$(sizes)"

hyprctl -j clients 2> /dev/null | jq -r '.[] | select(.pid > 0) | .pid' | xargs -r kill -TERM 2> /dev/null
sleep 1
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" REPO_ROOT="$REPO_ROOT" \
    HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$RUN/no-system-bus" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 200 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
    --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$WORK/readings" 2> /dev/null; }
dump() {
    echo "--- readings ---" >&2
    cat -- "$WORK/readings" >&2 2> /dev/null
}
expect() { # expect <key> <wanted> <message>
    [[ "$(reading "$1")" == "$2" ]] && return 0
    dump
    fail "$3: got '$(reading "$1")', wanted '$2'"
}
distinct3() { # a cycle of three tabs: four readings, the first and last equal, the three before distinct
    local -a v=($1)
    (( ${#v[@]} == 4 )) && [[ "${v[0]}" == "${v[3]}" && "${v[0]}" != "${v[1]}" && "${v[1]}" != "${v[2]}" && "${v[0]}" != "${v[2]}" ]]
}

[[ -s "$WORK/readings" ]] || { cat "$WORK/kwin.log" >&2; fail "setup: the nested Hyprland never ran"; }
expect unregistered "" "hyprctl binds in the nested Hyprland lacks chords"
echo "ok   nested: hyprctl binds lists all eight chords under their keys"
expect start "0,0,0" "setup: three plain windows"
expect after_toggle "1,0,0" "the group-toggle dispatcher did not make the focused window a group"
expect after_c_in "2,0,2" "move-into-group left did not move c into a's group"
expect after_b_in "3,3,3" "move-into-group left did not move b into the group"
echo "ok   dispatch: toggle makes a group, move-into-group left takes the next window in, and again; three tabs share one group"

distinct3 "$(reading next_cycle)" || { dump; fail "three next-tab dispatches did not visit every tab and come back"; }
distinct3 "$(reading prev_cycle)" || { dump; fail "three previous-tab dispatches did not visit every tab and come back"; }
read -r -a next <<< "$(reading next_cycle)"
read -r -a prev <<< "$(reading prev_cycle)"
[[ "${next[1]}" != "${prev[1]}" ]] || { dump; fail "next tab and previous tab went the same way"; }
echo "ok   tabs: next and previous cycle all three tabs, in opposite directions"

expect pulled_alone 0 "pull-out left $(reading pulled_class) in a group"
[[ "$(reading after_pull | tr ',' '\n' | grep -c '^2$')" == 2 ]] || { dump; fail "pull-out did not leave the other two grouped"; }
expect after_dissolve "0,0,0" "toggle on a group did not dissolve it"
echo "ok   out: pull-out takes the focused tab out alone; toggle on the rest dissolves the group"
