#!/usr/bin/env bash
# koompi-displays rate, keep and revert: a switch saves nothing until it is kept, and an unanswered one goes back by itself
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
mkdir -p "$stub" "$tmp/config/hypr" "$tmp/run"
chmod 700 "$tmp/run"

for cmd in bash jq mktemp mv rm sleep cat mkdir setsid; do
    path="$(command -v "$cmd")" || { echo "FAIL: test host has no $cmd" >&2; exit 1; }
    ln -s "$path" "$stub/$cmd"
done
cp "$REPO_ROOT/tests/displays-hyprctl" "$stub/hyprctl"
chmod +x "$stub/hyprctl"

lua="$tmp/config/hypr/monitors.lua"
pending="$tmp/run/koompi-displays/pending"
want_74='hl.monitor({output = "HDMI-A-1", mode = "1920x1080@74.97", position = "1920x0", scale = 1.25})'
want_back='hl.monitor({output = "HDMI-A-1", mode = "1920x1080@60", position = "1920x0", scale = 1.25})'

fresh() {
    cp "$REPO_ROOT/tests/displays-monitors.json" "$tmp/state.json"
    : > "$tmp/eval.log"
    rm -rf "$lua" "$tmp/run/koompi-displays" "$tmp/state.json.ignore" "$tmp/state.json.broken" "$stub/luac"
}
run_displays() {
    env -i PATH="$stub" HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" XDG_RUNTIME_DIR="$tmp/run" \
        HYPRCTL_STATE="$tmp/state.json" HYPRCTL_EVAL_LOG="$tmp/eval.log" \
        ${CONFIRM:+KOOMPI_DISPLAYS_CONFIRM_SECONDS=$CONFIRM} bash "$SCRIPT" "$@" > "$tmp/out" 2>&1
}
eval_lines() { wc -l < "$tmp/eval.log"; }
eval_n() { sed -n "${1}p" "$tmp/eval.log"; }
lua_text() { cat "$lua" 2> /dev/null; }
config_files() { find "$tmp/config/hypr" -mindepth 1 -printf '%f '; }
hdmi_rate_is() { jq -e --argjson r "$1" '.[1].refreshRate == $r' "$tmp/state.json" > /dev/null; }
wait_until() {
    local tries=$1
    shift
    for ((i = 0; i < tries * 5; i++)); do "$@" && return 0; sleep 0.2; done
    return 1
}
two_evals() { (( $(eval_lines) >= 2 )); }

saved=$'hl.monitor({\n    output = "desc:BOE 0x0CE0",\n    mode = "1920x1200@60",\n    position = "0x0",\n    scale = 1,\n    transform = 0\n})\nhl.monitor({\n    output = "desc:WAM HDMI 18250023",\n    mode = "1920x1080@74.97",\n    position = "1920x0",\n    scale = 1.25,\n    transform = 0\n})'

fresh
run_displays rate HDMI-A-1 74.97
status=$?
(( status == 0 )) || fail "rate HDMI-A-1 74.97 exited $status: $(cat "$tmp/out")"
jq -e '.monitor == "HDMI-A-1" and .previous == 60 and .seconds >= 14 and .seconds <= 15' "$tmp/out" > /dev/null \
    || fail "rate did not print the monitor, the rate it goes back to and 15 seconds to answer: $(cat "$tmp/out")"
[[ "$(cat "$tmp/eval.log")" == "$want_74" ]] || fail "rate 74.97 sent '$(cat "$tmp/eval.log")', wanted '$want_74'"
[[ ! -e "$lua" ]] || fail "rate saved a layout before it was kept: $(lua_text)"
[[ -e "$pending" ]] || fail "rate left no record of the change it is waiting on"
run_displays keep
status=$?
(( status == 0 )) || fail "keep exited $status: $(cat "$tmp/out")"
[[ "$(lua_text | tail -n +3)" == "$saved" ]] || fail "keep did not save the layout the display-keyed way: $(lua_text)"
[[ "$(config_files)" == "monitors.lua " ]] || fail "keep left more than monitors.lua in the config dir: $(config_files)"
[[ ! -e "$pending" ]] || fail "keep left the record behind"
(( $(eval_lines) == 1 )) || fail "keep sent another mode change: $(cat "$tmp/eval.log")"
end_case "rate switches without saving, keep saves the layout"

