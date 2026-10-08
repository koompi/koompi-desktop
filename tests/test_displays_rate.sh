#!/usr/bin/env bash
# koompi-displays rate puts one monitor on another refresh rate at its resolution and saves the layout
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

for cmd in bash jq mktemp mv rm sleep cat; do
    path="$(command -v "$cmd")" || { echo "FAIL: test host has no $cmd" >&2; exit 1; }
    ln -s "$path" "$stub/$cmd"
done
cp "$REPO_ROOT/tests/displays-hyprctl" "$stub/hyprctl"
chmod +x "$stub/hyprctl"

lua="$tmp/config/hypr/monitors.lua"
fresh() {
    cp "$REPO_ROOT/tests/displays-monitors.json" "$tmp/state.json"
    : > "$tmp/eval.log"
    rm -rf "$lua" "$tmp/state.json.ignore" "$stub/luac"
}
run_displays() {
    env -i PATH="$stub" HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" \
        HYPRCTL_STATE="$tmp/state.json" HYPRCTL_EVAL_LOG="$tmp/eval.log" bash "$SCRIPT" "$@" > "$tmp/out" 2>&1
}
eval_lines() { wc -l < "$tmp/eval.log"; }
lua_text() { cat "$lua" 2> /dev/null; }
lua_has() { grep -qF -- "$1" "$lua" 2> /dev/null; }
config_files() { find "$tmp/config/hypr" -mindepth 1 -printf '%f '; }

fresh
run_displays rate HDMI-A-1 74.97
status=$?
(( status == 0 )) || fail "rate HDMI-A-1 74.97 exited $status: $(cat "$tmp/out")"
want='hl.monitor({output = "HDMI-A-1", mode = "1920x1080@74.97", position = "1920x0", scale = 1.25})'
[[ "$(cat "$tmp/eval.log")" == "$want" ]] || fail "rate 74.97 sent '$(cat "$tmp/eval.log")', wanted '$want'"
saved=$'hl.monitor({\n    output = "desc:BOE 0x0CE0",\n    mode = "1920x1200@60",\n    position = "0x0",\n    scale = 1,\n    transform = 0\n})\nhl.monitor({\n    output = "desc:WAM HDMI 18250023",\n    mode = "1920x1080@74.97",\n    position = "1920x0",\n    scale = 1.25,\n    transform = 0\n})'
[[ "$(lua_text | tail -n +3)" == "$saved" ]] || fail "monitors.lua after rate 74.97 is not the saved layout: $(lua_text)"
[[ "$(config_files)" == "monitors.lua " ]] || fail "rate left more than monitors.lua in the config dir: $(config_files)"
end_case "rate HDMI-A-1 74.97 applies 1920x1080@74.97 in place's form and saves the layout"

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
[[ "$(lua_text)" == '-- kept' ]] || fail "a refused rate rewrote monitors.lua: $(lua_text)"
end_case "a rate the monitor does not list, an unknown monitor, a word and a missing rate are all refused"

fresh
run_displays rate HDMI-A-1 59.94
lua_has 'mode = "1920x1080@59.94",' || fail "59.94 was not saved as 59.94: $(lua_text)"
run_displays rate HDMI-A-1 60
lua_has 'mode = "1920x1080@60",' || fail "60 was not saved as 60: $(lua_text)"
grep -qF 'mode = "1920x1080@60.00"' "$tmp/eval.log" || fail "60 was not applied as 1920x1080@60.00: $(cat "$tmp/eval.log")"
end_case "59.94 and 60 Hz are applied and saved as themselves"

fresh
jq '.[1].refreshRate = 74.97300' "$tmp/state.json" > "$tmp/state.new" && mv "$tmp/state.new" "$tmp/state.json"
run_displays place HDMI-A-1 left
status=$?
(( status == 0 )) || fail "place HDMI-A-1 left exited $status: $(cat "$tmp/out")"
grep -qF 'output = "HDMI-A-1", mode = "1920x1080@74.97"' "$tmp/eval.log" || fail "place did not keep HDMI-A-1 at 74.97: $(cat "$tmp/eval.log")"
lua_has 'mode = "1920x1080@74.97",' || fail "place did not save HDMI-A-1 at 74.97: $(lua_text)"
end_case "place keeps a chosen 74.97 Hz instead of rounding it to 75"

fresh
touch "$tmp/state.json.ignore"
run_displays rate HDMI-A-1 74.97
status=$?
(( status != 0 )) || fail "rate exited 0 although the compositor never switched"
grep -q 'did not switch to 74.97 Hz' "$tmp/out" || fail "the failure does not say the switch did not happen: $(cat "$tmp/out")"
[[ ! -e "$lua" ]] || fail "a rate that did not take was saved: $(lua_text)"
end_case "a switch the compositor did not make exits non-zero and saves nothing"

fresh
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/luac"
chmod +x "$stub/luac"
run_displays rate HDMI-A-1 74.97
status=$?
(( status != 0 )) || fail "rate exited 0 although luac rejected the file"
grep -q 'failed lua validation' "$tmp/out" || fail "a rejected file was not reported: $(cat "$tmp/out")"
[[ -z "$(config_files)" ]] || fail "a file luac rejected left something in the config dir: $(config_files)"
end_case "rate saves through the validation place uses"

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
    if [[ -f "$lua" ]]; then
        { echo 'hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })'; cat "$lua"; } > "$tmp/verify.lua"
        verify_config "$tmp/verify.lua" || fail "Hyprland's parser rejects what rate saved: $(cat "$tmp/verify.out")"
        sed 's/@74.97/@banana/' "$tmp/verify.lua" > "$tmp/bad.lua"
        ! verify_config "$tmp/bad.lua" || fail "Hyprland's parser accepts a mode of banana, so its verdict above proves nothing"
    else
        fail "rate saved no layout for Hyprland's parser to read"
    fi
    end_case "Hyprland's own parser accepts the saved layout, a quote and a backslash in a description included, and rejects a bad mode"
else
    echo "note: Hyprland is not installed, so its parser was not asked about the saved layout"
fi

(( failed )) && exit 1
echo "ok   displays rate: applied, saved, refused and failed loudly as above"
