#!/usr/bin/env bash
# Every app widget (Super+`, Super+\, Super+Shift+D, Super+H, Super+Y) goes through one script and one rule
# block: floating, centred, 70% x 70%, on its own special workspace. A press shows it, the next hides it and
# gives focus back, a press from another desk shows it there. Ctrl+Super+S did the same as Super+S.
#
# Live: Hyprland nested in a headless KWin on a private bus. The window rules are the shipped ones, lifted
# out of rules.lua; the clients are kitty windows wearing each widget's class.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$REPO_ROOT/dots/.config/hypr/hyprland/rules.lua"
BINDS="$REPO_ROOT/dots/.config/hypr/hyprland/keybinds.lua"
NAMES="telegram discord whatsapp term sysmon"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

widget_binds="$(grep -c 'appScratch \.\.' "$BINDS")"
[[ $widget_binds == 5 ]] || fail "keybinds.lua has $widget_binds app widget binds through appScratch, want 5"
if grep -E 'special:(telegram|discord|whatsapp|term|sysmon)' "$BINDS"; then fail "a bind reaches a widget's special workspace without the one script"; fi
echo "ok   source: all 5 widget binds go through toggle_app_scratchpad.sh"

grep -qF 'size = {"(monitor_w*0.7)", "(monitor_h*0.7)"}' "$RULES" || fail "rules.lua has no shared 70% x 70% widget size"
for name in $NAMES; do
    grep -qF "special = \"$name\"" "$RULES" || fail "rules.lua widget table lacks $name"
done
if grep -E 'special:(telegram|discord|whatsapp|term|sysmon) silent' "$RULES"; then fail "a widget has its own workspace rule outside the shared block"; fi
echo "ok   source: one rule block gives every widget the same size"

if grep -q 'CTRL + SUPER + S"' "$BINDS"; then fail "Ctrl+Super+S is back: it did the same as Super+S"; fi
echo "ok   source: Ctrl+Super+S is gone, Super+S toggles the scratchpad"

for tool in Hyprland hyprctl kwin_wayland kitty dbus-run-session jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static check only"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$(mktemp -d /tmp/hr.XXXXXX)"
trap 'rm -rf "$WORK" "$RUN"' EXIT
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.local/state" "$HOME_DIR/.local/share" "$HOME_DIR/.cache"

{
    cat <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({
    misc = { disable_watchdog_warning = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})
LUA
    sed -n '/^-- app widgets (toggle_app_scratchpad/,/^end$/p' "$RULES"
} > "$HOME_DIR/.config/hypr/hyprland.lua"

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || exit 1

script="$REPO_ROOT/dots/.config/hypr/hyprland/scripts/toggle_app_scratchpad.sh"
by_class() { hyprctl clients -j | jq -c --arg c "$1" '[.[] | select(.class == $c)][0] // empty'; }
wait_class() { local _; for _ in $(seq 1 80); do [[ -n $(by_class "$1") ]] && return 0; sleep 0.25; done; return 1; }
shown() { hyprctl monitors -j | jq -r '.[0].specialWorkspace.name'; }
desk() { hyprctl monitors -j | jq -r '.[0].activeWorkspace.id'; }
focused() { hyprctl activewindow -j | jq -r '.class // ""'; }
note() { echo "$*" >> "$WORK/readings"; }
goto() { hyprctl dispatch "hl.dsp.focus({ workspace = $1 })" > /dev/null 2>&1; sleep 0.5; }

hyprctl dispatch 'hl.dsp.exec_cmd("kitty -o remember_window_size=no --class base")' > /dev/null 2>&1
wait_class base || note "timeout base"
sleep 1

widgets=(
    "telegram TelegramDesktop --title=Telegram"
    "discord discord"
    "whatsapp web.whatsapp.com"
    "term term-scratch"
    "sysmon TUI.sysmon-scratch"
)
for entry in "${widgets[@]}"; do
    read -r name class extra <<< "$entry"
    press() { "$script" "$name" "$class" "kitty -o remember_window_size=no --class $class $extra"; sleep 1.2; }
    goto 1
    press
    wait_class "$class" || { note "timeout $name"; continue; }
    sleep 1
    c="$(by_class "$class")"
    note "$name show $(jq -c '[.floating, .size[0], .size[1], .at[0], .at[1], .workspace.name]' <<< "$c") shown=$(shown)"
    press
    note "$name hide shown=[$(shown)] focus=$(focused)"
    goto 2
    press
    note "$name otherdesk desk=$(desk) shown=$(shown)"
    press
    goto 1
    pkill -f "kitty --class $class" 2> /dev/null
    sleep 1
    press
    wait_class "$class" || { note "timeout $name relaunch"; continue; }
    sleep 1
    note "$name relaunch shown=$(shown)"
    press
    pkill -f "kitty --class $class" 2> /dev/null
    sleep 1
done

pkill -f 'kitty --class' 2> /dev/null
sleep 1
cp "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" "$WORK/hyprland-run.log" 2> /dev/null
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" REPO_ROOT="$REPO_ROOT" \
    HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; tail -15 "$WORK/hyprland-run.log" >&2 2> /dev/null; }
[[ -s $WORK/readings ]] || { dump; fail "setup: the probe recorded nothing"; }
if grep -q '^timeout' "$WORK/readings"; then dump; fail "setup: a window never appeared"; fi

# 70% of 1280x800 is 896x560 centred at 192,120; a pixel or two of rounding is fine
near() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= 4) }'; }
for name in $NAMES; do
    line="$(grep "^$name show " "$WORK/readings")"
    read -r floating w h x y ws <<< "$(sed -E 's/^[a-z]+ show \[(.*)\] shown.*/\1/' <<< "$line" | tr -d '"' | tr ',' ' ')"
    [[ $floating == true ]] || { dump; fail "$name is not floating: $line"; }
    near "${w:-0}" 896 && near "${h:-0}" 560 || { dump; fail "$name is ${w}x${h}, want 896x560: $line"; }
    near "${x:-0}" 192 && near "${y:-0}" 120 || { dump; fail "$name is at $x,$y, want 192,120 (centred): $line"; }
    [[ $ws == "special:$name" && $line == *"shown=special:$name" ]] || { dump; fail "$name press did not show it on special:$name: $line"; }
    echo "ok   $name: floating, ${w}x${h} at $x,$y on $ws"
    grep -qE "^$name hide shown=\[\] focus=base$" "$WORK/readings" || { dump; fail "$name second press: $(grep "^$name hide" "$WORK/readings"), want hidden and focus back on base"; }
    echo "ok   $name: second press hides it and focus returns"
    grep -qE "^$name otherdesk desk=2 shown=special:$name$" "$WORK/readings" || { dump; fail "$name from desk 2: $(grep "^$name otherdesk" "$WORK/readings")"; }
    echo "ok   $name: from another desk it shows on that desk"
    grep -qE "^$name relaunch shown=special:$name$" "$WORK/readings" || { dump; fail "$name after the app was closed: $(grep "^$name relaunch" "$WORK/readings")"; }
    echo "ok   $name: closing the app does not break the next press"
done
