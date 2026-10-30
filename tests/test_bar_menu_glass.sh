#!/usr/bin/env bash
# The menus that hang from the bar (the global menu, the window actions) are cut from the bar's
# glass. The real GlobalMenu and GlobalMenuPopup run under a Hyprland nested in headless KWin
# (private bus, own HOME and runtime dir) with the repo's Hyprland config, below a fixture bar
# window that carries what Bar.qml's window does (barScheme, barGlass, barSurface, barWallpaper).
#   Glass: the menu is the bar's tone at the bar's tint, its text the bar's scheme, flipped too.
#   On screen: a white window sits under the menu, and the menu still shows the same pixels as the
#   bar, because a layer is blurred from the wallpaper as the bar is. A popup would show the window.
#   A brighter band under the menu than under the bar: the tint rises until its text keeps 4.5:1.
#   A solid bar, or one drawn with no background: the bar's solid colour.
#   Placement: flush under the title (over it, for a bar along the bottom), a submenu beside its
#   entry, turned left at the screen's edge.
#   Keys: Down and Return activate the first entry.
#   BarTone: the strip is the top of the wallpaper (a crop honoured the fill's gravity, and cut the
#   middle), and the bands run top down.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in Hyprland hyprctl kwin_wayland qs dbus-run-session jq magick grim wtype; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, the bar's menus not drawn"; exit 0; }
done

# the fixture bar stands in for Bar.qml's window: it has to carry the same names
for name in barScheme barGlass barSurface barWallpaper; do
    grep -q "readonly property [a-zA-Z]* $name: barContent\." "$SHELL_ROOT/modules/koompi/bar/Bar.qml" \
        || fail "Bar.qml's window no longer carries $name, which the bar's menus read"
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
RUN="$WORK/no-session-yet"
HOME_DIR="$WORK/home"
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
        fail "LEAK: pid $pid ($(cat "/proc/$pid/comm" 2> /dev/null)) outlived the nested session"
    done
    kill -KILL "${pids[@]}" 2> /dev/null
}
trap 'reap_session; if (( failed )); then echo "kept $WORK" >&2; else rm -rf "$WORK" "$RUN"; fi' EXIT

mkdir -p "$WORK/shell" "$WORK/bin" "$HOME_DIR/.config/hypr/hyprland" "$HOME_DIR/.config/koompi" \
    "$HOME_DIR/.local/state/quickshell/user" "$HOME_DIR/.local/bin" "$HOME_DIR/.cache"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