fresh
printf -- '-- kept\n' > "$lua"
run_displays rate HDMI-A-1 74.97
run_displays revert
status=$?
(( status == 0 )) || fail "revert exited $status: $(cat "$tmp/out")"
[[ "$(eval_n 2)" == "$want_back" ]] || fail "revert sent '$(eval_n 2)', wanted '$want_back'"
hdmi_rate_is 60 || fail "revert left the monitor at $(jq '.[1].refreshRate' "$tmp/state.json")"
[[ "$(lua_text)" == '-- kept' ]] || fail "revert changed monitors.lua: $(lua_text)"
[[ ! -e "$pending" ]] || fail "revert left the record behind"
run_displays keep
status=$?
(( status != 0 )) || fail "keep exited 0 after a revert"
grep -q 'no refresh-rate change is waiting' "$tmp/out" || fail "keep after a revert did not say nothing is waiting: $(cat "$tmp/out")"
end_case "revert puts the old rate back and monitors.lua stays as it was"

fresh
printf -- '-- kept\n' > "$lua"
CONFIRM=4 run_displays rate HDMI-A-1 74.97
status=$?
(( status == 0 )) || fail "rate with a 4 s window exited $status: $(cat "$tmp/out")"
(( $(eval_lines) == 1 )) || fail "the revert had already happened when rate returned, so rate itself waited: $(cat "$tmp/eval.log")"
hdmi_rate_is 74.97 || fail "rate did not leave the monitor at 74.97 while it waits"
wait_until 12 two_evals || fail "no answer for 4 s and the monitor was not put back: $(cat "$tmp/eval.log")"
[[ "$(eval_n 2)" == "$want_back" ]] || fail "the timeout sent '$(eval_n 2)', wanted '$want_back'"
hdmi_rate_is 60 || fail "after the timeout the monitor runs $(jq '.[1].refreshRate' "$tmp/state.json"), not 60"
[[ "$(lua_text)" == '-- kept' ]] || fail "the timeout changed monitors.lua: $(lua_text)"
[[ ! -e "$pending" ]] || fail "the timeout left the record behind"
(( $(eval_lines) == 2 )) || fail "the timeout sent more than one mode change: $(cat "$tmp/eval.log")"
run_displays keep
status=$?
(( status != 0 )) || fail "keep exited 0 after the time ran out"
end_case "no answer: the old rate comes back by itself and monitors.lua is unchanged"

fresh
run_displays rate HDMI-A-1 74.97
run_displays place HDMI-A-1 left
status=$?
(( status != 0 )) || fail "place exited 0 while a rate change was waiting"
grep -q "waiting for an answer" "$tmp/out" || fail "place did not say a change is waiting: $(cat "$tmp/out")"
run_displays rate HDMI-A-1 59.94
status=$?
(( status != 0 )) || fail "a second rate exited 0 while one was waiting"
(( $(eval_lines) == 1 )) || fail "a refused command still reached hyprctl: $(cat "$tmp/eval.log")"
[[ ! -e "$lua" ]] || fail "a refused command saved a layout: $(lua_text)"
run_displays revert
end_case "while a change waits, place and a second rate are refused"

