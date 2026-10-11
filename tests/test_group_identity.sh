#!/usr/bin/env bash
# J55: the bar's app identity says which tab of a group the focused window is. The real ActiveWindow runs under a
# Hyprland nested in headless KWin (private bus, own HOME and runtime dir); the compositor's window list is a
# fixture. A window in a group of three reads "2/3" after its title, alone it reads nothing, a group of one reads
# nothing, and a window with no title still shows its tab.
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

    function win(address, title, grouped) {
        return { address: address, "class": "org.kde.dolphin", initialClass: "org.kde.dolphin", title: title, mapped: true, pid: 1, workspace: { id: 1 }, size: [800, 600], grouped: grouped };
    }

    function show(windows, active) {
        ShellServices.hyprland = { windows: windows, active_window: active, workspaces_numbered: [], monitors: [], layers: ({}) };
    }

    function scenarios() {
        const tabs = ["0xa1", "0xa2", "0xa3"];
        const alone = probe.win("0xc1", "Home - Dolphin", []);
        probe.show([alone], alone);
        probe.later(200, () => {
            probe.verdict(identity.groupTag === "", "a window alone: no tab tag: '" + identity.groupTag + "'");
            probe.verdict(identity.titleText === "Home", "a window alone: its title: '" + identity.titleText + "'");
            probe.verdict(identity.groupLabel === "", "a window alone: nothing drawn after the title");
            const second = probe.win("0xa2", "Docs - Dolphin", tabs);
            probe.show([probe.win("0xa1", "Home - Dolphin", tabs), second, probe.win("0xa3", "Pics - Dolphin", tabs)], second);
            probe.later(200, () => {
                probe.verdict(identity.groupTag === "2/3", "the second of three tabs reads 2/3: '" + identity.groupTag + "'");
                probe.verdict(identity.titleText === "Docs", "and the title is still its own: '" + identity.titleText + "'");
                probe.verdict(identity.groupLabel === "· 2/3", "and 2/3 is drawn after the title: '" + identity.groupLabel + "'");
                const third = probe.win("0xa3", "Pics - Dolphin", tabs);
                probe.show([probe.win("0xa1", "Home - Dolphin", tabs), probe.win("0xa2", "Docs - Dolphin", tabs), third], third);
                probe.later(200, () => {
                    probe.verdict(identity.groupTag === "3/3", "the next tab reads 3/3: '" + identity.groupTag + "'");
                    const two = ["0xd1", "0xd2"];
                    const bare = probe.win("0xd2", "", two);
                    probe.show([probe.win("0xd1", "x", two), bare], bare);
                    probe.later(200, () => {
                        probe.verdict(identity.groupTag === "2/2", "a group of two: its second tab reads 2/2: '" + identity.groupTag + "'");
                        probe.verdict(identity.groupLabel === "2/2", "a window with no title still shows its tab, without the dot: '" + identity.groupLabel + "'");
                        const one = probe.win("0xe1", "Solo - Dolphin", ["0xe1"]);
                        probe.show([one], one);
                        probe.later(200, () => {
                            probe.verdict(identity.groupTag === "", "a group of one: no tag: '" + identity.groupTag + "'");
                            console.log("PROBE DONE " + probe.failures);
                            Qt.quit();
                        });
                    });
                });
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
            if (!Config.ready)
                return;
            running = false;
            probe.scenarios();
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
source "$REPO_ROOT/tests/nested-hyprland.sh"

cleanup() { nested_hyprland_stop "$hypr_pid" "$HYPRLAND_INSTANCE_SIGNATURE"; }
if nested_hyprland_start "$HOME/.config/hypr/hyprland.lua" "$WORK/hyprland.log"; then
    trap cleanup EXIT
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
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY -u QT_QPA_PLATFORM WORK="$WORK" REPO_ROOT="$REPO_ROOT" \
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
    fail "the group identity probe did not pass"
fi
if grep -qE 'Binding loop|TypeError|ReferenceError|Cannot assign' <<< "$out"; then
    grep -E 'Binding loop|TypeError|ReferenceError|Cannot assign' <<< "$out" >&2
    fail "a QML error while the identity ran"
fi
(( failed )) && exit 1
echo "ok   probe: the bar reads 2/3 after the title of the second of three tabs, 3/3 for the third, 2/2 with no title, nothing for a window alone or a group of one"
