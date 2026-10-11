#!/usr/bin/env bash
# nested hyprland: okular on xwayland, kdeconnect-app on wayland, kdialog floated on both
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in Hyprland hyprctl kwin_wayland dbus-run-session jq pgrep Xwayland okular kdeconnect-app kdialog; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nested Hyprland not run"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$WORK/no-session-yet"
trap 'rm -rf "$WORK" "$RUN"' EXIT
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.local/state" "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$WORK/bin"
ln -s "$REPO_ROOT/dots/.config/hypr/hyprland" "$HOME_DIR/.config/hypr/hyprland"

cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
require("hyprland.env")
require("hyprland.rules")
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/logger"
cat > "$WORK/bin/report_platform" <<'SH'
#!/usr/bin/env bash
printf '%s' "${QT_QPA_PLATFORM-<unset>}" > "$WORK/session_platform"
SH
chmod +x "$WORK/bin/logger" "$WORK/bin/report_platform"

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"
if ! nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log"; then
    printf 'monitor\tmissing\n' >> "$WORK/readings"
    exit 0
fi
printf 'monitor\tready\n' >> "$WORK/readings"

launch() { hyprctl dispatch "hl.dsp.exec_cmd(\"$1\")" > /dev/null 2>&1; }

window_of() {
    hyprctl clients -j 2> /dev/null | jq -r --arg a "$1" \
        '[.[] | select(.class | ascii_downcase | contains($a))][0] | select(. != null) | [.class, .xwayland, .floating] | @tsv'
}

# an xcb app that outlives its x server can segfault, and every coredump toasts the live seat
stop_apps() {
    local child
    for child in $(pgrep -P "$hypr_pid"); do
        [[ $(cat "/proc/$child/comm" 2> /dev/null) == Xwayland ]] || kill "$child" 2> /dev/null
    done
}

probe() {
    local row=""
    launch "$2"
    for _ in $(seq 1 120); do row=$(window_of "$3"); [[ -n $row ]] && break; sleep 0.5; done
    printf '%s\t%s\n' "$1" "${row:-missing}" >> "$WORK/readings"
    stop_apps
    for _ in $(seq 1 60); do [[ -z $(window_of "$3") ]] && break; sleep 0.5; done
}

launch report_platform
for _ in $(seq 1 60); do [[ -s $WORK/session_platform ]] && break; sleep 0.5; done
probe okular 'koompi-launch okular' okular
probe kdeconnect-app 'koompi-launch kdeconnect-app' kdeconnect
probe kdialog-wayland 'koompi-launch kdialog --getopenfilename . --title probe-wayland' kdialog
probe kdialog-xcb 'env QT_QPA_PLATFORM=xcb kdialog --getopenfilename . --title probe-xcb' kdialog

stop_apps
sleep 1
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
SH
chmod +x "$WORK/inner.sh"

field() { awk -F'\t' -v k="$1" -v n="$(($2 + 1))" '$1 == k { print $n }' "$WORK/readings" 2> /dev/null; }

run_session() {
    RUN="$(mktemp -d /tmp/hr.XXXXXX)"
    chmod 700 "$RUN"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY -u QT_QPA_PLATFORM WORK="$WORK" REPO_ROOT="$REPO_ROOT" \
        HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
        XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
        PATH="$WORK/bin:$REPO_ROOT/dots/.local/bin:$PATH" \
        timeout 300 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
    rm -rf "$RUN"
}

dump() {
    echo "--- readings ---" >&2
    cat -- "$WORK/readings" >&2 2> /dev/null
    echo "--- session platform: $(cat "$WORK/session_platform" 2> /dev/null) ---" >&2
    echo "--- hyprland.log ---" >&2
    grep -vE '^\s*$' "$WORK/hyprland.log" 2> /dev/null | tail -15 >&2
}

run_session
grep '^nested Hyprland:' "$WORK/kwin.log" | sed 's/^/note: /'
[[ "$(field monitor 1)" == ready ]] || { dump; fail "setup: the nested Hyprland never got an output from KWin, so no window can map"; exit 1; }

session_platform="$(cat "$WORK/session_platform" 2> /dev/null)"
[[ "$session_platform" == 'wayland;xcb' ]] || fail "a client started from Hyprland sees QT_QPA_PLATFORM '$session_platform', want 'wayland;xcb'"
echo "ok   session: clients started from the nested Hyprland see QT_QPA_PLATFORM=$session_platform"

for name in okular kdeconnect-app kdialog-wayland kdialog-xcb; do
    [[ -n "$(field "$name" 1)" && "$(field "$name" 1)" != missing ]] || { dump; fail "$name never mapped a window"; exit 1; }
done

[[ "$(field okular 2)" == true ]] || fail "okular through koompi-launch is xwayland=$(field okular 2), want true: its menubar only reaches the bar on X11"
[[ "$(field kdeconnect-app 2)" == false ]] || fail "kdeconnect-app through koompi-launch is xwayland=$(field kdeconnect-app 2), want false"
[[ "$(field kdialog-wayland 2)" == false ]] || fail "kdialog through koompi-launch is xwayland=$(field kdialog-wayland 2), want false"
[[ "$(field kdialog-wayland 3)" == true ]] || fail "the kdialog rule left the wayland dialog (class $(field kdialog-wayland 1)) tiled"
[[ "$(field kdialog-xcb 2)" == true ]] || fail "setup: kdialog forced to xcb is xwayland=$(field kdialog-xcb 2)"
[[ "$(field kdialog-xcb 3)" == true ]] || fail "the kdialog rule left the xcb dialog (class $(field kdialog-xcb 1)) tiled"

for name in okular kdeconnect-app kdialog-wayland kdialog-xcb; do
    printf 'client: %-16s class=%-24s xwayland=%-5s floating=%s\n' "$name" "$(field "$name" 1)" "$(field "$name" 2)" "$(field "$name" 3)"
done
(( failed == 0 )) || { dump; exit 1; }
echo "ok   nested Hyprland: okular on X11, kdeconnect-app on Wayland, kdialog floated on both"