fresh
mkdir -p "$tmp/run/koompi-displays"
jq -n '{monitor: "HDMI-A-1", mode: "1920x1080@60", x: 1920, y: 0, scale: 1.25, centi: 6000, token: "dead", deadline: 1}' > "$pending"
jq '.[1].refreshRate = 74.973' "$tmp/state.json" > "$tmp/state.new" && mv "$tmp/state.new" "$tmp/state.json"
run_displays place HDMI-A-1 right
status=$?
(( status == 0 )) || fail "place exited $status after an expired record: $(cat "$tmp/out")"
[[ "$(eval_n 1)" == "$want_back" ]] || fail "an expired record was not put back before anything else, first eval: '$(eval_n 1)'"
[[ ! -e "$pending" ]] || fail "the expired record is still there"
end_case "a record whose timer died is undone before the next change"

fresh
touch "$tmp/state.json.ignore"
run_displays rate HDMI-A-1 74.97
status=$?
(( status != 0 )) || fail "rate exited 0 although the compositor never switched"
grep -q 'did not switch to 74.97 Hz' "$tmp/out" || fail "the failure does not say the switch did not happen: $(cat "$tmp/out")"
[[ ! -e "$lua" ]] || fail "a switch that did not take left a layout: $(lua_text)"
[[ ! -e "$pending" ]] || fail "a switch that did not take left a record waiting"
(( $(eval_lines) == 2 )) || fail "a switch that did not take was not undone: $(cat "$tmp/eval.log")"
end_case "a switch the compositor did not make fails loudly and leaves nothing waiting"

fresh
printf -- '-- kept\n' > "$lua"
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/luac"
chmod +x "$stub/luac"
run_displays rate HDMI-A-1 74.97
run_displays keep
status=$?
(( status != 0 )) || fail "keep exited 0 although luac rejected the file"
grep -q 'failed lua validation' "$tmp/out" || fail "a rejected file was not reported: $(cat "$tmp/out")"
[[ "$(config_files)" == "monitors.lua " ]] || fail "a rejected file left something in the config dir: $(config_files)"
[[ "$(lua_text)" == '-- kept' ]] || fail "a rejected file replaced monitors.lua: $(lua_text)"
hdmi_rate_is 60 || fail "a layout that could not be saved was left running at $(jq '.[1].refreshRate' "$tmp/state.json")"
end_case "keep that cannot save puts the old rate back instead"

fresh
printf -- '-- kept\n' > "$lua"
run_displays rate HDMI-A-1 74.97
touch "$tmp/state.json.broken"
run_displays keep
status=$?
(( status != 0 )) || fail "keep exited 0 although hyprctl could not list the monitors"
[[ "$(lua_text)" == '-- kept' ]] || fail "keep wrote a layout it had not read: $(lua_text)"
[[ "$(config_files)" == "monitors.lua " ]] || fail "keep left a temp file behind: $(config_files)"
end_case "keep that cannot read the monitors leaves monitors.lua alone"

fresh
printf -- '-- kept\n' > "$lua"
run_displays rate HDMI-A-1 74.97
jq '.[1].refreshRate = 60' "$tmp/state.json" > "$tmp/state.new" && mv "$tmp/state.new" "$tmp/state.json"
run_displays keep
status=$?
(( status != 0 )) || fail "keep exited 0 although the monitor was no longer at the rate it was asked to keep"
grep -q 'no longer at the new refresh rate' "$tmp/out" || fail "keep did not say the monitor had left the new rate: $(cat "$tmp/out")"
[[ "$(lua_text)" == '-- kept' ]] || fail "keep saved a rate the monitor was not running: $(lua_text)"
[[ ! -e "$pending" ]] || fail "keep left the record behind"
end_case "keep after a config reload dropped the new rate saves nothing"

