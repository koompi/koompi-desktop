#!/usr/bin/env bash
# Launch feedback (audit 3.11, F10) end to end: the repo's Hyprland config and shell in a
# Hyprland nested in headless KWin (private bus, own HOME and runtime dir), with the real
# koompi-shelld asked for its hyprland service alone, so HyprlandData sees the nested
# compositor and nothing of the host. A slow app (sleeps 1.5 s, then execs a window
# client) starts as a key bind starts one, through koompi-launch:
#   from 0.3 s on: the shell has been told, and says it is opening the app
#   once the window maps: the launch ends, well inside the 8 s ttl, so it was the window
# once with the program found by what its Exec runs and the window by StartupWMClass, once
# with a window only the launched pid can claim. SHOTS=<dir> keeps the screenshots:
# the empty desktop, the first answer, and 3 s after the bind.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=$((failed + 1)); }

for tool in Hyprland hyprctl kwin_wayland dbus-run-session jq qs grim kdialog; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nested Hyprland not run"; exit 0; }
done
SHELLD="${KOOMPI_SHELLD_BIN:-}"
for candidate in "$HOME/.local/bin/koompi-shelld" "$REPO_ROOT/shell-services/target/release/koompi-shelld"; do
    [[ -n "$SHELLD" && -x "$SHELLD" ]] && break
    SHELLD="$candidate"
done
[[ -x "$SHELLD" ]] || { echo "skip: no built koompi-shelld, the bar has no window list to follow"; exit 0; }

WORK="$(mktemp -d)"
RUN="$WORK/no-session-yet"
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK" "$RUN"' EXIT
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/quickshell" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share/applications" "$HOME_DIR/.cache" "$WORK/bin" "$WORK/shots"

