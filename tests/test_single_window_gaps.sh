#!/usr/bin/env bash
# One tiled window on a workspace fills it: no gap. Two or more keep gaps_in/gaps_out, a floating
# window does not count, and a scratchpad keeps its 30 px gap.
#
# Live: Hyprland nested in a headless KWin on a private bus. The config is the repo's real gap
# values plus the workspace-rules block lifted out of rules.lua, so the rule under test is the shipped one.
# Hyprland reports a window geometry inside its border, so [0,0,1280,800] also proves border 0.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$REPO_ROOT/dots/.config/hypr/hyprland/rules.lua"
GENERAL="$REPO_ROOT/dots/.config/hypr/hyprland/general.lua"
SELECTOR='w[t1]s[false]'

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q '^        gaps_in = 4,$' "$GENERAL" && grep -q '^        gaps_out = 5,$' "$GENERAL" || fail "general.lua no longer has gaps_in 4 and gaps_out 5"
grep -qF "hl.workspace_rule({ workspace = \"$SELECTOR\", gaps_out = 0, gaps_in = 0 })" "$RULES" || fail "rules.lua has no gap-free workspace rule for $SELECTOR"
grep -qF "workspace = \"$SELECTOR\" }, border_size = 0" "$RULES" || fail "rules.lua has no border_size 0 window rule for $SELECTOR"
echo "ok   source: rules.lua carries the single-window rule, general.lua keeps gaps 4 and 5"

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
hl.window_rule({ match = { title = "^floater$" }, float = true })
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({
    misc = { disable_watchdog_warning = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    general = { gaps_in = 4, gaps_out = 5, border_size = 1 },
})
LUA
    sed -n '/^-- ######## Workspace rules/,/^-- ######## Layer rules/p' "$RULES"
} > "$HOME_DIR/.config/hypr/hyprland.lua"

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log" || exit 1

tiled_count() { hyprctl clients -j | jq '[.[] | select(.floating == false and (.workspace.name | startswith("special") | not))] | length'; }
wait_count() {
    local want=$1 _
    for _ in $(seq 1 80); do
        [[ $(tiled_count) == "$want" ]] && sleep 1 && return 0
        sleep 0.25
    done
    return 1
}
wait_title() {
    local _
    for _ in $(seq 1 80); do
        hyprctl clients -j | jq -e --arg t "$1" '.[] | select(.title == $t)' > /dev/null && sleep 1 && return 0
        sleep 0.25
    done
    return 1
}
record() { echo "$1 $(hyprctl clients -j | jq -c --arg t "$2" '.[] | select(.title == $t) | [.at[0], .at[1], .size[0], .size[1]]')" >> "$WORK/readings"; }
open() { hyprctl dispatch "hl.dsp.exec_cmd(\"kitty --title $1\")" > /dev/null 2>&1; }

open one
wait_count 1 || echo "timeout one" >> "$WORK/readings"
record single one

open two
wait_count 2 || echo "timeout two" >> "$WORK/readings"
record pair-one one
record pair-two two

pkill -f 'kitty --title two' 2> /dev/null
wait_count 1 || echo "timeout back" >> "$WORK/readings"
record again one

open floater
wait_title floater || echo "timeout floater" >> "$WORK/readings"
sleep 2
record with-float one
pkill -f "kitty --title floater" 2> /dev/null
sleep 2
open floater
wait_title floater || echo "timeout floater" >> "$WORK/readings"
sleep 2
record with-float-again one

hyprctl dispatch 'hl.dsp.exec_cmd("kitty --title scratch", { workspace = "special:term" })' > /dev/null 2>&1
wait_title scratch || echo "timeout scratch" >> "$WORK/readings"
record scratch scratch

pkill -f 'kitty --title' 2> /dev/null
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
    timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
reading() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print }' "$WORK/readings" 2> /dev/null; }
dump() { echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null; tail -15 "$WORK/hyprland-run.log" >&2 2> /dev/null; }

# monitor 1280x800: gaps_out 5 insets a lone window to [5,5,1270,790]; no gaps fills [0,0,1280,800]
[[ -s $WORK/readings ]] || { dump; fail "setup: the probe recorded nothing"; }
grep -q '^timeout' "$WORK/readings" && { dump; fail "setup: a window never appeared"; }
[[ "$(reading single)" == "[0,0,1280,800]" ]] || { dump; fail "one tiled window is $(reading single), want [0,0,1280,800]"; }
echo "ok   one tiled window fills the output"
[[ "$(reading pair-one)" == "[6,6,629,788]" && "$(reading pair-two)" == "[645,6,629,788]" ]] || { dump; fail "two windows: got $(reading pair-one) and $(reading pair-two), want them inset by gaps_out 5, gaps_in 4 and a 1 px border"; }
echo "ok   two tiled windows keep the gaps: $(reading pair-one) and $(reading pair-two)"
[[ "$(reading again)" == "[0,0,1280,800]" ]] || { dump; fail "after closing one the remaining window is $(reading again), want [0,0,1280,800]"; }
echo "ok   closing one hands the whole output back"
[[ "$(reading with-float)" == "[0,0,1280,800]" ]] || { dump; fail "a floating window changed the tiled one: $(reading with-float)"; }
[[ "$(reading with-float-again)" == "[0,0,1280,800]" ]] || { dump; fail "a second floating window changed the tiled one: $(reading with-float-again)"; }
echo "ok   a floating window does not count as a second tiled one"
[[ "$(reading scratch)" == "[31,31,"* ]] || { dump; fail "scratchpad window is $(reading scratch), want its 30 px gap and 1 px border"; }
echo "ok   a scratchpad keeps its 30 px gap"
