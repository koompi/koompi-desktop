#!/usr/bin/env bash
# waffle start menu, folder, taskbar and search launch apps through koompi-launch
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nothing probed"; exit 0; }
done

WORK="$(mktemp -d)" || exit 1
# unix socket paths cap at 108 bytes
RUNTIME="$(mktemp -d /tmp/lp.XXXXXX)" || exit 1
chmod 700 "$RUNTIME"
cleanup() {
    rm -rf "$WORK" "$RUNTIME"
}
trap cleanup EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/apps/applications" "$WORK/xdg/config/koompi" \
    "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"language": {"ui": "en_US"}, "windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"

desktop_entry() { # id, name, exec, extra lines
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n%s\n' "$2" "$3" "${4:-}" > "$WORK/apps/applications/$1.desktop"
}
desktop_entry fx.start 'Fx Start' 'fx-start %U'
desktop_entry fx.folder 'Fx Folder' 'fx-folder' 'Categories=FxFolder;'
desktop_entry fx.task 'Fx Task' 'fx-task' 'Actions=new-window;

[Desktop Action new-window]
Name=Fx New Window
Exec=fx-task --new-window'
desktop_entry org.kde.dolphin 'Dolphin' 'fx-dolphin %u' 'StartupWMClass=dolphin'

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/launch.log"\n' "$WORK" > "$WORK/bin/koompi-launch"
printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$(basename -- "$0")" "$*" >> "%s/direct.log"\n' "$WORK" > "$WORK/bin/fx-app"
chmod +x "$WORK/bin"/*
for app in fx-start fx-folder fx-task fx-dolphin; do
    ln -s fx-app "$WORK/bin/$app"
done

cat > "$WORK/shell/launch_probe.qml" <<'QML'
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import qs.services
import qs.modules.common
import qs.modules.waffle.bar.tasks
import qs.modules.waffle.startMenu
import qs.modules.waffle.startMenu.searchPage
import qs.modules.waffle.startMenu.startPage
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    property int ticks: 0
    property string stage: "load"
    property int stageTicks: 0
    property var context: null
    property var results: null

    Component { id: bigComp; BigAppGrid {} }
    Component { id: categoryComp; AggregatedAppCategoryModel {} }
    Component { id: folderComp; AppCategoryGrid {} }
    Component { id: taskComp; TaskAppButton {} }
    Component { id: contextComp; StartMenuContext {} }
    Component { id: resultsComp; SearchResults {} }

    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 1100
        implicitHeight: 700
    }

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  got=" + JSON.stringify(got) + " want=" + JSON.stringify(want)));
        if (!ok)
            probe.failures++;
    }

    function run(name, step) {
        try {
            step();
        } catch (e) {
            probe.check(`${name}: ran to the end`, String(e), "no error");
        }
    }

    function findAll(item, test) {
        const found = test(item) ? [item] : [];
        for (let i = 0; i < item.children.length; i++)
            found.push(...probe.findAll(item.children[i], test));
        return found;
    }

    function textsOf(root) {
        return probe.findAll(root, item => typeof item.text === "string" && item.text !== "").map(item => item.text);
    }

    function entryTiles(root) {
        return probe.findAll(root, item => item.desktopEntry !== undefined && typeof item.clicked === "function");
    }

    function startMenu() {
        const grid = bigComp.createObject(host.contentItem, { desktopEntries: [DesktopEntries.byId("fx.start")] });
        const tiles = probe.entryTiles(grid);
        probe.check("start menu: the pinned grid draws its one tile", tiles.map(t => t.desktopEntry.id), ["fx.start"]);
        tiles.forEach(tile => tile.clicked());

        const category = categoryComp.createObject(probe, { name: "Fx", categories: ["FxFolder"] });
        const cells = probe.entryTiles(folderComp.createObject(host.contentItem, { aggregatedCategory: category }));
        probe.check("start menu: the app folder draws its one app", cells.map(c => c.desktopEntry.id), ["fx.folder"]);
        cells.forEach(cell => cell.clicked());
    }

    function taskbar() {
        const task = taskComp.createObject(host.contentItem, { appEntry: { appId: "fx.task", pinned: true, toplevels: [] } });
        task.clicked();
        task.middleClickAction();
        const menus = probe.findAll(task, item => Array.isArray(item.model) && item.model.some(m => typeof m.action === "function"));
        probe.check("taskbar: the app button has its context menu", menus.length, 1);
        const pins = [Translation.tr("Pin to taskbar"), Translation.tr("Unpin from taskbar")];
        const starts = menus[0].model.filter(m => typeof m.action === "function" && !pins.includes(m.text));
        probe.check("taskbar: the menu starts the desktop action and the app", starts.map(m => m.text), ["Fx New Window", "Fx Task"]);
        starts.forEach(m => m.action());
    }

    function search() {
        probe.context = contextComp.createObject(probe);
        probe.results = resultsComp.createObject(host.contentItem, { context: probe.context, width: 1000, height: 560 });
        LauncherSearch.query = Config.options.search.prefix.app + "dolphin";
    }

    function pinRow() {
        const texts = probe.textsOf(probe.results);
        return ["Pin to taskbar", "Unpin from taskbar"].filter(row => texts.includes(Translation.tr(row)));
    }

    function openFromSearch() {
        probe.context.accepted();
        const open = probe.findAll(probe.results, item => item.text === Translation.tr("Open") && typeof item.clicked === "function");
        probe.check("search: the preview offers Open", open.length, 1);
        open.forEach(button => button.clicked());
    }

    function go(stage) {
        probe.stage = stage;
        probe.stageTicks = 0;
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.ticks++;
            probe.stageTicks++;
            if (probe.stage === "load") {
                if (Config.ready && DesktopEntries.applications.values.length > 0 && AppSearch.list.length > 0) {
                    probe.run("start menu", probe.startMenu);
                    probe.run("taskbar", probe.taskbar);
                    probe.run("search", probe.search);
                    probe.go("search");
                } else if (probe.ticks > 150) {
                    probe.check("config and desktop entries loaded", [Config.ready, DesktopEntries.applications.values.length], "in time");
                    probe.go("done");
                }
            } else if (probe.stage === "search") {
                if (probe.pinRow().length > 0 || probe.stageTicks > 60)
                    probe.go("act");
            } else if (probe.stage === "act") {
                probe.run("search", probe.openFromSearch);
                probe.go("settle");
            } else if (probe.stage === "settle") {
                // dispatches and launches leave on a socket and a process
                if (probe.stageTicks >= 10)
                    probe.go("done");
            } else if (probe.stage === "done") {
                console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
                running = false;
                Qt.quit();
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell" || exit 1
exec timeout 90 qs -p "$WORK/shell/launch_probe.qml" > "$WORK/probe.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

# wayland, not offscreen: Idle.qml in qs.services holds a PanelWindow, which has no offscreen backend
env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY HOME="$WORK/home" XDG_RUNTIME_DIR="$RUNTIME" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    XDG_DATA_HOME="$WORK/xdg/data" XDG_DATA_DIRS="$WORK/apps" PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" \
    QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

plain="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/probe.log" 2> /dev/null)"
if ! grep -q '^ DEBUG qml: PROBE OK' <<< "$plain"; then
    grep -E '^ DEBUG qml: (FAIL|INFO)' <<< "$plain" | sed 's/^ DEBUG qml: /     /' >&2
    grep -q '^ DEBUG qml: PROBE FAILED' <<< "$plain" || { grep -vE 'qmlscanner|^\s*$' <<< "$plain" | tail -30 >&2; fail "the probe never finished"; }
    fail "the waffle launch checks above failed"
fi

want_launches="--id fx.folder -- fx-folder
--id fx.start -- fx-start
--id fx.task -- fx-task
--id fx.task -- fx-task
--id fx.task -- fx-task
--id fx.task -- fx-task --new-window
--id org.kde.dolphin -- fx-dolphin
--id org.kde.dolphin -- fx-dolphin"
want_count="$(grep -c '' <<< "$want_launches")"
for _ in $(seq 1 30); do
    seen="$(grep -c '' "$WORK/launch.log" 2> /dev/null)"
    (( ${seen:-0} >= want_count )) && break
    sleep 0.1
done
launched="$(LC_ALL=C sort "$WORK/launch.log" 2> /dev/null)"
[[ "$launched" == "$(LC_ALL=C sort <<< "$want_launches")" ]] || fail "the apps were not all started through koompi-launch (- wanted, + saw):
$(diff <(LC_ALL=C sort <<< "$want_launches") <(printf '%s\n' "$launched"))"
[[ ! -s "$WORK/direct.log" ]] || fail "an app was started without koompi-launch, so it is outside app.slice and on the wrong platform:
$(cat "$WORK/direct.log")"

(( failed == 0 )) || exit 1
echo "ok   launch paths: waffle start menu, folder, taskbar and search start apps through koompi-launch"
