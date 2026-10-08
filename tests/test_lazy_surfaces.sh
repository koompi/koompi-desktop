#!/usr/bin/env bash
# A closed surface does not exist (docs/navigation.md, Panel contract). A probe runs the real surfaces in a headless KWin
# and drives them over IPC, asking each whether its LazySurface has built anything: nothing while closed, something once
# open, kept or dropped after the close. A Scope's children are not readable from QML, so each surface reports `built`.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
for tool in qs kwin_wayland dbus-run-session; do command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }; done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/config/koompi" "$WORK/state/quickshell/user" "$WORK/cache" "$WORK/data" "$WORK/rt" && chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"; done
echo greeted > "$WORK/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld" && chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/lazy_probe.qml" <<'QML'
import Quickshell
import Quickshell.Io
import QtQuick
import qs
import qs.modules.common
import qs.modules.koompi.cheatsheet
import qs.modules.koompi.launchpad
import qs.modules.koompi.mediaControls
import qs.modules.koompi.overview
import qs.modules.koompi.screensaver
import qs.modules.koompi.screenTranslator
import qs.modules.koompi.sessionScreen
import qs.modules.koompi.sidebarLeft
import qs.modules.koompi.sidebarRight
import qs.modules.koompi.tour

ShellRoot {
    id: probe
    readonly property var surfaces: ({ launchpad, cheatsheet, translator, media, search, grid, right, session, tour, saver, left })
    property int builds: 0
    property int drops: 0
    property bool unitOpen: false
    property int unitWarm: 1500

    Launchpad { id: launchpad } Cheatsheet { id: cheatsheet } ScreenTranslator { id: translator } MediaControls { id: media }
    SearchPanel { id: search } OverviewPanel { id: grid } SidebarRight { id: right } SessionScreen { id: session } Tour { id: tour }
    Screensaver { id: saver } SidebarLeft { id: left }
    LazySurface {
        id: unit
        open: probe.unitOpen
        keepWarm: probe.unitWarm
        component: QtObject {
            Component.onCompleted: probe.builds++
            Component.onDestruction: probe.drops++
        }
    }

    IpcHandler {
        target: "probe"
        function built(name: string): int { const b = probe.surfaces[name]?.built; return typeof b === "boolean" ? Number(b) : -1; }
        function flag(name: string, on: bool): void { GlobalStates[name] = on; }
        function openSearch(): void { search.open(); }
        function drawer(): string { return right.content?.drawer ?? "no content"; }
        function unitState(open: bool, warm: int): string {
            probe.unitWarm = warm;
            probe.unitOpen = open;
            return `${probe.builds} ${probe.drops} ${unit.item !== null}`;
        }
    }
}
QML

cat > "$WORK/inner.sh" <<'SH'
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell" || exit 1
qs -p lazy_probe.qml > "$WORK/qs.log" 2>&1 &
trap 'kill $!; wait $!' EXIT
call() { qs -p lazy_probe.qml ipc call "$@" 2> /dev/null < /dev/null; }
check() { if [[ "$2" == "$3" ]]; then echo "PASS $1"; else echo "FAIL $1: got '$2', wanted '$3'"; fi; }
for _ in $(seq 1 80); do call probe built launchpad > /dev/null && break; sleep 0.5; done
sleep 2

for name in launchpad cheatsheet translator media search grid right session tour saver left; do
    check "$name is not built while closed" "$(call probe built "$name")" 0
done
call sidebarRight drawer calendar; sleep 0.5
check "a drawer asked for on a closed right sidebar opens its page" "$(call probe drawer)" calendar
call sidebarRight close; sleep 0.3; call sidebarRight drawer todo; sleep 0.3
check "a drawer asked for on a warm closed sidebar opens its page" "$(call probe drawer)" todo
call sidebarRight drawer todo; sleep 0.3
check "the same drawer again closes it" "$(call probe drawer)" ""
call sidebarRight close

# a warm surface stays built after the close, a per-open one is dropped
while IFS='|' read -r name open close after; do
    call $open; sleep 1
    check "$name: $open builds it" "$(call probe built "$name")" 1
    call $close; sleep 0.3
    check "$name: $close leaves built=$after" "$(call probe built "$name")" "$after"
done <<'ROWS'
launchpad|launchpad open|launchpad close|1
cheatsheet|cheatsheet open|cheatsheet close|1
left|sidebarLeft open|sidebarLeft close|1
right|sidebarRight open|sidebarRight close|1
search|probe openSearch|probe flag searchOpen false|1
grid|probe flag overviewOpen true|probe flag overviewOpen false|1
session|session open|session close|0
saver|screensaver open|screensaver close|0
media|mediaControls open|mediaControls close|0
tour|probe flag tourOpen true|probe flag tourOpen false|0
ROWS

state() { call probe unitState "$@"; }
check "LazySurface builds on open" "$(state true 1500)" "1 0 true"
state false 1500 > /dev/null
check "open inside keepWarm is the same instance" "$(state true 1500)" "1 0 true"
state false 1500 > /dev/null; sleep 2
check "released once keepWarm has passed" "$(state false 1500)" "1 1 false"
state true 0 > /dev/null; check "keepWarm 0 releases at once" "$(state false 0)" "2 1 false"
echo DONE
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY WORK="$WORK" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" \
    XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" XDG_DATA_HOME="$WORK/data" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 240 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

grep -E '^(PASS|FAIL) ' "$WORK/kwin.log"
grep -qx DONE "$WORK/kwin.log" || { cat "$WORK/qs.log" >&2; fail "the probe did not finish"; }
! grep -q '^FAIL ' "$WORK/kwin.log" || fail "a closed surface is built, or an open one is not"
echo "ok   lazy surfaces: not built while closed, built on open, kept warm or dropped, a drawer on a closed sidebar"
