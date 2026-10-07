#!/usr/bin/env bash
# The Super+/ sheet inside its real panel, headless (audit 3.8): every description and
# chord stays inside its category column, no row spills into the next, the panel fits the
# screen, and the keybinds page scrolls so the last row can be reached. A probe opens the
# real Cheatsheet in a nested KWin at three screen sizes, binds from the shipped Lua
# config behind a hyprctl shim, and measures what the scene graph laid out.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
RECORDER="$SHELL_ROOT/services/hyprlandKeybinds/recorder.lua"
HYPR="$REPO_ROOT/dots/.config/hypr"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for tool in qs kwin_wayland dbus-run-session lua jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, the sheet layout is not measured"; exit 0; }
done
[[ -f "$RECORDER" ]] || fail "missing services/hyprlandKeybinds/recorder.lua"

WORK="$(mktemp -d)"
# a socket path has to fit 108 bytes, so the runtime dir is short
RUNTIME="$(mktemp -d /tmp/csl.XXXXXX)"
chmod 700 "$RUNTIME"
kept=0
cleanup() { (( kept )) && echo "kept $WORK" >&2 || rm -rf "$WORK"; rm -rf "$RUNTIME"; }
trap cleanup EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/xdg/data"

lua "$RECORDER" "$HYPR" hyprland.keybinds hyprland.keybinds_shell_extra custom.keybinds > "$WORK/binds.json" 2> "$WORK/rec.err" \
    || { cat "$WORK/rec.err" >&2; fail "recorder could not replay the shipped keybinds"; }
# the plain-text form `hyprctl binds` prints, one Lua-dispatched record per declaration
jq -r 'to_entries[] | "bindd\n\tmodmask: \(.value.modmask)\n\tsubmap: \(.value.submap)\n\tkey: \(.value.key)\n\tkeycode: 0\n\tcatchall: false\n\tdescription: \(.value.description)\n\tdispatcher: __lua\n\targ: \(.key)\n"' \
    "$WORK/binds.json" > "$WORK/binds.txt" || fail "could not turn the recorded binds into hyprctl output"

