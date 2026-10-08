#!/usr/bin/env bash
# Launch feedback (audit 3.11, F10) as the bar draws it. The real ActiveWindow and the real
# LaunchFeedback run under a Hyprland nested in headless KWin (private bus, own HOME and
# runtime dir), which is what gives the bar a focused monitor; the compositor's window list is
# a fixture, so the answer cannot depend on how fast an app starts.
#   Empty desktop: no window reads "Desktop" with no second line (decision
#   J13_empty_desktop_identity), where it read "Workspace N" and elided to "Works...".
#   Opening: a launch turns the identity into the app's name over "Opening...", pulses it,
#   hides the menus of the window being left, and ends when a window of the app maps (found
#   through a real DesktopEntries lookup) or when ttl runs out.
#   Reduce Motion: the pulse is a held dim state, not a loop.
#   Entries: a launch from koompi-launch resolves by id and by the program the Exec runs, and
#   not when two entries share one.
#   Scale 1.25: the monitor is fractional, where a name was given a whole pixel fewer than its
#   text, and lost two letters to the ellipsis ("Visual Studio Code" and "Probe App" here).
#   Dimming: the icon and the name dim and pulse, never below the opacity that keeps their text at
#   4.5:1 on the dark and the light palette, and the Opening line is never dimmed.
#   Relaunch: focus that was on the app's window before the launch began does not end the launch,
#   however late its notice reaches the shell, and the app's next window does. So with an app started
#   again just before the shell hears that the first one's window has closed.
#   Several at once: the bar shows the newest launch, each ends at its own window in any order, one
#   that never maps blocks no other and ends at its own ttl, and the shell keeps the eight newest.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, the bar's launch identity not drawn"; exit 0; }
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
RUN="$WORK/no-session-yet"
HOME_DIR="$WORK/home"