HYPR_SRC="$REPO_ROOT/dots/.config/hypr"
for entry in "$HYPR_SRC"/*; do
    name="$(basename -- "$entry")"
    [[ "$name" == hyprland || "$name" == hyprland.lua || "$name" == custom ]] && continue
    ln -s "$entry" "$HOME_DIR/.config/hypr/$name"
done
# copied, not linked: the shell writes into hyprland/, and a link would write into the repo
mkdir -p "$HOME_DIR/.config/hypr/hyprland"
cp -r -- "$HYPR_SRC/hyprland/." "$HOME_DIR/.config/hypr/hyprland/"
cat > "$HOME_DIR/.config/hypr/hyprland/execs.lua" <<'LUA'
hl.on("hyprland.start", function()
    hl.exec_cmd("env QT_QPA_PLATFORM=wayland qs -c koompi")
end)
LUA
grep -v 'custom\.' "$HYPR_SRC/hyprland.lua" > "$HOME_DIR/.config/hypr/hyprland.lua"
cat >> "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1200", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA
ln -s "$REPO_ROOT/dots/.config/quickshell/koompi" "$HOME_DIR/.config/quickshell/koompi"
ln -s "$REPO_ROOT/dots/.config/fontconfig" "$HOME_DIR/.config/fontconfig"
[[ -d "$HOME/.local/share/fonts" ]] && ln -s "$HOME/.local/share/fonts" "$HOME_DIR/.local/share/fonts"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}, "language": {"ui": "en_US"}}' > "$HOME_DIR/.config/koompi/config.json"

# the real daemon, asked for hyprland only: network, power and the rest would reach the host's system bus
cat > "$WORK/bin/koompi-shelld" <<SH
#!/usr/bin/env bash
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$WORK/no-system-bus
jq -c --unbuffered 'if .cmd == "subscribe" then .services |= map(select(. == "hyprland")) else . end' | "$SHELLD"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/logger"

# slow apps: sleep, then become a window client, as a heavy app does
for app in slow-probe-app slow-probe-pid; do
    printf '#!/usr/bin/env bash\nsleep 1.5\nexec kdialog --msgbox %s --title %s\n' "'$app'" "'$app title'" > "$WORK/bin/$app"
done
chmod +x "$WORK/bin"/*
# the entry the shell finds by what its Exec runs, and whose window it knows by StartupWMClass
printf '[Desktop Entry]\nType=Application\nName=Slow Probe\nIcon=okular\nExec=slow-probe-app\nStartupWMClass=org.kde.kdialog\n' \
    > "$HOME_DIR/.local/share/applications/slow-probe.desktop"
# the entry whose window nothing about it can name: only the launched pid does
printf '[Desktop Entry]\nType=Application\nName=Slow Pid Probe\nIcon=btop\nExec=slow-probe-pid\n' \
    > "$HOME_DIR/.local/share/applications/slowpid.desktop"
# a bind that starts the first program it finds, as keybinds.lua's app() does
printf '#!/usr/bin/env bash\nexec koompi-launch --id fileManager "%s/scripts/launch_first_available.sh" no-such-app-x slow-probe-app\n' "$HYPR_SRC/hyprland" > "$WORK/bin/bind-first"
printf '#!/usr/bin/env bash\nexec koompi-launch --id slowpid slow-probe-pid\n' > "$WORK/bin/bind-pid"
chmod +x "$WORK/bin/bind-first" "$WORK/bin/bind-pid"

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
parent=$WAYLAND_DISPLAY
Hyprland -c "$HOME/.config/hypr/hyprland.lua" > "$WORK/hyprland.log" 2>&1 &
hypr_pid=$!
for _ in $(seq 1 100); do sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2> /dev/null | head -1); [[ -n $sig ]] && break; sleep 0.2; done
export HYPRLAND_INSTANCE_SIGNATURE=$sig
for _ in $(seq 1 100); do d=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | grep -v "^$parent$" | head -1); [[ -n $d ]] && break; sleep 0.2; done
export WAYLAND_DISPLAY=$d

reading() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/readings"; }
now_ms() { echo $(($(date +%s%N) / 1000000)); }
status() {
    local out rc=0
    out=$(qs -c koompi ipc call launch status 2> /dev/null) || rc=$?
    (( rc == 0 )) || out="<qs exit $rc>"
    printf '%s' "$out"
}
clients() { hyprctl clients -j 2> /dev/null; }
probe_windows() { clients | jq -r '[.[] | select(.class == "org.kde.kdialog")] | length'; }

finish() {
    local child
    for child in $(clients | jq -r '.[] | select(.class == "org.kde.kdialog") | .pid'); do kill "$child" 2> /dev/null; done
    for child in $(pgrep -P "$hypr_pid"); do [[ $(cat "/proc/$child/comm" 2> /dev/null) == Xwayland ]] || kill "$child" 2> /dev/null; done
    sleep 1
    hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
    sleep 1
}

for _ in $(seq 1 80); do [[ $(hyprctl monitors -j 2> /dev/null | jq length) -ge 1 ]] && break; sleep 0.5; done
if [[ $(hyprctl monitors -j 2> /dev/null | jq length) -lt 1 ]]; then reading monitor missing; finish; exit 0; fi
reading monitor ready

# the shell is up when its launch handler answers; the daemon's first snapshot follows
for _ in $(seq 1 120); do answer=$(qs -c koompi ipc call launch status 2> /dev/null); [[ $? -eq 0 && $answer != "Target not found." ]] && break; sleep 0.5; done
sleep 6
reading idle "$(status)"
grim "$WORK/shots/empty-desktop.png" 2>> "$WORK/grim.log"

# name, bind script, window title it ends up with; the notice is a qs process of its own, so
# the shell is asked from 0.3 s on and the screenshot is taken at the first answer
scenario() {
    local name=$1 bind=$2 title=$3 t0 early="" seen=-1 mapped=-1 cleared=-1 spent
    t0=$(now_ms)
    hyprctl dispatch 'hl.dsp.exec_cmd("'"$bind"'")' > /dev/null 2>&1
    sleep 0.3
    while :; do
        early=$(status)
        if [[ -n $early ]]; then seen=$(($(now_ms) - t0)); break; fi
        (( $(now_ms) - t0 > 2500 )) && break
    done
    reading "$name.early" "$early"
    reading "$name.seen_ms" "$seen"
    grim "$WORK/shots/$name-0.3s.png" 2>> "$WORK/grim.log"
    for _ in $(seq 1 120); do
        if (( mapped < 0 )) && [[ $(clients | jq -r --arg t "$title" '[.[] | select(.title == $t)] | length') -gt 0 ]]; then mapped=$(($(now_ms) - t0)); fi
        if (( mapped >= 0 )) && [[ -z $(status) ]]; then cleared=$(($(now_ms) - t0)); break; fi
        if (( $(now_ms) - t0 > 20000 )); then break; fi
        sleep 0.1
    done
    reading "$name.mapped_ms" "$mapped"
    reading "$name.cleared_ms" "$cleared"
    spent=$(($(now_ms) - t0))
    (( spent >= 3000 )) || sleep "$(awk -v ms="$spent" 'BEGIN { printf "%.2f", (3000 - ms) / 1000 }')"
    reading "$name.late" "$(status)"
    reading "$name.focus" "$(hyprctl activewindow -j 2> /dev/null | jq -r '.title // ""')"
    grim "$WORK/shots/$name-3s.png" 2>> "$WORK/grim.log"
    for pid in $(clients | jq -r --arg t "$title" '.[] | select(.title == $t) | .pid'); do kill "$pid" 2> /dev/null; done
    for _ in $(seq 1 40); do [[ $(probe_windows) -eq 0 ]] && break; sleep 0.25; done
}

scenario slowprobe bind-first 'slow-probe-app title'
scenario slowpid bind-pid 'slow-probe-pid title'
finish
SH
chmod +x "$WORK/inner.sh"

field() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$WORK/readings" 2> /dev/null; }

run_session() {
    RUN="$(mktemp -d /tmp/hr.XXXXXX)"
    chmod 700 "$RUN"
    rm -f "$WORK/readings"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY -u QT_QPA_PLATFORM WORK="$WORK" \
        HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
        XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
        PATH="$WORK/bin:$REPO_ROOT/dots/.local/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" \
        timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 2120 --height 1400 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
    rm -rf "$RUN"
}

dump() {
    echo "--- readings ---" >&2
    cat -- "$WORK/readings" >&2 2> /dev/null
    echo "--- hyprland.log ---" >&2
    grep -vE '^\s*$' "$WORK/hyprland.log" 2> /dev/null | tail -15 >&2
}

for attempt in 1 2 3; do
    run_session
    [[ "$(field monitor)" == ready ]] && break
    echo "attempt $attempt: KWin gave the nested Hyprland no output, starting the session again" >&2
done
[[ "$(field monitor)" == ready ]] || { dump; fail "setup: the nested Hyprland never got an output from KWin, so no window can map"; exit 1; }

if [[ -n "${SHOTS:-}" ]]; then
    mkdir -p "$SHOTS" && cp -- "$WORK"/shots/*.png "$SHOTS"/ 2> /dev/null
fi

# what the bar draws, read off the screenshot: the app identity is the block right of the star
bar_text() {
    magick "$WORK/shots/$1.png" -crop 300x40+60+0 +repage -filter Lanczos -resize 300% "$WORK/crop.png" 2> /dev/null \
        && tesseract "$WORK/crop.png" stdout --psm 6 2> /dev/null | tr '\n' ' ' | sed 's/^ *//; s/ *$//'
}
expect_bar() {
    local text before=$failed
    text="$(bar_text "$1")"
    grep -qiE "$2" <<< "$text" || fail "the bar in $1 reads '$text', want /$2/"
    [[ -z "${3:-}" ]] || ! grep -qiE "$3" <<< "$text" || fail "the bar in $1 reads '$text', which has /$3/"
    (( failed == before )) && echo "ok   bar in $1 reads '$text'"
}