# the repo's own Hyprland config, for its blur and layer rules; nothing started at login
hypr_src="$REPO_ROOT/dots/.config/hypr"
for entry in "$hypr_src"/*; do
    name=$(basename -- "$entry")
    [[ $name == hyprland || $name == hyprland.lua || $name == custom ]] && continue
    ln -s "$entry" "$HOME_DIR/.config/hypr/$name"
done
cp -r -- "$hypr_src/hyprland/." "$HOME_DIR/.config/hypr/hyprland/"
echo '-- nothing at login' > "$HOME_DIR/.config/hypr/hyprland/execs.lua"
grep -v 'custom\.' "$hypr_src/hyprland.lua" > "$HOME_DIR/.config/hypr/hyprland.lua"
cat >> "$HOME_DIR/.config/hypr/hyprland.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x800", position = "auto", scale = 1 })
hl.config({ misc = { disable_watchdog_warning = true }, ecosystem = { no_update_news = true, no_donation_nag = true } })
LUA
echo greeted > "$HOME_DIR/.local/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}, "language": {"ui": "en_US"}}' > "$HOME_DIR/.config/koompi/config.json"
printf '#!/usr/bin/env bash\nexec cat > /dev/null\n' > "$WORK/bin/koompi-shelld"
# the menu daemon writes down what the shell sends it
printf '#!/usr/bin/env bash\nexec cat >> %q\n' "$WORK/daemon.log" > "$HOME_DIR/.local/bin/koompi-global-menu-daemon"
chmod +x "$WORK/bin/koompi-shelld" "$HOME_DIR/.local/bin/koompi-global-menu-daemon"

# 16:10, as the screen: a flat gray, and one dark only in the strip under the bar
magick -size 640x400 xc:'#404040' "$WORK/flat.png"
magick -size 640x400 xc:'#e0e0e0' -fill '#101010' -draw 'rectangle 0,0 639,23' "$WORK/split.png"
magick -size 480x300 gradient:black-white "$WORK/ramp.png"

cat > "$WORK/shell/menu_glass_probe.qml" <<'QML'
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.koompi.bar

ShellRoot {
    id: probe
    property int failures: 0
    property int waited: 0
    readonly property string work: Quickshell.env("WORK")
    property string wall: probe.work + "/flat.png"
    property var glass: null
    property bool flipped: false
    property bool showBackground: true
    property real menuX: 200
    readonly property var chain: globalMenu.popupWindows

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
    function run(argv, done) {
        const p = Qt.createQmlObject("import Quickshell.Io; Process {}", probe);
        p.command = argv;
        p.exited.connect(() => { p.destroy(); done(); });
        p.running = true;
    }
    function same(a, b) {
        return Math.abs(a.r - b.r) < 0.002 && Math.abs(a.g - b.g) < 0.002 && Math.abs(a.b - b.b) < 0.002 && Math.abs(a.a - b.a) < 0.002;
    }
    function open(index, then) {
        globalMenu.closeMenu();
        probe.later(200, () => {
            globalMenu.switchTopLevel(index);
            probe.later(700, then);
        });
    }
    // a title button, out of the menu's row of them
    function title(index) {
        for (const child of globalMenu.children[0].children) {
            if (child.label === GlobalMenuService.menuItems[index].label)
                return child;
        }
        return null;
    }

    // A: glass in the theme's own tone
    function ownGlass() {
        probe.glass = { "flipped": false, "tint": host.barScheme.tintOver(BarTone.tones[probe.wall], 0.3) };
        probe.open(0, () => {
            const top = probe.chain[0];
            probe.verdict(!!top, "glass: the menu opens");
            if (!top)
                return probe.finish();
            probe.verdict(probe.same(top.surface, host.barSurface), "glass: the menu is the bar's glass, " + top.surface + " and the bar " + host.barSurface);
            const entry = top.entryItemAt(0);
            probe.verdict(probe.same(entry.foregroundColor, host.barScheme.fg), "glass: an entry's text is the bar's: " + entry.foregroundColor);
            const anchor = probe.title(0).mapToItem(null, 0, 0);
            probe.verdict(top.placedX === Math.round(anchor.x) && top.placedY === 40, "placement: flush under its title at " + top.placedX + "," + top.placedY + " (title at " + anchor.x + ")");
            const mx = top.placedX + 110, my = top.placedY + 42;
            probe.run(["sh", "-c", "hyprctl -j layers > \"$WORK/layers.json\"; hyprctl -j clients > \"$WORK/clients.json\"; grim \"$WORK/own.png\""], () => {
                console.log("PATCH own " + mx + " " + my);
                probe.flippedGlass();
            });
        });
    }

    // B: the other tone's glass, dark text on light glass in dark mode
    function flippedGlass() {
        probe.flipped = true;
        probe.glass = { "flipped": true, "tint": host.barScheme.tintOver(BarTone.tones[probe.wall], 0.3) };
        probe.open(0, () => {
            const top = probe.chain[0];
            probe.verdict(probe.same(top.surface, host.barSurface), "flipped: the menu is the bar's light glass, " + top.surface + " and the bar " + host.barSurface);
            probe.verdict(probe.same(top.entryItemAt(0).foregroundColor, host.barScheme.ink), "flipped: an entry's text is the bar's dark ink");
            probe.run(["grim", probe.work + "/flipped.png"], () => {
                console.log("PATCH flipped " + (top.placedX + 110) + " " + (top.placedY + 42));
                probe.flipped = false;
                probe.brighterBand();
            });
        });
    }

    // C: dark under the bar, bright under the menu
    function brighterBand() {
        probe.wall = probe.work + "/split.png";
        probe.glass = { "flipped": false, "tint": host.barScheme.tintOver(BarTone.tones[probe.wall], 0.3) };
        probe.open(0, () => {
            const top = probe.chain[0];
            const scheme = host.barScheme;
            probe.verdict(probe.glass.tint === 0.3, "band: the bar over its dark strip is at the floor: " + probe.glass.tint);
            probe.verdict(top.surface.a >= probe.glass.tint + 0.2, "band: the menu over the bright band is denser glass: " + top.surface.a.toFixed(2));
            const tiles = BarTone.under(probe.wall, top.placedY / 800, (top.placedY + top.implicitHeight) / 800);
            const wall = Math.max(...tiles.map(t => Math.min(1, t.mean + t.sd)));
            const a = top.surface.a;
            const under = Qt.rgba(a * scheme.glass.r + (1 - a) * wall, a * scheme.glass.g + (1 - a) * wall, a * scheme.glass.b + (1 - a) * wall, 1);
            for (const token of ["fg", "subtext"])
                probe.verdict(scheme.contrast(scheme[token], under) >= 4.5, "band: its " + token + " keeps 4.5:1 on the band's brightest, " + scheme.contrast(scheme[token], under).toFixed(2) + ":1");
            probe.wall = probe.work + "/flat.png";
            probe.solid();
        });
    }

    // D: a solid bar, then a bar drawn with no background
    function solid() {
        probe.glass = null;
        probe.open(0, () => {
            probe.verdict(probe.same(probe.chain[0].surface, Appearance.colors.colBarBackground), "solid: the menu is the solid bar's colour");
            probe.showBackground = false;
            probe.later(100, () => {
                probe.verdict(probe.same(probe.chain[0].surface, Appearance.colors.colBarBackground), "no background: the menu keeps the solid colour, not the bar's nothing");
                probe.showBackground = true;
                probe.submenus();
            });
        });
    }

    // E: a submenu beside its entry, and turned left where the screen ends
    function submenus() {
        probe.glass = { "flipped": false, "tint": host.barScheme.tintOver(BarTone.tones[probe.wall], 0.3) };
        probe.open(0, () => {
            const top = probe.chain[0];
            top.highlight = 2;
            top.openHighlightedChild();
            probe.later(500, () => {
                const sub = probe.chain[1];
                const entry = top.entryItemAt(2);
                const at = entry.mapToItem(null, 0, 0);
                probe.verdict(!!sub && sub.placedX === Math.round(top.placedX + at.x + entry.width + 5) && sub.placedY === Math.round(top.placedY + at.y),
                    "submenu: beside its entry at " + sub?.placedX + "," + sub?.placedY);
                probe.verdict(!!sub && probe.same(sub.surface, top.surface), "submenu: the same glass as its parent over the same wallpaper");
                probe.menuX = host.width - 160;
                probe.open(0, () => {
                    const edge = probe.chain[0];
                    edge.highlight = 2;
                    edge.openHighlightedChild();
                    probe.later(500, () => {
                        const turned = probe.chain[1];
                        const e = edge.entryItemAt(2).mapToItem(null, 0, 0);
                        probe.verdict(!!turned && turned.placedX + turned.implicitWidth <= edge.placedX + e.x - 4 && turned.placedX >= 0,
                            "submenu: turned left of its entry at the screen's right edge, at " + turned?.placedX);
                        probe.verdict(edge.placedX + edge.implicitWidth <= host.width, "top level: kept on the screen at the right edge, at " + edge.placedX);
                        probe.menuX = 200;
                        probe.keys();
                    });
                });
            });
        });
    }

    // F: the keyboard reaches the chain through the layers
    function keys() {
        probe.open(0, () => {
            probe.verdict(globalMenu.menuOpen, "keys: the focus grab holds with the menu a layer");
            probe.run(["wtype", "-k", "Down", "-k", "Return"], () => {
                probe.later(400, () => {
                    probe.verdict(!globalMenu.menuOpen, "keys: Down and Return activate and close");
                    probe.bottomBar();
                });
            });
        });
    }

    // G: a bar along the bottom: the menu grows up from its title and ends on the bar's edge
    function bottomBar() {
        Config.options.bar.bottom = true;
        probe.later(300, () => probe.open(0, () => {
            const top = probe.chain[0];
            const barTop = top.screen.height - 40;
            probe.verdict(top.placedY + top.implicitHeight === barTop, "bottom bar: the menu ends flush on the bar's top edge, at " + (top.placedY + top.implicitHeight) + " for " + barTop);
            Config.options.bar.bottom = false;
            probe.finish();
        }));
    }

    function finish() {
        console.log("PROBE DONE " + probe.failures);
        Qt.quit();
    }

    // the wallpaper, under everything: what a layer's blur sees
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "probe-wallpaper"
        exclusionMode: ExclusionMode.Ignore
        anchors { left: true; right: true; top: true; bottom: true }
        color: "black"
        Image {
            anchors.fill: parent
            source: "file://" + probe.wall
            fillMode: Image.Stretch
        }
    }

    // a white window under the menu
    FloatingWindow {
        title: "probe window"
        color: "white"
        implicitWidth: 1100
        implicitHeight: 700
    }

    PanelWindow {
        id: host
        WlrLayershell.namespace: "quickshell:bar"
        WlrLayershell.keyboardFocus: globalMenu.menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { left: true; right: true; top: !Config.options.bar.bottom; bottom: Config.options.bar.bottom }
        exclusiveZone: 40
        implicitHeight: 63
        color: "transparent"
        // the bar's surface is at the window's top edge, or its bottom one for a bar along the bottom
        readonly property real surfaceY: Config.options.bar.bottom ? host.height - 40 : 0
        readonly property BarScheme barScheme: BarScheme {
            flipped: probe.flipped
        }
        readonly property var barGlass: probe.glass
        readonly property color barSurface: !probe.showBackground ? "transparent"
            : probe.glass ? ColorUtils.applyAlpha(host.barScheme.glass, probe.glass.tint) : Appearance.colors.colBarBackground
        readonly property string barWallpaper: probe.wall

        Rectangle {
            y: host.surfaceY
            width: parent.width
            height: 40
            color: host.barSurface
        }
        GlobalMenu {
            id: globalMenu
            x: probe.menuX
            y: host.surfaceY
            height: 40
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.waited++;
            if (probe.waited > 400) {
                console.log("FAIL setup: the wallpaper was never measured");
                probe.finish();
            }
            if (probe.waited === 1) {
                BarTone.measure(probe.work + "/flat.png");
                BarTone.measure(probe.work + "/split.png");
                BarTone.measure(probe.work + "/ramp.png");
                GlobalMenuService.menuItems = [
                    { "id": 1, "label": "File", "enabled": true, "items": [
                        { "id": 11, "label": "New", "enabled": true },
                        { "id": 12, "label": "Open", "enabled": true },
                        { "id": 13, "label": "Recent", "enabled": true, "items": [
                            { "id": 131, "label": "notes.txt", "enabled": true },
                            { "id": 132, "label": "plan.md", "enabled": true }] },
                        { "id": 14, "sep": true },
                        { "id": 15, "label": "Quit", "enabled": true, "shortcut": "Ctrl+Q" }] },
                    { "id": 2, "label": "Edit", "enabled": true, "items": [{ "id": 21, "label": "Copy", "enabled": true }] }];
            }
            const ramp = BarTone.tones[probe.work + "/ramp.png"];
            if (!Config.ready || BarTone.tones[probe.work + "/flat.png"] === undefined || BarTone.tones[probe.work + "/split.png"] === undefined || ramp === undefined)
                return;
            running = false;
            const rows = BarTone.bands[probe.work + "/ramp.png"];
            probe.verdict(!!ramp && ramp.every(t => t.mean < 0.05), "BarTone: the strip is the top of a black-to-white ramp: " + (ramp ? ramp[0].mean.toFixed(3) : "unread"));
            probe.verdict(!!rows && rows.length === 10 && rows[0][0].mean < rows[9][0].mean && rows[9][0].mean > 0.9, "BarTone: ten bands, top down");
            probe.ownGlass();
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
    QT_QPA_PLATFORM=wayland timeout 100 qs -p menu_glass_probe.qml > "$WORK/qs.log" 2>&1
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
        XDG_STATE_HOME="$HOME_DIR/.local/state" XDG_CACHE_HOME="$HOME_DIR/.cache" \
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
    fail "the bar menu probe did not pass"
fi
if grep -qE 'Binding loop|TypeError|ReferenceError|Cannot assign' <<< "$out"; then
    grep -E 'Binding loop|TypeError|ReferenceError|Cannot assign' <<< "$out" >&2
    fail "a QML error while the menus ran"
fi

# the menu is a layer of its own, not a popup of the bar's
jq -e '.. | objects | select(.namespace? == "quickshell:barMenu")' "$WORK/layers.json" > /dev/null 2>&1 \
    || fail "the menu is not the quickshell:barMenu layer: $(jq -c '[.. | objects | .namespace? // empty]' "$WORK/layers.json" 2> /dev/null)"

# the pixels: a patch of the bar against a patch of the menu that has the white window under it
mean() { magick "$1" -crop "$4x$5+$2+$3" +repage -format '%[fx:round(mean.r*255)] %[fx:round(mean.g*255)] %[fx:round(mean.b*255)]' info:; }
while read -r _ shot mx my; do
    png="$WORK/$shot.png"
    [[ -f $png ]] || { fail "pixels: no $shot screenshot"; continue; }
    read -r br bg bb <<< "$(mean "$png" 1000 8 60 20)"
    read -r mr mg mb <<< "$(mean "$png" "$mx" "$my" 30 12)"
    if [[ $shot == own ]]; then
        jq -e --argjson x "$mx" --argjson y "$my" '[.[] | select(.title == "probe window")
            | select(.at[0] <= $x and .at[1] <= $y and .at[0] + .size[0] >= $x + 30 and .at[1] + .size[1] >= $y + 12)] | length > 0' \
            "$WORK/clients.json" > /dev/null 2>&1 \
            || fail "pixels: the probe window is not under the menu's patch: $(jq -c '[.[] | {title, at, size}]' "$WORK/clients.json" 2> /dev/null)"
        read -r wr _ _ <<< "$(mean "$png" 900 400 40 40)"
        (( wr >= 240 )) || fail "pixels: the window under the menu is not white ($wr)"
    fi
    for pair in "$br $mr" "$bg $mg" "$bb $mb"; do
        read -r b m <<< "$pair"
        (( b - m <= 3 && m - b <= 3 )) || { fail "pixels ($shot): the menu ($mr,$mg,$mb) is not the bar's glass ($br,$bg,$bb)"; break; }
    done
    echo "pixels ($shot): bar $br,$bg,$bb  menu $mr,$mg,$mb"
done < <(grep -oE 'PATCH [a-z]+ [0-9]+ [0-9]+' <<< "$out")

grep -q '^activate 11 ' "$WORK/daemon.log" 2> /dev/null || fail "keys: the daemon was not asked to activate the first entry: $(tr '\n' '|' < "$WORK/daemon.log" 2> /dev/null)"

(( failed )) && exit 1
echo "ok   bar menus: cut from the bar's glass, own tone or flipped, and the same on screen over a white window; denser over a brighter band, solid under a solid bar; flush under the title, submenus beside and turned at the edge; keys through the layers; BarTone reads the top strip"
