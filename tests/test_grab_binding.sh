#!/usr/bin/env bash
# GlobalFocusGrab: its window list follows the keyboard (the old tree walk is the oracle), and a cold cheatsheet
# neither pins the main thread nor stays blank, and a click outside each surface still dismisses it.
# Hyprland nested in a headless KWin, repo keybinds, real surfaces, a virtual pointer for the clicks.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
HYPR="$REPO_ROOT/dots/.config/hypr"
CPU_MAX_TICKS=300
PAINT_MAX_S=1.0

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq grim cmp; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nested Hyprland not run"; exit 0; }
done

WORK="$(mktemp -d)"
RUN="$(mktemp -d /tmp/gb.XXXXXX)"
trap 'rm -rf "$WORK" "$RUN"' EXIT
chmod 700 "$RUN"
HOME_DIR="$WORK/home"
mkdir -p "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share" "$HOME_DIR/.cache" "$WORK/bin" "$WORK/shell"
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$HOME_DIR/.config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld" && chmod +x "$WORK/bin/koompi-shelld"
for entry in "$SHELL_ROOT"/*; do ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"; done

# a copy: the shell writes into this directory
cp -r -- "$HYPR/hyprland" "$HOME_DIR/.config/hypr/hyprland"
printf 'hl.on("hyprland.start", function() end)\n' > "$HOME_DIR/.config/hypr/hyprland/execs.lua"
grep -v 'custom\.' "$HYPR/hyprland.lua" > "$HOME_DIR/.config/hypr/hyprland.lua"
cat >> "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1200", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA

cat > "$WORK/shell/grab_probe.qml" <<'QML'
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.cheatsheet
import qs.modules.koompi.launchpad
import qs.modules.koompi.overview
import qs.modules.koompi.sidebarLeft
import qs.modules.koompi.sidebarRight
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: probe
    property bool sampling: false
    property var st: ({})

    Cheatsheet { id: sheet }
    Launchpad { id: pad }
    SearchPanel { id: search }
    SidebarLeft { id: left }
    SidebarRight { id: right }

    PanelWindow {
        id: bar
        visible: true
        anchors { top: true; left: true; right: true }
        implicitHeight: 24
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "probe-bar"
        Component.onCompleted: GlobalFocusGrab.addPersistent(bar)
    }
    PanelWindow {
        id: holder
        visible: false
        implicitWidth: 300
        implicitHeight: 100
        color: "transparent"
        WlrLayershell.namespace: "probe-holder"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        Item { Item { Item { TextInput { focus: true; text: "x" } } } }
    }
    PanelWindow { id: ondemand; visible: false; WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand }
    PanelWindow { id: nofocus; visible: false; WlrLayershell.keyboardFocus: WlrKeyboardFocus.None }

    // oracle: the rule the grab used before it stopped walking the tree
    function oldWalk(el) { return !!el?.activeFocus || Array.from(el?.children ?? []).some(c => probe.oldWalk(c)); }

    function reset() { probe.st = { samples: 0, open: 0, inside: 0, outside: 0, unfocusable: 0, mismatches: 0, first: "" }; }

    function nameOf(w) { return w === bar ? "bar" : w === holder ? "holder" : w === ondemand ? "ondemand" : w === nofocus ? "nofocus" : String(w?.WlrLayershell?.namespace ?? w); }

    function verdict(why) {
        const d = GlobalFocusGrab.dismissable, p = GlobalFocusGrab.persistent, got = GlobalFocusGrab.grabbedWindows;
        const inside = d.some(w => probe.oldWalk(w?.contentItem));
        const unfocusable = d.every(w => !w?.focusable);
        // the grab keeps only windows; a window pushed a moment ago can read back undefined once
        const want = ((unfocusable || inside) ? [...d, ...p] : [...d]).filter(w => w);
        const same = want.length === got.length && want.every((w, i) => w === got[i]);
        const s = probe.st;
        s.samples++;
        if (d.length > 0) s.open++;
        if (inside) s.inside++;
        else if (unfocusable) s.unfocusable++;
        else s.outside++;
        if (!same) {
            s.mismatches++;
            if (!s.first) s.first = `first (${why}): want [${want.map(probe.nameOf)}] got [${Array.from(got).map(probe.nameOf)}] inside=${inside} unfocusable=${unfocusable}`;
        }
        return `${same ? "ok" : "MISMATCH"} inside=${inside} unfocusable=${unfocusable} want=${want.length} got=${got.length}`;
    }

    // all three branches without the compositor: a window with no surface never holds the keyboard
    function matrix() {
        const saved = GlobalFocusGrab.dismissable;
        const cases = [{ n: "empty", l: [] }, { n: "unfocusable", l: [nofocus] }, { n: "focusable-hidden", l: [ondemand] }, { n: "mixed", l: [nofocus, ondemand] }];
        const lines = cases.map(c => { GlobalFocusGrab.dismissable = c.l; return `${c.n}: ${probe.verdict("matrix")}`; });
        GlobalFocusGrab.dismissable = saved;
        return lines.join("; ");
    }

    Timer { interval: 100; repeat: true; running: probe.sampling; onTriggered: probe.verdict("timer") }
    Connections {
        target: GlobalFocusGrab
        enabled: probe.sampling
        function onGrabbedWindowsChanged() { probe.verdict("change"); }
    }
    Component.onCompleted: probe.reset()

    IpcHandler {
        target: "probe"
        function ping(): int { return 1; }
        function reset(): void { probe.reset(); }
        function sampling(on: bool): void { probe.sampling = on; }
        function verdict(): string { return probe.verdict("ipc"); }
        function matrix(): string { return probe.matrix(); }
        function stats(): string {
            const s = probe.st;
            return `samples=${s.samples} open=${s.open} inside=${s.inside} outside=${s.outside} unfocusable=${s.unfocusable} mismatches=${s.mismatches} ${s.first}`;
        }
        function hold(on: bool): void {
            if (on) { holder.visible = true; GlobalFocusGrab.addDismissable(holder); }
            else { GlobalFocusGrab.removeDismissable(holder); holder.visible = false; }
        }
        function openSearch(): void { search.open(); }
        function flag(name: string, on: bool): void { GlobalStates[name] = on; }
        function flagOf(name: string): string { return String(GlobalStates[name]); }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
log() { printf '%s\n' "$*" >> "$WORK/readings"; }

locate() {
    local lock p s
    for lock in "$XDG_RUNTIME_DIR"/hypr/*/hyprland.lock; do
        [[ -f $lock ]] || continue
        { read -r p; read -r s; } < "$lock"
        [[ $p == "$1" && -n $s ]] && { echo "$(basename -- "$(dirname -- "$lock")") $s"; return 0; }
    done
    return 1
}
# no-output start (hyprwm/aquamarine#415): SIGKILL and redo; its SIGTERM and its own exit both abort, and a coredump toasts the live seat
for attempt in 1 2 3 4 5 6; do
    Hyprland -c "$HOME/.config/hypr/hyprland.lua" >> "$WORK/hyprland.log" 2>&1 &
    hypr_pid=$!
    found=""
    for _ in $(seq 1 150); do
        found=$(locate "$hypr_pid") && break
        kill -0 "$hypr_pid" 2> /dev/null || { log "dead Hyprland exited at start $attempt"; exit 0; }
        sleep 0.2
    done
    if [[ -n $found ]]; then
        read -r sig socket <<< "$found"
        export HYPRLAND_INSTANCE_SIGNATURE=$sig WAYLAND_DISPLAY=$socket
        for _ in $(seq 1 50); do hyprctl monitors -j 2> /dev/null | jq -e 'length > 0' > /dev/null 2>&1 && break 2; sleep 0.1; done
    fi
    log "start $attempt: no output"
    kill -9 "$hypr_pid" 2> /dev/null; wait "$hypr_pid" 2> /dev/null