# every process of the session carries its private runtime dir in its environment, so what is
# still running once KWin has returned is found by that, named, ended by pid, and fails the test
session_pids() {
    grep -lzxF "XDG_RUNTIME_DIR=$RUN" /proc/[0-9]*/environ 2> /dev/null | sed -e 's|^/proc/||' -e 's|/environ$||'
}
reap_session() {
    local pids pid
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        mapfile -t pids < <(session_pids)
        (( ${#pids[@]} )) || return 0
        sleep 0.5
    done
    for pid in "${pids[@]}"; do
        fail "LEAK: pid $pid ($(cat "/proc/$pid/comm" 2> /dev/null)) outlived the nested session: $(tr '\0' ' ' 2> /dev/null < "/proc/$pid/cmdline" | cut -c1-160)"
    done
    kill -TERM "${pids[@]}" 2> /dev/null
    sleep 1
    mapfile -t pids < <(session_pids)
    (( ${#pids[@]} == 0 )) || kill -KILL "${pids[@]}" 2> /dev/null
}
trap 'reap_session; if (( failed )); then echo "kept $WORK" >&2; else rm -rf "$WORK" "$RUN"; fi' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$HOME_DIR/.config/hypr" "$HOME_DIR/.config/koompi" "$HOME_DIR/.local/state/quickshell/user" \
    "$HOME_DIR/.local/share/applications" "$HOME_DIR/.cache" "$WORK/sysdata"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
cat > "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1.25 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}, "language": {"ui": "en_US"}}' > "$HOME_DIR/.config/koompi/config.json"
# daemons that stay up and say nothing, so a fixture is not wiped by a restart, and end when the
# shell that holds their stdin does
mkdir -p "$HOME_DIR/.local/bin"
printf '#!/usr/bin/env bash\nexec cat > /dev/null\n' > "$WORK/bin/koompi-shelld"
cp "$WORK/bin/koompi-shelld" "$HOME_DIR/.local/bin/koompi-global-menu-daemon"
chmod +x "$WORK/bin/koompi-shelld" "$HOME_DIR/.local/bin/koompi-global-menu-daemon"

write_entry() {
    printf '[Desktop Entry]\nType=Application\nName=%s\nIcon=%s\nExec=%s\n%s' "$2" "$3" "$4" "${5:+$5$'\n'}" > "$HOME_DIR/.local/share/applications/$1.desktop"
}
write_entry probe-app "Probe App" probe-icon "probe-app-bin %U" "StartupWMClass=ProbeWindowClass"
write_entry second-app "Second App" probe-icon "second-app-bin" "StartupWMClass=SecondWindowClass"
write_entry third-app "Third App" probe-icon "third-app-bin" "StartupWMClass=ThirdWindowClass"
write_entry shared-one "Shared One" shared-icon "sharedlauncher one"
write_entry shared-two "Shared Two" shared-icon "sharedlauncher two"

cat > "$WORK/shell/identity_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.bar
import "services/launch-match.js" as LaunchMatch

ShellRoot {
    id: probe
    property int failures: 0
    property int waited: 0

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
        if (!ok)
            probe.failures++;
    }

    function later(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", probe);
        t.interval = ms;
        t.triggered.connect(() => { t.destroy(); fn(); });
        t.start();
    }

    function win(address, cls, title) {
        return { address: address, "class": cls, initialClass: cls, title: title, mapped: true, pid: 1, workspace: { id: 1 }, size: [800, 600] };
    }

    function show(windows, active) {
        ShellServices.hyprland = { windows: windows, active_window: active, workspaces_numbered: [], monitors: [], layers: ({}) };
    }

    function after(fn) {
        probe.later(150, fn);
    }

    // what the shell has seen outlives a scenario, and a claim left by one would hide a fault in the next
    function fresh() {
        LaunchFeedback.pending = [];
        LaunchFeedback.seen = LaunchMatch.noneSeen();
    }

    // the opacity of the name as drawn, sampled, and the lowest the Opening line ever had
    function opacities(count, done) {
        const seen = [];
        let title = 1;
        const poll = Qt.createQmlObject("import QtQuick; Timer { interval: 100; repeat: true }", probe);
        poll.triggered.connect(() => {
            seen.push(identity.nameOpacity);
            title = Math.min(title, identity.titleOpacity);
            if (seen.length < count)
                return;
            poll.stop();
            poll.destroy();
            done(Math.min(...seen), Math.max(...seen), title);
        });
        poll.start();
    }

    function entries() {
        const resolve = (id, program) => LaunchFeedback.resolve(id, program)?.id ?? "none";
        probe.verdict(resolve("probe-app", "") === "probe-app", "resolve: a desktop entry id: " + resolve("probe-app", ""));
        probe.verdict(resolve("fileManager", "probe-app-bin") === "probe-app", "resolve: the program the Exec runs, under a role id: " + resolve("fileManager", "probe-app-bin"));
        probe.verdict(resolve("fileManager", "/opt/bin/probe-app-bin") === "probe-app", "resolve: the program given by path: " + resolve("fileManager", "/opt/bin/probe-app-bin"));
        probe.verdict(resolve("x", "ProbeWindowClass") === "none", "resolve: a window class is not a program, and no fuzzy lookup stands in for the Exec: " + resolve("x", "ProbeWindowClass"));
        probe.verdict(resolve("x", "sharedlauncher") === "none", "resolve: two entries on one program is a launcher, not an app: " + resolve("x", "sharedlauncher"));
        probe.verdict(resolve("x", "nothing-installed") === "none", "resolve: nothing installed: " + resolve("x", "nothing-installed"));
        probe.verdict(resolve("x", "") === "none", "resolve: no program at all: " + resolve("x", ""));
    }

    function emptyDesktop() {
        probe.show([], null);
        probe.after(() => {
            probe.verdict(identity.nameText === "Desktop", "no window: the name is Desktop: '" + identity.nameText + "'");
            probe.verdict(!identity.nameElided, "no window: the name is not cut short at this scale");
            probe.verdict(identity.titleText === "", "no window: no second line: '" + identity.titleText + "'");
            probe.show([], ({}));
            probe.after(() => {
                probe.verdict(identity.nameText === "Desktop" && identity.titleText === "", "no active window (an empty object): '" + identity.nameText + "' over '" + identity.titleText + "'");
                probe.focusedWindow();
            });
        });
    }

    function focusedWindow() {
        const dolphin = probe.win("0xa1", "org.kde.dolphin", "Home - Dolphin");
        probe.show([dolphin], dolphin);
        GlobalMenuService.menuItems = [{ id: 1, label: "File", items: [] }];
        probe.after(() => {
            probe.verdict(identity.nameText === "Dolphin", "a focused window: its name: '" + identity.nameText + "'");
            probe.verdict(!identity.nameElided, "a focused window: the name is not cut short at this scale");
            probe.verdict(identity.titleText === "Home", "a focused window: its title without the app's name: '" + identity.titleText + "'");
            probe.verdict(identity.menuShown, "a focused window: its menus show");
            probe.verdict(!identity.launching && !identity.pulsing && identity.nameOpacity === 1 && identity.titleOpacity === 1, "nothing launching: no pulse, full opacity");
            probe.longNames(dolphin);
        });
    }

    function longNames(dolphin) {
        const names = ["Visual Studio Code", "Okular", "Slow Probe"];
        const next = () => {
            const name = names.shift();
            if (!name) {
                LaunchFeedback.pending = [];
                probe.after(() => probe.opening(dolphin));
                return;
            }
            LaunchFeedback.pending = [];
            LaunchFeedback.add({ id: "name", entryId: "name", name: name, icon: "probe-icon", program: "name" });
            probe.after(() => {
                probe.verdict(identity.nameText === name && !identity.nameElided, "a launch: '" + name + "' is whole at this scale: '" + identity.nameText + "'");
                next();
            });
        };
        next();
    }

    // no startupClass here, so the window below can only be matched by the entry lookup
    function opening(dolphin) {
        LaunchFeedback.add({ id: "probe-app", entryId: "probe-app", name: "Probe App", icon: "probe-icon", program: "probe-app-bin" });
        probe.after(() => {
            probe.verdict(identity.launching, "a launch: the identity says so");
            probe.verdict(identity.nameText === "Probe App" && !identity.nameElided, "a launch: the app's name, whole, not the focused window's: '" + identity.nameText + "'");
            probe.verdict(identity.titleText === "Opening…", "a launch: Opening... under it: '" + identity.titleText + "'");
            probe.verdict(!identity.actionsAvailable, "a launch: the identity is not a target for the focused window's actions");
            probe.verdict(!identity.menuShown, "a launch: the menus of the window being left step aside");
            probe.verdict(identity.pulsing, "a launch: it pulses");
            probe.opacities(24, (low, high, title) => {
                probe.verdict(low <= 0.8 && high >= 0.95, "a launch: the pulse is seen on the name, opacity " + low.toFixed(2) + " to " + high.toFixed(2));
                probe.verdict(low >= 0.69, "a launch: the pulse never takes the name below the opacity that keeps 4.5:1 on both palettes: " + low.toFixed(2));
                probe.verdict(title === 1, "a launch: the Opening line is never dimmed: " + title.toFixed(2));
                probe.reduced(dolphin);
            });
        });
    }

    function reduced(dolphin) {
        Config.options.appearance.reduceMotion = true;
        probe.later(300, () => {
            probe.verdict(!identity.pulsing, "reduce motion: the pulse is stopped");
            probe.opacities(8, (low, high, title) => {
                probe.verdict(low === high && low >= 0.69 && low <= 0.75, "reduce motion: a held dim state, opacity " + low.toFixed(2) + " to " + high.toFixed(2));
                probe.verdict(title === 1, "reduce motion: the Opening line stays as legible as ever: " + title.toFixed(2));
                Config.options.appearance.reduceMotion = false;
                probe.later(200, () => probe.ending(dolphin));
            });
        });
    }

    function ending(dolphin) {
        const other = probe.win("0xb1", "okular", "Okular");
        probe.show([dolphin, other], other);
        probe.after(() => {
            probe.verdict(identity.launching, "another app's window does not end it: '" + identity.nameText + "'");
            const mine = probe.win("0xb2", "ProbeWindowClass", "Probe window");
            probe.show([dolphin, other, mine], mine);
            probe.after(() => {
                probe.verdict(!identity.launching, "a window with the entry's StartupWMClass ends it, found by DesktopEntries.heuristicLookup");
                probe.verdict(identity.nameText === "ProbeWindowClass", "the real window's identity follows: '" + identity.nameText + "'");
                probe.verdict(identity.titleText === "Probe window", "the real window's title follows: '" + identity.titleText + "'");
                probe.verdict(!identity.pulsing && identity.nameOpacity === 1 && identity.menuShown, "and the pulse is gone and the menus are back");
                probe.terminalApp();
            });
        });
    }

    function terminalApp() {
        LaunchFeedback.begin({ id: "tui-app", name: "Tui App", icon: "x", startupClass: "", command: ["tui-app"], runInTerminal: true });
        probe.after(() => {
            probe.verdict(!identity.launching, "an app that runs in a terminal is not announced: its window is the terminal's");
            probe.relaunch();
        });
    }

    // the app's window has been up and focused for a while when a key bind starts the app again, and
    // the notice reaches the shell 100 ms after the bind: that focus is older than the launch
    function relaunch() {
        probe.fresh();
        const open = probe.win("0xe1", "ProbeWindowClass", "Open window");
        probe.show([open], null);
        probe.after(() => {
            probe.show([open], open);
            probe.later(300, () => {
                LaunchFeedback.add({ id: "probe-app", entryId: "probe-app", name: "Probe App", icon: "probe-icon", program: "probe-app-bin", startupClass: "ProbeWindowClass", startedAt: Date.now() - 100 });
                probe.after(() => {
                    probe.verdict(identity.launching && identity.nameText === "Probe App", "relaunch: focus that was there before the launch does not end it: '" + identity.nameText + "'");
                    const second = probe.win("0xe2", "ProbeWindowClass", "Second window");
                    probe.show([open, second], second);
                    probe.after(() => {
                        probe.verdict(!identity.launching && identity.titleText === "Second window", "relaunch: its own window does: '" + identity.titleText + "'");
                        probe.closed();
                    });
                });
            });
        });
    }

    // the app is started again a moment before the shell hears that the window of the first start has closed
    function closed() {
        probe.fresh();
        const first = probe.win("0xf1", "ProbeWindowClass", "First window");
        probe.show([], null);
        probe.after(() => {
            LaunchFeedback.begin(DesktopEntries.byId("probe-app"));
            probe.show([first], null);
            probe.after(() => {
                probe.show([first], first);
                probe.after(() => {
                    probe.verdict(!identity.launching, "closed: the first launch ended at its window");
                    LaunchFeedback.add({ id: "probe-app", entryId: "probe-app", name: "Probe App", icon: "probe-icon", program: "probe-app-bin", startupClass: "ProbeWindowClass", startedAt: Date.now() - 60 });
                    probe.after(() => {
                        probe.verdict(identity.launching && identity.nameText === "Probe App", "closed: the app started again shows Opening: '" + identity.nameText + "'");
                        probe.show([], null);
                        probe.after(() => {
                            probe.verdict(identity.launching && identity.nameText === "Probe App", "closed: hearing that the first window has closed does not end it: '" + identity.nameText + "'");
                            const next = probe.win("0xf2", "ProbeWindowClass", "Next window");
                            probe.show([next], next);
                            probe.after(() => {
                                probe.verdict(!identity.launching && identity.titleText === "Next window", "closed: its own window does: '" + identity.titleText + "'");
                                probe.several();
                            });
                        });
                    });
                });
            });
        });
    }

    // three apps started in the same second, as session restore starts them: the bar shows the newest,
    // each ends at its own window, and the one that never maps blocks nothing
    function several() {
        const ids = () => LaunchFeedback.pending.map(l => l.id).join(",");
        LaunchFeedback.pending = [];
        LaunchFeedback.ttl = 1500;
        for (const id of ["probe-app", "second-app", "third-app"])
            LaunchFeedback.begin(DesktopEntries.byId(id));
        probe.after(() => {
            probe.verdict(ids() === "probe-app,second-app,third-app", "several: three launches wait at once: " + ids());
            probe.verdict(identity.nameText === "Third App", "several: the bar shows the newest: '" + identity.nameText + "'");
            const second = probe.win("0xc2", "SecondWindowClass", "Second window");
            probe.show([second], second);
            probe.after(() => {
                probe.verdict(ids() === "probe-app,third-app", "several: a window ends its own launch, not the newest one: " + ids());
                probe.verdict(identity.nameText === "Third App", "several: and the bar still shows the newest: '" + identity.nameText + "'");
                const third = probe.win("0xc3", "ThirdWindowClass", "Third window");
                probe.show([second, third], third);
                probe.after(() => {
                    probe.verdict(ids() === "probe-app", "several: the next window ends the next launch: " + ids());
                    probe.verdict(identity.launching && identity.nameText === "Probe App", "several: the oldest, whose window has not come, shows once the newer ones have ended: '" + identity.nameText + "'");
                    probe.later(1700, () => {
                        probe.verdict(ids() === "" && !identity.launching, "several: the one that never maps ends at its own ttl: [" + ids() + "]");
                        probe.crowd();
                    });
                });
            });
        });
    }

    // more launches than the shell keeps: the oldest are forgotten and the bar shows the newest
    function crowd() {
        for (let i = 0; i < 9; i++)
            LaunchFeedback.add({ id: "n" + i, entryId: "n" + i, name: "App " + i, icon: "x", program: "n" + i });
        probe.after(() => {
            const kept = LaunchFeedback.pending.map(l => l.id).join(",");
            probe.verdict(kept === "n1,n2,n3,n4,n5,n6,n7,n8", "several: the shell keeps the eight newest launches: " + kept);
            probe.verdict(identity.nameText === "App 8", "several: and the bar shows the newest of them: '" + identity.nameText + "'");
            LaunchFeedback.pending = [];
            probe.expiring();
        });
    }

    function expiring() {
        LaunchFeedback.ttl = 700;
        LaunchFeedback.begin(DesktopEntries.byId("shared-one"));
        probe.after(() => {
            probe.verdict(identity.launching && identity.nameText === "Shared One", "a launch from a surface, with a real entry: '" + identity.nameText + "'");
            probe.later(1100, () => {
                probe.verdict(!identity.launching, "and is dropped when ttl passes");
                console.log("PROBE DONE " + probe.failures);
                Qt.quit();
            });
        });
    }

    PanelWindow {
        id: host
        anchors { left: true; top: true }
        implicitWidth: 520
        implicitHeight: 40
        color: "#1b1b1b"

        ActiveWindow {
            id: identity
            anchors.fill: parent
            anchors.leftMargin: 8
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.waited++;
            if (probe.waited > 300) {
                console.log("FAIL probe timed out");
                Qt.quit();
                return;
            }
            if (!Config.ready || DesktopEntries.byId("probe-app") === null)
                return;
            running = false;
            probe.entries();
            probe.emptyDesktop();
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
parent=$WAYLAND_DISPLAY

running() { local s; read -r _ _ s _ 2> /dev/null < "/proc/$1/stat" && [[ $s != Z ]]; }
# the compositor is asked to leave, and ended by pid if it does not
cleanup() {
    hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
    for _ in $(seq 1 20); do running "$hypr_pid" || break; sleep 0.25; done
    if running "$hypr_pid"; then
        kill "$hypr_pid" 2> /dev/null
        sleep 1
        kill -KILL "$hypr_pid" 2> /dev/null
    fi
    wait "$hypr_pid" 2> /dev/null
}

Hyprland -c "$HOME/.config/hypr/hyprland.lua" > "$WORK/hyprland.log" 2>&1 &
hypr_pid=$!
trap cleanup EXIT
for _ in $(seq 1 100); do sig=$(ls "$XDG_RUNTIME_DIR/hypr" 2> /dev/null | head -1); [[ -n $sig ]] && break; sleep 0.2; done
export HYPRLAND_INSTANCE_SIGNATURE=$sig
for _ in $(seq 1 100); do d=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | grep -v "^$parent$" | head -1); [[ -n $d ]] && break; sleep 0.2; done
export WAYLAND_DISPLAY=$d
for _ in $(seq 1 80); do [[ $(hyprctl monitors -j 2> /dev/null | jq length) -ge 1 ]] && break; sleep 0.5; done
if [[ $(hyprctl monitors -j 2> /dev/null | jq length) -ge 1 ]]; then
    echo ready > "$WORK/monitor"
    cd "$WORK/shell" || exit 1
    QT_QPA_PLATFORM=wayland timeout 100 qs -p identity_probe.qml > "$WORK/qs.log" 2>&1
else
    echo missing > "$WORK/monitor"
fi
SH
chmod +x "$WORK/inner.sh"

run_session() {
    RUN="$(mktemp -d /tmp/hr.XXXXXX)"
    chmod 700 "$RUN"
    rm -f "$WORK/monitor" "$WORK/qs.log"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY -u QT_QPA_PLATFORM WORK="$WORK" \
        HOME="$HOME_DIR" XDG_RUNTIME_DIR="$RUN" XDG_CONFIG_HOME="$HOME_DIR/.config" \
        XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" XDG_DATA_HOME="$HOME_DIR/.local/share" XDG_DATA_DIRS="$WORK/sysdata" \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" \
        timeout 200 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1480 --height 1000 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
    reap_session
    rm -rf "$RUN"
}

for attempt in 1 2 3; do
    run_session
    [[ "$(cat "$WORK/monitor" 2> /dev/null)" == ready ]] && break
    echo "attempt $attempt: KWin gave the nested Hyprland no output, starting the session again" >&2
done
[[ "$(cat "$WORK/monitor" 2> /dev/null)" == ready ]] || { fail "setup: the nested Hyprland never got an output from KWin, so nothing can be drawn"; exit 1; }

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q '^ DEBUG qml: PROBE DONE' <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    fail "the launch identity probe did not pass"
fi
if grep -qE 'Binding loop|TypeError|ReferenceError|Cannot assign' <<< "$out"; then
    grep -E 'Binding loop|TypeError|ReferenceError|Cannot assign' <<< "$out" >&2
    fail "a QML error while the identity ran"
fi
(( failed )) && exit 1
echo "ok   probe: Desktop alone on an empty desktop, Opening and a pulse while an app starts with the menus stepping aside, a held dim state under Reduce Motion, ended by its window or by ttl and not by a focus older than the launch, entries resolved by id and by program"