fresh
printf -- '-- kept\n' > "$lua"
run_displays rate HDMI-A-1 75.03
status=$?
(( status != 0 )) || fail "rate HDMI-A-1 75.03 exited 0 although 1920x1080 has no 75.03 Hz mode"
grep -q 'does not list 75.03 Hz' "$tmp/out" || fail "the refusal does not say 75.03 is not listed: $(cat "$tmp/out")"
grep -q 'listed: 74.97 60 59.94' "$tmp/out" || fail "the refusal does not list the rates the monitor has: $(cat "$tmp/out")"
run_displays rate eDP-1 48
status=$?
(( status != 0 )) || fail "rate eDP-1 48 exited 0 although eDP-1 lists one mode, 60 Hz"
jq '.[1].availableModes = []' "$tmp/state.json" > "$tmp/state.new" && mv "$tmp/state.new" "$tmp/state.json"
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
(( $(eval_lines) == 0 )) || fail "a refused rate still reached hyprctl eval: $(cat "$tmp/eval.log")"
[[ ! -e "$pending" ]] || fail "a refused rate left a record waiting"
[[ "$(lua_text)" == '-- kept' ]] || fail "a refused rate rewrote monitors.lua: $(lua_text)"
end_case "a rate the monitor does not list, an unknown monitor, a word and a missing rate are all refused"

fresh
run_displays rate HDMI-A-1 59.94
run_displays keep
grep -qF 'mode = "1920x1080@59.94",' "$lua" || fail "59.94 was not saved as 59.94: $(lua_text)"
run_displays rate HDMI-A-1 60
status=$?
(( status == 0 )) || fail "rate HDMI-A-1 60 exited $status: $(cat "$tmp/out")"
grep -qF 'mode = "1920x1080@60.00"' "$tmp/eval.log" || fail "60 was not applied as 1920x1080@60.00: $(cat "$tmp/eval.log")"
run_displays keep
grep -qF 'mode = "1920x1080@60",' "$lua" || fail "60 was not saved as 60: $(lua_text)"
end_case "59.94 and 60 Hz are applied and saved as themselves"

fresh
jq '.[1].refreshRate = 74.97300' "$tmp/state.json" > "$tmp/state.new" && mv "$tmp/state.new" "$tmp/state.json"
run_displays place HDMI-A-1 left
status=$?
(( status == 0 )) || fail "place HDMI-A-1 left exited $status: $(cat "$tmp/out")"
grep -qF 'output = "HDMI-A-1", mode = "1920x1080@74.97"' "$tmp/eval.log" || fail "place did not keep HDMI-A-1 at 74.97: $(cat "$tmp/eval.log")"
grep -qF 'mode = "1920x1080@74.97",' "$lua" || fail "place did not save HDMI-A-1 at 74.97: $(lua_text)"
end_case "place keeps a chosen 74.97 Hz instead of rounding it to 75"

if command -v Hyprland > /dev/null 2>&1; then
    mkdir -p "$tmp/hv/run"
    chmod 700 "$tmp/hv/run"
    verify_config() {
        env -i PATH="$PATH" HOME="$tmp/hv" XDG_RUNTIME_DIR="$tmp/hv/run" \
            timeout 30 Hyprland --verify-config -c "$1" > "$tmp/verify.out" 2>&1
    }
    fresh
    jq '.[1].description = "WAM \"HDMI\" \\ 1" | .[1].transform = 1' "$tmp/state.json" > "$tmp/state.new" && mv "$tmp/state.new" "$tmp/state.json"
    run_displays rate HDMI-A-1 74.97
    run_displays keep
    if [[ -f "$lua" ]]; then
        { echo 'hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })'; cat "$lua"; } > "$tmp/verify.lua"
        verify_config "$tmp/verify.lua" || fail "Hyprland's parser rejects what keep saved: $(cat "$tmp/verify.out")"
        sed 's/@74.97/@banana/' "$tmp/verify.lua" > "$tmp/bad.lua"
        ! verify_config "$tmp/bad.lua" || fail "Hyprland's parser accepts a mode of banana, so its verdict above proves nothing"
    else
        fail "keep saved no layout for Hyprland's parser to read"
    fi
    end_case "Hyprland's own parser accepts the saved layout, a quote and a backslash in a description included, and rejects a bad mode"
else
    echo "note: Hyprland is not installed, so its parser was not asked about the saved layout"
fi

(( failed )) && exit 1
echo "ok   displays rate: switched, kept, reverted, expired and refused as above"