done
hyprctl monitors -j 2> /dev/null | jq -e 'length > 0' > /dev/null 2>&1 || { log "wedged: no start had an output"; exit 0; }

cd "$WORK/shell" || exit 1
qs -p grab_probe.qml > "$WORK/qs.log" 2>&1 &
qs_pid=$!
call() { qs -p grab_probe.qml ipc call "$@" 2> /dev/null < /dev/null; }
for _ in $(seq 1 80); do call probe ping > /dev/null && break; sleep 0.5; done
sleep 3

ticks() { awk '{print $14 + $15}' "/proc/$qs_pid/task/$qs_pid/stat"; }
shot() { timeout 10 grim -g "560,350 800x500" -t ppm "$1" 2>> "$WORK/grim.log"; }
now() { date +%s.%N; }
shot "$WORK/empty.ppm"
t0=$(now); cpu0=$(ticks)
call cheatsheet open > /dev/null
painted=none; used=none
for _ in $(seq 1 80); do
    sleep 0.15
    shot "$WORK/now.ppm"
    t=$(awk -v a="$(now)" -v b="$t0" 'BEGIN { printf "%.2f", a - b }')
    cpu=$(( $(ticks) - cpu0 ))
    differing=$(cmp -l "$WORK/empty.ppm" "$WORK/now.ppm" 2> /dev/null | head -n 20000 | wc -l)
    log "cold t=$t cpu_ticks=$cpu differing=$differing"
    if (( differing >= 20000 )); then painted=$t; used=$cpu; break; fi
