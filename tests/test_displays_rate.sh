#!/usr/bin/env bash
# koompi-displays rate: a monitor changes refresh rate at its current resolution
# and the layout is saved. hyprctl is a stub holding the founder's two monitors:
# HDMI-A-1 lists 74.97, 60 and 59.94 at 1920x1080 (60 twice) and 75 Hz modes at
# smaller sizes, eDP-1 lists one mode. The stub's eval applies WxH@R the way
# Hyprland resolves an explicit mode, the nearest listed rate at that size, so
# the script's read-back check has a state to read; which mode the compositor
# really picks is not exercised here, a nested Hyprland lists no modes.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.local/bin/koompi-displays"

failed=0
case_failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; case_failed=1; }
end_case() { (( case_failed )) || printf 'PASS %s\n' "$1"; case_failed=0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/config/hypr"

# PATH is the stub dir alone: no lua, no luac, and hyprctl never reaches the session.
for cmd in bash jq date mktemp mv rm sleep cat; do
    path="$(command -v "$cmd")" || { echo "FAIL: test host has no $cmd" >&2; exit 1; }
    ln -s "$path" "$stub/$cmd"
done

cat > "$tmp/monitors.json" <<'JSON'
[
  {"id": 0, "name": "eDP-1", "description": "BOE 3296", "width": 1920, "height": 1200,
   "refreshRate": 60.00300, "x": 0, "y": 0, "scale": 1, "transform": 0,
   "availableModes": ["1920x1200@60.00Hz"]},
  {"id": 1, "name": "HDMI-A-1", "description": "WAM 9088", "width": 1920, "height": 1080,
   "refreshRate": 60.00000, "x": 1920, "y": 0, "scale": 1.25, "transform": 0,
   "availableModes": ["1920x1080@60.00Hz", "1920x1080@74.97Hz", "1920x1080@59.94Hz", "1920x1080@60.00Hz",
     "1680x1050@59.95Hz", "1400x1050@59.98Hz", "1280x1024@75.03Hz", "1280x1024@60.02Hz", "1440x900@59.89Hz",
     "1280x960@60.00Hz", "1366x768@60.00Hz", "1152x864@75.00Hz", "1280x720@60.00Hz", "1280x720@59.94Hz",
     "1280x720@60.00Hz", "1024x768@60.00Hz", "1024x768@70.07Hz", "1024x768@75.03Hz", "832x624@74.55Hz",
     "800x600@56.25Hz", "800x600@60.32Hz", "800x600@72.19Hz", "800x600@75.00Hz", "640x480@59.94Hz",
     "640x480@66.67Hz", "640x480@72.81Hz", "640x480@72.01Hz", "640x480@75.00Hz", "640x480@60.00Hz",
     "720x400@70.08Hz"]}
]
JSON

cat > "$stub/hyprctl" <<'STUB'
#!/usr/bin/env bash
state="${HYPRCTL_STATE:?}"
if [[ $1 != eval ]]; then
    cat "$state"
    exit 0
fi
printf '%s\n' "$2" >> "${HYPRCTL_EVAL_LOG:?}"
[[ -z ${HYPRCTL_IGNORE_EVAL:-} ]] || exit 0
re='output = "([^"]+)", mode = "([0-9]+)x([0-9]+)@([0-9.]+)", position = "(-?[0-9]+)x(-?[0-9]+)", scale = ([0-9.]+)'
[[ $2 =~ $re ]] || exit 1
jq --arg n "${BASH_REMATCH[1]}" --argjson w "${BASH_REMATCH[2]}" --argjson h "${BASH_REMATCH[3]}" \
    --argjson r "${BASH_REMATCH[4]}" --argjson x "${BASH_REMATCH[5]}" --argjson y "${BASH_REMATCH[6]}" \
    --argjson s "${BASH_REMATCH[7]}" '
    map(if .name == $n then
        ([.availableModes[] | capture("^(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)Hz$")
          | select((.w | tonumber) == $w and (.h | tonumber) == $h) | (.r | tonumber)]
         | min_by(. - $r | fabs)) as $got
        | .width = $w | .height = $h | .x = $x | .y = $y | .scale = $s
        | if $got == null then . else .refreshRate = $got end
    else . end)' "$state" > "$state.new" && mv "$state.new" "$state"
STUB
chmod +x "$stub/hyprctl"

lua="$tmp/config/hypr/monitors.lua"
fresh() {
    cp "$tmp/monitors.json" "$tmp/state.json"
    : > "$tmp/eval.log"
    rm -f "$lua"
}
run_displays() {
    env -i PATH="$stub" HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" HYPRCTL_STATE="$tmp/state.json" \
        HYPRCTL_EVAL_LOG="$tmp/eval.log" HYPRCTL_IGNORE_EVAL="${HYPRCTL_IGNORE_EVAL:-}" \
        bash "$SCRIPT" "$@" > "$tmp/out" 2>&1
}
eval_lines() { wc -l < "$tmp/eval.log"; }
lua_text() { cat "$lua" 2> /dev/null; }
lua_has() { grep -qF -- "$1" "$lua" 2> /dev/null; }
config_files() { find "$tmp/config/hypr" -mindepth 1 -printf '%f '; }

# 74.97: one eval in place's form, position and scale kept, the saved layout exact
fresh
run_displays rate HDMI-A-1 74.97
status=$?
(( status == 0 )) || fail "rate HDMI-A-1 74.97 exited $status: $(cat "$tmp/out")"
want='hl.monitor({output = "HDMI-A-1", mode = "1920x1080@74.97", position = "1920x0", scale = 1.25})'
(( $(eval_lines) == 1 )) || fail "rate 74.97 wanted one hl.monitor eval, got: $(cat "$tmp/eval.log")"
[[ "$(cat "$tmp/eval.log")" == "$want" ]] || fail "rate 74.97 eval is not '$want': $(cat "$tmp/eval.log")"
saved=$'hl.monitor({\n    output = "eDP-1",\n    mode = "1920x1200@60",\n    position = "0x0",\n    scale = 1\n})\nhl.monitor({\n    output = "HDMI-A-1",\n    mode = "1920x1080@74.97",\n    position = "1920x0",\n    scale = 1.25\n})'
[[ "$(lua_text | tail -n +3)" == "$saved" ]] || fail "monitors.lua after rate 74.97 is not the saved layout: $(lua_text)"
[[ "$(config_files)" == "monitors.lua " ]] || fail "rate left more than monitors.lua in the config dir: $(config_files)"
if [[ -f "$lua" ]] && command -v luac > /dev/null 2>&1; then
    luac -p "$lua" || fail "the monitors.lua rate wrote is not valid lua"
fi
end_case "rate HDMI-A-1 74.97 applies 1920x1080@74.97 in place's form and saves the layout"

# 75.03 exists only at 1280x1024 and 1024x768: refused, nothing applied, nothing rewritten
fresh
printf -- '-- kept\n' > "$lua"
run_displays rate HDMI-A-1 75.03
status=$?
(( status != 0 )) || fail "rate HDMI-A-1 75.03 exited 0 although 1920x1080 has no 75.03 Hz mode"
grep -q 'does not list 75.03 Hz' "$tmp/out" || fail "the refusal does not say 75.03 is not listed: $(cat "$tmp/out")"
grep -q 'listed: 74.97 60 59.94' "$tmp/out" || fail "the refusal does not list the rates the monitor has: $(cat "$tmp/out")"
(( $(eval_lines) == 0 )) || fail "a refused rate still reached hyprctl eval: $(cat "$tmp/eval.log")"
[[ "$(lua_text)" == '-- kept' ]] || fail "a refused rate rewrote monitors.lua: $(lua_text)"
run_displays rate eDP-1 48
status=$?
(( status != 0 )) || fail "rate eDP-1 48 exited 0 although eDP-1 lists one mode, 60 Hz"
(( $(eval_lines) == 0 )) || fail "a refused eDP-1 rate still reached hyprctl eval"
end_case "a rate the monitor does not list at its resolution is refused, with the rates it has"

# 59.94 and 60 are different options and stay different in the saved rule
fresh
run_displays rate HDMI-A-1 59.94
status=$?
(( status == 0 )) || fail "rate HDMI-A-1 59.94 exited $status: $(cat "$tmp/out")"
lua_has 'mode = "1920x1080@59.94",' || fail "59.94 was not saved as 59.94: $(lua_text)"
run_displays rate HDMI-A-1 60
status=$?
(( status == 0 )) || fail "rate HDMI-A-1 60 exited $status: $(cat "$tmp/out")"
lua_has 'mode = "1920x1080@60",' || fail "60 was not saved as 60: $(lua_text)"
grep -qF 'mode = "1920x1080@60.00"' "$tmp/eval.log" || fail "60 was not applied as 1920x1080@60.00: $(cat "$tmp/eval.log")"
end_case "59.94 and 60 Hz are applied and saved as themselves"

# place re-applies a monitor's current rate exactly instead of rounding 74.97 to 75
fresh
jq '.[1].refreshRate = 74.97300' "$tmp/monitors.json" > "$tmp/state.json"
run_displays place HDMI-A-1 left
status=$?
(( status == 0 )) || fail "place HDMI-A-1 left exited $status: $(cat "$tmp/out")"
grep -qF 'output = "HDMI-A-1", mode = "1920x1080@74.97"' "$tmp/eval.log" \
    || fail "place did not keep HDMI-A-1 at 74.97: $(cat "$tmp/eval.log")"
lua_has 'mode = "1920x1080@74.97",' || fail "place did not save HDMI-A-1 at 74.97: $(lua_text)"
end_case "place keeps a chosen 74.97 Hz instead of rounding it to 75"

# a compositor that ignores the rule is reported, not saved as if it had worked
fresh
HYPRCTL_IGNORE_EVAL=1 run_displays rate HDMI-A-1 74.97
status=$?
(( status != 0 )) || fail "rate exited 0 although the compositor never switched"
grep -q 'did not switch to 74.97 Hz' "$tmp/out" || fail "the failure does not say the switch did not happen: $(cat "$tmp/out")"
[[ ! -e "$lua" ]] || fail "a rate that did not take was saved: $(lua_text)"
end_case "a switch the compositor did not make exits non-zero and saves nothing"

# no modes listed at all (a nested or virtual output), an unknown monitor, a word, no rate
fresh
jq '.[1].availableModes = []' "$tmp/monitors.json" > "$tmp/state.json"
run_displays rate HDMI-A-1 60
status=$?
(( status != 0 )) || fail "rate exited 0 for a monitor that lists no modes"
grep -q 'listed: none' "$tmp/out" || fail "the refusal does not say no rate is listed: $(cat "$tmp/out")"
run_displays rate DP-9 60
status=$?
(( status != 0 )) || fail "rate exited 0 for a monitor that does not exist"
grep -q 'unknown monitor DP-9' "$tmp/out" || fail "the refusal does not name the unknown monitor: $(cat "$tmp/out")"
run_displays rate HDMI-A-1 fast
status=$?
(( status != 0 )) || fail "rate exited 0 for a rate that is not a number"
run_displays rate HDMI-A-1
status=$?
(( status != 0 )) || fail "rate without a rate exited 0"
end_case "no modes, an unknown monitor, a word and a missing rate are all refused"

# the saved file goes through the validation place uses, and a rejected one leaves no temp file
fresh
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/luac"
chmod +x "$stub/luac"
run_displays rate HDMI-A-1 74.97
status=$?
(( status != 0 )) || fail "rate exited 0 although luac rejected the file"
grep -q 'failed lua validation' "$tmp/out" || fail "a rejected file was not reported: $(cat "$tmp/out")"
[[ -z "$(config_files)" ]] || fail "a file luac rejected left something in the config dir: $(config_files)"
rm -f "$stub/luac"
end_case "rate saves through the validation place uses"

# the consumer: Hyprland's own parser, offline and on a private home, reads what rate saved;
# a mode of banana is the negative control that its verdict means something
if command -v Hyprland > /dev/null 2>&1; then
    mkdir -p "$tmp/hv/run"
    chmod 700 "$tmp/hv/run"
    verify_config() {
        env -i PATH="$PATH" HOME="$tmp/hv" XDG_RUNTIME_DIR="$tmp/hv/run" \
            timeout 30 Hyprland --verify-config -c "$1" > "$tmp/verify.out" 2>&1
    }
    fresh
    run_displays rate HDMI-A-1 74.97
    if [[ -f "$lua" ]]; then
        # verify only parses, but no nested Hyprland config goes without update news off
        { echo 'hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })'; cat "$lua"; } > "$tmp/verify.lua"
        verify_config "$tmp/verify.lua" || fail "Hyprland's parser rejects what rate saved: $(cat "$tmp/verify.out")"
        sed 's/@74.97/@banana/' "$tmp/verify.lua" > "$tmp/bad.lua"
        ! verify_config "$tmp/bad.lua" || fail "Hyprland's parser accepts a mode of banana, so its verdict above proves nothing"
    else
        fail "rate saved no layout for Hyprland's parser to read"
    fi
    end_case "Hyprland's own parser accepts the saved layout and rejects a bad mode"
else
    echo "note: Hyprland is not installed, so its parser was not asked about the saved layout"
fi

(( failed )) && exit 1
echo "ok   displays rate: applied, saved, refused and failed loudly as above"