cat > "$WORK/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == binds ]]; then cat "$SHIM_BINDS"; exit 0; fi
line="$1"; shift; for a in "$@"; do line+=$'\t'"$a"; done
printf '%s\n' "$line" >> "$SHIM_LOG"
exit 0
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/*

for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
ln -s "$REPO_ROOT/dots/.config/fontconfig" "$WORK/xdg/config/fontconfig"
[[ -d $HOME/.local/share/fonts ]] && ln -s "$HOME/.local/share/fonts" "$WORK/xdg/data/fonts"

cat > "$WORK/shell/layout_probe.qml" <<'QML'
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.cheatsheet
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property bool expectScroll: Quickshell.env("PROBE_EXPECT_SCROLL") === "1"
    property int ticks: 0
    property int stage: 0
    property int mark: 0
    property real lastHeight: -1
    property real maxBottom: 0
    property real maxY: 0
    property int rowCount: 0

    Cheatsheet { id: sheet }

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
    }

    function find(obj, name, out) {
        if (!obj) return out;
        if (obj.objectName === name) out.push(obj);
        const kids = obj.children ?? [];
        for (let i = 0; i < kids.length; i++) probe.find(kids[i], name, out);
        return out;
    }

    // The cheatsheet window registers with the focus grab while it is open.
    function sheetWindow() {
        return GlobalFocusGrab.dismissable.find(w => w && w.contentItem) ?? null;
    }

    function parts() {
        const win = probe.sheetWindow();
        if (!win) return null;
        const flick = probe.find(win.contentItem, "cheatsheetColumns", [])[0];
        const search = probe.find(win.contentItem, "cheatsheetSearch", [])[0];
        const cats = probe.find(win.contentItem, "cheatsheetCategory", []);
        return flick && search ? { win: win, flick: flick, search: search, cats: cats } : null;
    }

    // The keycaps and the plus-key-or tail of every chord in a chord column.
    function pieces(column) {
        const out = [];
        for (let i = 0; i < (column?.children.length ?? 0); i++) {
            const flow = column.children[i];
            for (let j = 0; j < flow.children.length; j++)
                if (flow.children[j].width > 0) out.push(flow.children[j]);
        }
        return out;
    }

    // Where `item` sits in the scrolled content: its box in the flickable's content item.
    function box(item, flick) {
        const p = item.mapToItem(flick.contentItem, 0, 0);
        return { left: p.x, top: p.y, right: p.x + item.width, bottom: p.y + item.height };
    }

    // The panel itself, not only the page in it: on the screen, and below the bar.
    function checkBackground(p) {
        const panel = probe.find(p.win.contentItem, "cheatsheetPanel", [])[0];
        const sw = p.win.screen.width;
        const sh = p.win.screen.height;
        const b = panel ? panel.mapToItem(null, 0, 0) : null;
        probe.verdict(b !== null && b.x >= 0 && b.y >= Appearance.sizes.barHeight && b.x + panel.width <= sw && b.y + panel.height <= sh,
            "the panel is on the screen and below the bar: " + (b === null ? "no panel" :
                "x " + Math.round(b.x) + ".." + Math.round(b.x + panel.width) + " of " + sw
                + ", y " + Math.round(b.y) + ".." + Math.round(b.y + panel.height) + " of " + sh + ", bar " + Appearance.sizes.barHeight));
    }

    function checkPanel(p) {
        const f = p.flick.mapToItem(null, 0, 0);
        const sw = p.win.screen.width;
        const sh = p.win.screen.height;
        probe.verdict(f.x >= 0 && f.y >= 0 && f.x + p.flick.width <= sw && f.y + p.flick.height <= sh,
            "the keybinds viewport is on the screen: x " + Math.round(f.x) + ".." + Math.round(f.x + p.flick.width) + " of " + sw
                + ", y " + Math.round(f.y) + ".." + Math.round(f.y + p.flick.height) + " of " + sh);
    }

    // Every category takes the quarter of the page it was given, every description and
    // every keycap of a chord lies inside that quarter, a chord ends before its own
    // description starts, and a row holds both.
    function checkColumns(p) {
        const bad = [];
        let texts = 0;
        for (const cat of p.cats) {
            const column = cat.parent;
            const colBox = probe.box(column, p.flick);
            if (colBox.left < -0.5 || colBox.right > p.flick.width + 0.5)
                bad.push(cat.categoryName + " column leaves the page: " + Math.round(colBox.left) + ".." + Math.round(colBox.right) + " of " + Math.round(p.flick.width));
            if (cat.width > column.width + 0.5)
                bad.push(cat.categoryName + " is " + Math.round(cat.width) + " wide in a column of " + Math.round(column.width));
            const descs = probe.find(cat, "bindDescription", []);
            const chords = probe.find(cat, "bindChords", []);
            if (descs.length !== chords.length) bad.push(cat.categoryName + " has " + descs.length + " descriptions and " + chords.length + " chord columns");
            for (let i = 0; i < descs.length; i++) {
                const d = descs[i];
                const line = d.parent.parent.parent;
                const dBox = probe.box(d, p.flick);
                const painted = dBox.left + Math.min(d.contentWidth, d.width);
                texts++;
                probe.maxBottom = Math.max(probe.maxBottom, dBox.bottom);
                if (d.width > column.width + 0.5 || d.contentWidth > d.width + 0.5 || painted > colBox.right + 0.5 || dBox.left < colBox.left - 0.5)
                    bad.push(cat.categoryName + ": \"" + d.text + "\" ends at " + Math.round(painted) + ", its column at " + Math.round(colBox.right));
                if (d.mapToItem(line, 0, d.height).y > line.height + 0.5)
                    bad.push(cat.categoryName + ": \"" + d.text + "\" is taller than its row");
                const chordBox = chords[i] ? probe.box(chords[i], p.flick) : null;
                if (chordBox) probe.maxBottom = Math.max(probe.maxBottom, chordBox.bottom);
                const lineBox = probe.box(line, p.flick);
                for (const piece of probe.pieces(chords[i])) {
                    const pBox = probe.box(piece, p.flick);
                    probe.maxBottom = Math.max(probe.maxBottom, pBox.bottom);
                    if (pBox.right > dBox.left + 0.5 || pBox.right > colBox.right + 0.5)
                        bad.push(cat.categoryName + ": a keycap of \"" + d.text + "\" ends at " + Math.round(pBox.right) + ", its text starts at " + Math.round(dBox.left));
                    if (pBox.bottom > lineBox.bottom + 0.5)
                        bad.push(cat.categoryName + ": a keycap of \"" + d.text + "\" hangs below its row");
                }
            }
            probe.rowCount += descs.length;
        }
        probe.verdict(bad.length === 0 && texts > 90,
            texts + " rows in " + p.cats.length + " columns stay inside their column" + (bad.length ? ": " + bad.length + " out, first " + bad.slice(0, 5).join("; ") : ""));
    }

    // The element tiles of the Elements page, empty slots left out.
    function tiles(obj, out) {
        if (!obj) return out;
        if (obj.element !== undefined && obj.element.type !== undefined && obj.element.type !== "empty") out.push(obj);
        const kids = obj.children ?? [];
        for (let i = 0; i < kids.length; i++) probe.tiles(kids[i], out);
        return out;
    }

    function nameOf(tile) {
        for (let i = 0; i < tile.children.length; i++)
            if (tile.children[i].text === tile.element.name) return tile.children[i];
        return null;
    }

    // All 118 tiles whole inside the page and the panel's inner rect, each name inside
    // its tile and at least 9 px: the periodic table gives way to the panel, not the other way round.
    function checkElements(p) {
        const panel = probe.find(p.win.contentItem, "cheatsheetPanel", [])[0];
        const pb = panel.mapToItem(null, 0, 0);
        const inner = { left: pb.x + panel.padding, top: pb.y + panel.padding, right: pb.x + panel.width - panel.padding, bottom: pb.y + panel.height - panel.padding };
        const tiles = probe.tiles(p.win.contentItem, []);
        let page = tiles.length > 0 ? tiles[0] : null;
        while (page && !(page.clip === true && page.contentChildren !== undefined)) page = page.parent;
        const pageBox = page ? page.mapToItem(null, 0, 0) : { x: 0, y: 0 };
        const cut = [];
        let smallest = 1e9;
        let overshoot = -1e9;
        for (const t of tiles) {
            const b = t.mapToItem(null, 0, 0);
            const inside = b.x >= inner.left - 0.5 && b.y >= inner.top - 0.5 && b.x + t.width <= inner.right + 0.5 && b.y + t.height <= inner.bottom + 0.5
                && page !== null && b.x >= pageBox.x - 0.5 && b.y >= pageBox.y - 0.5 && b.x + t.width <= pageBox.x + page.width + 0.5 && b.y + t.height <= pageBox.y + page.height + 0.5;
            if (!inside) cut.push(t.element.symbol);
            const n = probe.nameOf(t);
            if (n) {
                smallest = Math.min(smallest, n.fontInfo.pixelSize);
                overshoot = Math.max(overshoot, n.contentWidth - t.width);
            }
        }
        probe.verdict(tiles.length === 118 && cut.length === 0,
            (tiles.length - cut.length) + " of " + tiles.length + " element tiles are whole inside the panel's inner rect"
                + (tiles.length > 0 ? " (tile " + Math.round(tiles[0].width) + "x" + Math.round(tiles[0].height) + ")" : "")
                + (cut.length ? ", cut: " + cut.slice(0, 14).join(" ") : ""));
        probe.verdict(tiles.length > 0 && smallest >= 9 && overshoot <= 0.5,
            "element names read at " + smallest + " px or more and stay inside their tile (widest is " + Math.round(overshoot * 10) / 10 + " px past it)");
    }

    function checkScroll(p) {
        probe.maxY = Math.max(0, p.flick.contentHeight - p.flick.height);
        probe.verdict(probe.maxBottom <= p.flick.contentHeight + 0.5,
            "no row lies past the scrollable height: lowest " + Math.round(probe.maxBottom) + " of " + Math.round(p.flick.contentHeight));
        if (probe.expectScroll)
            probe.verdict(p.flick.contentHeight > p.flick.height + 1,
                "the sheet is taller than its viewport and scrolls: " + Math.round(p.flick.contentHeight) + " over " + Math.round(p.flick.height));
        p.flick.contentY = probe.maxY;
    }

    Timer {
        id: clock
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks > 400) {
                console.log("FAIL probe timed out in stage " + probe.stage);
                Qt.quit();
                return;
            }
            const waited = probe.ticks - probe.mark;

            if (probe.stage === 0) {
                const ready = HyprlandKeybinds.keybinds.length > 0 && Object.keys(HyprlandKeybinds.recorded).length > 0;
                if (!ready) return;
                GlobalStates.cheatsheetOpen = true;
                probe.stage = 1;
                probe.mark = probe.ticks;
                return;
            }
            if (probe.stage === 7) {
                if (waited < 4) return;
                probe.verdict(!GlobalStates.cheatsheetOpen, "Enter runs the first match and closes the sheet");
                console.log("PROBE DONE");
                clock.stop();
                Qt.quit();
                return;
            }
            const p = probe.parts();
            if (!p) {
                if (waited > 40) {
                    console.log("FAIL the open sheet has no scrolling keybinds page");
                    Qt.quit();
                }
                return;
            }

            if (probe.stage === 1) {
                // laid out: the content height has stopped moving
                const settled = p.cats.length >= 8 && p.flick.contentHeight === probe.lastHeight;
                probe.lastHeight = p.flick.contentHeight;
                if (waited < 8 || !settled) return;
                probe.checkBackground(p);
                probe.checkPanel(p);
                probe.checkColumns(p);
                probe.checkScroll(p);
                probe.stage = 2;
                probe.mark = probe.ticks;
            } else if (probe.stage === 2) {
                if (waited < 8) return;
                probe.verdict(Math.abs(p.flick.contentY - probe.maxY) < 1,
                    "scrolled to the end: " + Math.round(p.flick.contentY) + " of " + Math.round(probe.maxY));
                probe.verdict(probe.maxBottom - p.flick.contentY <= p.flick.height + 0.5,
                    "the last row is in view at the end: its bottom " + Math.round(probe.maxBottom - p.flick.contentY) + " in a viewport of " + Math.round(p.flick.height));
                Persistent.states.cheatsheet.tabIndex = 1;
                probe.stage = 3;
                probe.mark = probe.ticks;
            } else if (probe.stage === 3) {
                if (waited < 8) return;
                probe.checkElements(p);
                Persistent.states.cheatsheet.tabIndex = 0;
                probe.stage = 4;
                probe.mark = probe.ticks;
            } else if (probe.stage === 4) {
                if (waited < 8) return;
                // every chord's text carries "Super", so this keeps most rows and the page still scrolls
                p.search.text = "super";
                probe.stage = 5;
                probe.mark = probe.ticks;
            } else if (probe.stage === 5) {
                if (waited < 8) return;
                const room = p.flick.contentHeight - p.flick.height;
                probe.verdict(room > 1, "a broad query still leaves " + Math.round(room) + " to scroll");
                probe.verdict(p.flick.contentY < 1, "a query puts the sheet back at the top: contentY " + Math.round(p.flick.contentY));
                p.search.text = "Toggle cheatsheet";
                probe.stage = 6;
                probe.mark = probe.ticks;
            } else if (probe.stage === 6) {
                if (waited < 8) return;
                const rows = probe.find(p.win.contentItem, "bindDescription", []).length;
                probe.verdict(rows > 0 && rows < probe.rowCount / 2, "a narrow query leaves " + rows + " of " + probe.rowCount + " rows");
                p.search.accepted();
                probe.stage = 7;
                probe.mark = probe.ticks;
            }
        }
    }
}
QML

# QT_QPA_PLATFORM=wayland on purpose: env.lua forces xcb session wide, and a probe that
# inherits it gets no layer shell, so the sheet never maps.
run_size() {
    local size="$1" expect="$2"
    local width="${size%x*}" height="${size#*x}"
    : > "$WORK/shim.log"
    cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell"
exec qs -p "$WORK/shell/layout_probe.qml" > "$WORK/qs-$size.log" 2>&1
SH
    chmod +x "$WORK/inner.sh"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
        PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland \
        SHIM_BINDS="$WORK/binds.txt" SHIM_LOG="$WORK/shim.log" HYPRLAND_CONFIG="$HYPR/hyprland.lua" \
        PROBE_EXPECT_SCROLL="$expect" HOME="$WORK/home" XDG_RUNTIME_DIR="$RUNTIME" \
        XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" \
        timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width "$width" --height "$height" \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin-$size.log" 2>&1
    local out
    out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs-$size.log" 2> /dev/null)"
    printf '%s\n' "$out" | grep -E '^ DEBUG qml: (PASS|FAIL)' | sed "s/^ DEBUG qml: /     $size  /"
    if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
        echo "--- probe output at $size ---" >&2
        grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -30 >&2
        kept=1
        fail "the sheet layout is wrong at $size"
    fi
    if loops="$(grep -E 'Binding loop' <<< "$out")"; then
        echo "$loops" >&2
        kept=1
        fail "the sheet has a QML binding loop at $size"
    fi
    # execDetached spawns the shim, so give it a moment
    sleep 1
    grep -qF $'dispatch\thl.dsp.global("quickshell:cheatsheetToggle")' "$WORK/shim.log" \
        || { cat "$WORK/shim.log" >&2; kept=1; fail "Enter did not dispatch the first match at $size"; }
}

# the biggest screen could fit every row one day, so scrolling is only demanded below it
run_size 1920x1200 1
run_size 1366x768 1
run_size 2560x1600 0
echo "ok   the sheet fits its columns and scrolls: 1920x1200, 1366x768, 2560x1600"