done
log "cost painted_at=$painted cpu_ticks_at_paint=$used"
call cheatsheet close > /dev/null; sleep 1

log "matrix $(call probe matrix)"
log "STATS matrix $(call probe stats)"
call probe reset
call probe sampling true
call probe hold true
for _ in $(seq 1 40); do [[ $(call probe verdict) == *inside=true* ]] && break; sleep 0.25; done
log "holder $(call probe verdict)"
sleep 1
call probe hold false; sleep 1
log "STATS holder $(call probe stats)"
call probe reset

open_surface() { case $1 in search) call probe openSearch ;; *) call "$1" open ;; esac; }
close_surface() { case $1 in search) call probe flag searchOpen false ;; *) call "$1" close ;; esac; }
for s in cheatsheet search sidebarLeft sidebarRight; do
    for pass in open reopen; do
        open_surface "$s" > /dev/null; sleep 2
        log "$s $pass $(call probe verdict)"
        close_surface "$s" > /dev/null; sleep 1
    done
    log "STATS $s $(call probe stats)"
    call probe reset
done

# no pointer in the nested session: wl_virtual_click.py makes one; the point is empty desktop for each surface
click_out() {
    local name=$1 flag=$2 x=$3 y=$4 before after
    if [[ $name == launchpad ]]; then call launchpad open > /dev/null; else open_surface "$name" > /dev/null; fi
    sleep 2
    before=$(call probe flagOf "$flag")
    python3 "$REPO_ROOT/tests/wl_virtual_click.py" 1920 1200 "$x" "$y" >> "$WORK/click.log" 2>&1
    sleep 1.5
    after=$(call probe flagOf "$flag")
    log "CLICK $name before=$before after=$after"
    [[ $after == false ]] || { if [[ $name == launchpad ]]; then call launchpad close > /dev/null; else close_surface "$name" > /dev/null; fi; sleep 1; }
}
click_out cheatsheet cheatsheetOpen 40 1150
click_out search searchOpen 40 1150
click_out sidebarLeft sidebarLeftOpen 1880 1150
click_out sidebarRight sidebarRightOpen 40 1150
click_out launchpad launchpadOpen 40 1150

kill "$qs_pid" 2> /dev/null
cp "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log "$WORK/hyprland-run.log" 2> /dev/null
hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
sleep 1
log done
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" \
    REPO_ROOT="$REPO_ROOT" HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 420 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 2120 --height 1400 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

