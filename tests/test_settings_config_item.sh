#!/usr/bin/env bash
# J05: Settings does not send people to a JSON file. The real settings.qml runs
# in a headless KWin on a private bus and runtime dir (nothing reaches the live
# session), the Quick page loads, and the item tree is read back:
#   - the "Not all options are available" banner and its "Copy path" button are gone
#   - no filled FloatingActionButton sits at the top of the navigation
#   - the navigation is every SettingsPages entry in order, then "Edit config file"
#     as the last, unselected item
#   - pressing that item opens config.json (xdg-open and its siblings are shimmed
#     to a log, so nothing is launched)
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

for tool in kwin_wayland qs dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/run" "$WORK/home" "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" \
    "$WORK/xdg/cache" "$WORK/xdg/data"
chmod 700 "$WORK/run"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"language": {"ui": "en_US"}, "windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
for opener in xdg-open kde-open kde-open5 kde-open6 gio gnome-open; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$WORK/opened" > "$WORK/bin/$opener"
done
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/settings_probe.qml" <<'QML'
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import Quickshell
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.settings

ShellRoot {
    id: probe
    property var win: null
    property int ticks: 0
    property bool clicked: false

    Component.onCompleted: {
        const component = Qt.createComponent("settings.qml");
        if (component.status !== Component.Ready) {
            console.log("FAIL settings.qml did not load: " + component.errorString());
            Qt.quit();
            return;
        }
        probe.win = component.createObject(probe);
    }

    function walk(item, visit) {
        visit(item);
        for (let i = 0; i < item.children.length; i++) probe.walk(item.children[i], visit);
    }

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
    }

    function shownWidth(item) {
        let width = item.width;
        for (let p = item.parent; p; p = p.parent)
            if (p.clip) width = Math.min(width, p.width);
        return width;
    }

    function snapshot() {
        const out = { buttons: [], texts: [], fabs: 0 };
        probe.walk(probe.win.contentItem, item => {
            if (String(item).startsWith("FloatingActionButton")) out.fabs++;
            if (typeof item.text === "string") out.texts.push(item.text);
            if (String(item).startsWith("NavigationRailButton"))
                out.buttons.push({ item: item, text: item.buttonText, shown: probe.shownWidth(item), y: item.mapToItem(probe.win.contentItem, 0, 0).y });
        });
        out.buttons.sort((a, b) => a.y - b.y);
        return out;
    }

    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks > 60 && !probe.win) {
                console.log("FAIL settings window never opened");
                Qt.quit();
                return;
            }
            if (!probe.win || !Config.ready) return;
            const snap = probe.snapshot();
            const loaded = snap.texts.includes(Translation.tr("Wallpaper & Colors"));
            if (!loaded && probe.ticks < 60) return;
            if (probe.ticks < 12) return;

            if (!probe.clicked) {
                probe.clicked = true;
                probe.verdict(loaded, "the Quick page rendered (its Wallpaper & Colors heading is in the tree)");
                probe.verdict(!snap.texts.some(t => t.includes("Not all options are available")), "no banner text anywhere in the tree");
                probe.verdict(!snap.texts.includes(Translation.tr("Copy path")), "no Copy path button");
                probe.verdict(snap.fabs === 0, "no FloatingActionButton in the window (found " + snap.fabs + ")");

                const names = SettingsPages.list.map(p => p.name).concat([Translation.tr("Edit config file")]);
                const shown = snap.buttons.map(b => b.text);
                probe.verdict(JSON.stringify(shown) === JSON.stringify(names),
                    "navigation is the page list then Edit config file, got " + JSON.stringify(shown));

                const last = snap.buttons[snap.buttons.length - 1];
                probe.verdict(snap.buttons.length > 0 && snap.buttons.every(b => b.shown > 40 && b.item.visible),
                    "every navigation item shows inside the rail, narrowest " + Math.min(...snap.buttons.map(b => b.shown)) + " px");
                if (last) {
                    probe.verdict(last.item.toggled === false, "the last item is not the selected one");
                    last.item.clicked();
                }
                return;
            }
            if (probe.ticks > 14) {
                console.log("PROBE DONE");
                Qt.quit();
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
qs -p "$WORK/shell/settings_probe.qml" > "$WORK/qs.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" QT_NO_XDG_DESKTOP_PORTAL=1 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" \
    XDG_RUNTIME_DIR="$WORK/run" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" \
    XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
grep -q 'PROBE DONE' <<< "$out" || fail "the probe never finished"
grep -q '^ DEBUG qml: FAIL' <<< "$out" && fail "the settings window does not match the contract above"

opened="$(cat "$WORK/opened" 2> /dev/null)"
if grep -qE "^file://.*/koompi/config\.json$" <<< "$opened" && grep -qF "$WORK/xdg/config/" <<< "$opened"; then
    echo "PASS pressing Edit config file opens $opened"
else
    fail "pressing Edit config file did not open the config file; opener got '${opened:-nothing}'"
fi

if (( failed )); then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    exit 1
fi
echo "ok   settings: no banner, no filled Config file button, Edit config file is the last navigation item and opens config.json"