before=$failed
[[ -z "$(field idle)" ]] || fail "before any launch the shell says '$(field idle)' is opening"
(( failed == before )) && echo "ok   idle: nothing is opening before a launch"

check_scenario() {
    local name=$1 want=$2 title=$3 early mapped cleared before=$failed
    early="$(field "$name.early")" mapped="$(field "$name.mapped_ms")" cleared="$(field "$name.cleared_ms")"
    [[ "$early" == "$want" ]] || fail "$name: from 0.3 s on the shell says '$early' is opening, want '$want'"
    if [[ -z "$mapped" || "$mapped" -lt 0 ]]; then fail "$name: the slow app never mapped a window"; return; fi
    if (( mapped >= 7000 )); then fail "setup: $name took $mapped ms to map, so the 8 s ttl could have ended the launch, not the window"; return; fi
    if [[ -z "$cleared" || "$cleared" -lt 0 ]]; then fail "$name: the window mapped at $mapped ms and the shell still says '$(field "$name.late")' is opening"; return; fi
    (( cleared - mapped < 2000 )) || fail "$name: the window mapped at $mapped ms and the launch ended at $cleared ms, the ttl's doing and not the window's"
    [[ -z "$(field "$name.late")" ]] || fail "$name: 3 s after the bind the shell says '$(field "$name.late")' is opening"
    [[ "$(field "$name.focus")" == "$title" ]] || fail "$name: 3 s after the bind the focused window is '$(field "$name.focus")', want '$title'"
    (( failed == before )) && echo "ok   $name: '$want' from $(field "$name.seen_ms") ms, the window mapped at $mapped ms and ended it at $cleared ms"
}
check_scenario slowprobe 'Slow Probe' 'slow-probe-app title'
check_scenario slowpid 'Slow Pid Probe' 'slow-probe-pid title'

if command -v magick > /dev/null 2>&1 && command -v tesseract > /dev/null 2>&1; then
    expect_bar empty-desktop '^Desktop$' 'Work'
    expect_bar slowprobe-0.3s 'Slow Probe.*Opening' ''
    expect_bar slowpid-0.3s 'Slow Pid Probe.*Opening' ''
    expect_bar slowprobe-3s 'Kdialog' 'Opening'
    expect_bar slowpid-3s 'Kdialog' 'Opening'
else
    echo "note: no ImageMagick or tesseract here, so the bar's pixels were not read"
fi

(( failed == 0 )) || { dump; exit 1; }
echo "ok   nested Hyprland: a key bind's launch is announced, and ended by its window, found by StartupWMClass and by pid"