dump() {
    echo "--- readings ---" >&2; cat -- "$WORK/readings" >&2 2> /dev/null
    echo "--- qs.log ---" >&2; grep -vE 'qmlscanner|^\s*$' "$WORK/qs.log" 2> /dev/null | tail -25 >&2
    echo "--- hyprland.log ---" >&2; tail -15 -- "$WORK/hyprland.log" >&2 2> /dev/null
}
field() { grep -E "$1" "$WORK/readings" | head -1 | sed -E 's/ first.*//' | sed -E "s/.* $2=([^ ]+).*/\1/"; }
total() { grep -E '^STATS ' "$WORK/readings" | sed -E 's/ first.*//' | sed -E "s/.* $1=([0-9]+).*/\1/" | awk '{ s += $1 } END { print s + 0 }'; }

grep -q '^wedged' "$WORK/readings" 2> /dev/null && { echo "skip: no nested Hyprland start had an output (hyprwm/aquamarine#415), the grab test did not run"; exit 0; }
grep -q '^dead' "$WORK/readings" 2> /dev/null && grep -q 'no output' "$WORK/readings" && { echo "skip: the retry after a no-output nested Hyprland start died (hyprwm/aquamarine#415), the grab test did not run"; exit 0; }
grep -q '^dead' "$WORK/readings" 2> /dev/null && { dump; fail "setup: the nested Hyprland exited while it started"; }
grep -q '^done$' "$WORK/readings" 2> /dev/null || { dump; fail "setup: the probe session did not finish"; }
grep -qE '^holder (ok|MISMATCH) inside=true' "$WORK/readings" || { dump; fail "setup: the window with the nested focused item never held the keyboard"; }
for s in cheatsheet search sidebarLeft sidebarRight; do
    for branch in open inside outside; do
        (( $(field "^STATS $s " "$branch") > 0 )) || { dump; fail "setup: no sample of $s met '$branch', so that branch of its list was never compared"; }
    done
done
(( $(total unfocusable) > 0 )) || { dump; fail "setup: no sample met the branch where no dismissable window takes the keyboard"; }

failed=0
miss() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

bad=$(grep -E '^STATS ' "$WORK/readings" | grep -vE 'mismatches=0( |$)')
if [[ -n $bad ]]; then
    miss "the grab's window list differs from the keyboard rule: $bad"
else
    echo "ok   list: the grab held what the keyboard rule says in $(total samples) samples over the cheatsheet, Search, both sidebars and a nested focused item"
    grep -E '^STATS ' "$WORK/readings" | sed 's/^STATS /       /'
fi

painted=$(field '^cost ' painted_at); used=$(field '^cost ' cpu_ticks_at_paint)
if [[ $painted == none ]]; then
    miss "a cold cheatsheet was not on screen in the whole run: the main thread is still busy with it"
elif (( used > CPU_MAX_TICKS )); then
    miss "a cold cheatsheet took $used ticks of main-thread CPU to reach the screen, at $painted s (at most $CPU_MAX_TICKS)"
elif awk -v t="$painted" -v m="$PAINT_MAX_S" 'BEGIN { exit !(t > m) }'; then
    miss "a cold cheatsheet was on screen only at $painted s (at most $PAINT_MAX_S s)"
else
    echo "ok   cost: a cold cheatsheet was on screen at $painted s, after $used ticks of main-thread CPU (at most $CPU_MAX_TICKS, $PAINT_MAX_S s)"
fi

for s in cheatsheet search sidebarLeft sidebarRight launchpad; do
    if grep -qE "^CLICK $s before=true after=false\$" "$WORK/readings"; then
        echo "ok   click: a click outside dismissed the $s"
    else
        miss "a click outside did not dismiss the $s: $(grep -E "^CLICK $s " "$WORK/readings" || echo 'no reading') $(tail -2 "$WORK/click.log" 2> /dev/null)"
    fi
done

(( failed == 0 )) || { dump; exit 1; }
