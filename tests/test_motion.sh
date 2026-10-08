#!/usr/bin/env bash
# J10 (audit F2, decision D6): the shell's motion budget, asserted through the public
# surface of the real Appearance singleton in a headless KWin on a private bus and
# runtime dir (nothing reaches the running session).
#   Roles: every role in Appearance.animation runs 200 ms or less, closes (Exit) in
#   150, moves small things (Small) in 120, and no curve, role or named, has a bezier
#   y control above 1. The role and curve names are read out of Appearance.qml, so a
#   new role is held to the same budget without touching this test.
#   Reduce Motion: with appearance.reduceMotion on, a spatial role takes 0 ms and the
#   effects role (fades, colours) 100 ms or less; with it off they come back.
#   The ladder and the waffle: every step of Appearance.animationDuration but snap is 0
#   with Reduce Motion on, so no Timer may take its interval from the ladder; each of
#   Looks.transition's animations is then 0 ms (a fade or a colour: 100 ms at most), its
#   slider velocity jumps, and WStackView's slide and the bar panels' close follow it.
#   The dots of ThinkingIndicator pulse with it off and hold still with it on.
#   Loops: every `loops: Animation.Infinite` block in the shell is read out of the source,
#   and one whose duration is 0 with Reduce Motion on (a ladder step but snap, a spatial
#   role, a mirror of one) must have a `running` that checks reduceMotion. The scan proves
#   itself on fixtures before it reads the tree.
#   Runtime: a real Behavior on x with the elementMove role is still in flight at
#   50 ms, and has landed after 40 ms with Reduce Motion on.
#   Surfaces: the real SidebarDrawer (the right panel's drawer pages) and the real
#   SearchWidget's pill are timed from the property's first step to its landing on its
#   final value, the work the change sets off first (a search, a list) left out: the
#   best of three, 300 ms at most (60 ms with Reduce Motion). A jump that follows a
#   150 ms block proves the clock leaves that work out.
#   The Hyprland half of the budget is test_motion_hypr.sh, the Hyprland modes are
#   test_hypr_modes.sh.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
APPEARANCE="$SHELL_ROOT/modules/common/Appearance.qml"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

roles="$(sed -n '/^    animation: QtObject {/,/^    }/p' "$APPEARANCE" | grep -oE 'property QtObject [A-Za-z]+' | awk '{print $3}' | tr '\n' ' ')"
curves="$(sed -n '/^    animationCurves: QtObject {/,/^    }/p' "$APPEARANCE" | grep -oE 'list<real> [A-Za-z]+' | awk '{print $2}' | tr '\n' ' ')"
[[ -n "$roles" && -n "$curves" ]] || { fail "found no animation roles or curves in Appearance.qml; the scan broke"; exit 1; }
rungs="$(sed -n '/^    animationDuration: QtObject {/,/^    }/p' "$APPEARANCE" | grep -oE 'property int [A-Za-z]+' | awk '{print $3}' | tr '\n' ' ')"
waffle="$(sed -n '/^    transition: QtObject {/,/^    }/p' "$SHELL_ROOT/modules/waffle/looks/Looks.qml" | grep -oE 'property Component [A-Za-z]+' | awk '{print $3}' | tr '\n' ' ')"
[[ -n "$rungs" && -n "$waffle" ]] || { fail "found no ladder rungs or waffle transitions; the scan broke"; exit 1; }
if borrowed="$(grep -rnE 'interval:[^/]*(animationDuration|transition\.duration)' "$SHELL_ROOT" --include='*.qml')"; then
    fail "a Timer takes its interval from the duration ladder, where every step but snap is 0 with Reduce Motion on: $borrowed"
fi

# every `loops: Animation.Infinite` block is read: a duration that is 0 with Reduce Motion on (a ladder step
# but snap, a spatial role, a mirror of one) is only allowed if the block's `running` checks reduceMotion
scan_loops() {
    python3 -I - "$1" <<'PY'
import re
import sys
from pathlib import Path

ZERO = re.compile(
    r"animationDuration\.(?!snap\b)\w+"
    r"|transition\.duration\.(?!snap\b)\w+"
    r"|Appearance\.animation\.(?!elementMoveFast\b)\w+\.duration"
    r"|animationCurves\.(?!expressiveEffectsDuration\b)\w*Duration"
)
LOOP = re.compile(r"loops:\s*(?:Animation\.Infinite|-1)\b")


def blocks(text):
    spans, stack, i, n = [], [], 0, len(text)
    while i < n:
        if text.startswith("//", i):
            i = text.find("\n", i)
            if i < 0:
                break
        elif text.startswith("/*", i):
            i = text.find("*/", i + 2)
            if i < 0:
                break
            i += 2
        elif text[i] in "\"'`":
            quote = text[i]
            i += 1
            while i < n and text[i] != quote:
                i += 2 if text[i] == "\\" else 1
            i += 1
        else:
            if text[i] == "{":
                stack.append(i)
            elif text[i] == "}" and stack:
                spans.append((stack.pop(), i))
            i += 1
    return spans


def risky(text):
    spans = blocks(text)
    hits = []
    for m in LOOP.finditer(text):
        around = [s for s in spans if s[0] < m.start() < s[1]]
        if not around:
            continue
        start, end = min(around, key=lambda s: s[1] - s[0])
        body = text[start:end]
        running = re.search(r"running:\s*([^\n]*)", body)
        if running and "reduceMotion" in running.group(1):
            continue
        for expr in re.findall(r"duration:\s*([^\n;]*)", body):
            found = ZERO.search(expr.split("//")[0])
            if found:
                hits.append((text.count("\n", 0, m.start()) + 1, found.group(0)))
                break
    return hits


LOOPING = "Item { SequentialAnimation on opacity { running: on; loops: Animation.Infinite\n NumberAnimation { duration: %s } } }"
for expr, want in [
    ("Appearance.animation.elementMove.duration", True),
    ("Appearance.animationDuration.slow", True),
    ("Looks.transition.duration.fast", True),
    ("Appearance.animationCurves.workspaceSlideDuration", True),
    ("Appearance.animation.elementMoveFast.duration", False),
    ("Appearance.animationDuration.snap", False),
    ("700", False),
]:
    if bool(risky(LOOPING % expr)) != want:
        print(f"the loop scan broke on '{expr}': wanted {want}")
        sys.exit(2)
if risky((LOOPING % "Appearance.animation.elementMove.duration").replace("running: on;", "running: on && !Appearance.reduceMotion;")):
    print("the loop scan broke: a loop whose running checks reduceMotion was flagged")
    sys.exit(2)

root = Path(sys.argv[1])
bad = []
for path in sorted(root.rglob("*.qml")):
    text = path.read_text(errors="replace")
    if "loops:" not in text:
        continue
    for line, expr in risky(text):
        bad.append(f"{path.relative_to(root)}:{line}: loops forever on {expr}, 0 ms with Reduce Motion on, and its running does not check reduceMotion")
if bad:
    print("\n".join(bad))
    sys.exit(1)
PY
}
if command -v python3 > /dev/null 2>&1; then
    looping="$(scan_loops "$SHELL_ROOT" 2>&1)" || fail "a looping animation can run at 0 ms with Reduce Motion on: $looping"
else
    echo "skip: python3 not installed, no scan of looping animations"
fi

grep -qE 'property bool reduceMotion: false' "$SHELL_ROOT/modules/common/Config.qml" \
    || fail "Config.qml has no appearance.reduceMotion defaulting to false"
grep -q 'Config.options.appearance.reduceMotion' "$APPEARANCE" \
    || fail "Appearance.qml does not read appearance.reduceMotion"
grep -rq 'Config.options.appearance.reduceMotion' "$SHELL_ROOT/modules/settings" \
    || fail "no Settings page writes appearance.reduceMotion"
(( failed )) || echo "ok   source: roles [${roles% }] and curves [${curves% }] read from Appearance.qml, appearance.reduceMotion in Config, Appearance and Settings, no Timer on the ladder, no looping animation that is 0 ms with Reduce Motion on"

for tool in kwin_wayland qs dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit "$failed"; }
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/home" "$WORK/config/koompi" "$WORK/state/quickshell/user" "$WORK/cache" "$WORK/data" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/motion_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.koompi.overview
import qs.modules.koompi.sidebarLeft.aiChat
import qs.modules.koompi.sidebarRight
import qs.modules.waffle.looks

ShellRoot {
    id: probe
    property var roles: Quickshell.env("PROBE_ROLES").split(" ").filter(r => r.length > 0)
    property var curves: Quickshell.env("PROBE_CURVES").split(" ").filter(c => c.length > 0)
    property var rungs: Quickshell.env("PROBE_RUNGS").split(" ").filter(r => r.length > 0)
    property var waffle: Quickshell.env("PROBE_WAFFLE").split(" ").filter(w => w.length > 0)
    property int failures: 0
    property int waited: 0
    property real wideWidth: 0
    property real narrowWidth: 0
    property real jump: 0

    function verdict(ok, text) {
        console.log((ok ? "PASS " : "FAIL ") + text);
        if (!ok) probe.failures++;
    }

    function later(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", probe);
        t.interval = ms;
        t.triggered.connect(() => { t.destroy(); fn(); });
        t.start();
    }

    function yMax(list) {
        let top = -Infinity;
        for (let i = 1; i < list.length; i += 2)
            top = Math.max(top, list[i]);
        return top;
    }

    function setReduce(on) {
        try {
            Config.options.appearance.reduceMotion = on;
            return true;
        } catch (e) {
            probe.verdict(false, "Config.options.appearance.reduceMotion cannot be set: " + e);
            return false;
        }
    }

    function checkTokens(reduced) {
        const tag = reduced ? "reduce motion on: " : "";
        for (const name of probe.roles) {
            const role = Appearance.animation[name];
            if (!role) { probe.verdict(false, tag + "role " + name + " is missing"); continue; }
            const ms = role.duration;
            const curve = role.bezierCurve;
            const top = curve ? probe.yMax(curve) : 0;
            if (!reduced) {
                console.log("INFO role " + name + " " + ms + " ms, y max " + top);
                probe.verdict(ms <= 200, name + " takes " + ms + " ms, budget 200");
                probe.verdict(top <= 1, name + " curve y max " + top + ", budget 1 (no overshoot)");
            } else if (role.spatial === false) {
                probe.verdict(ms > 0 && ms <= 100, tag + name + " is an effects role: " + ms + " ms, wants a crossfade of at most 100");
            } else {
                probe.verdict(ms === 0, tag + name + " is spatial: " + ms + " ms, wants 0");
            }
        }
        if (!reduced) {
            probe.verdict(Appearance.animation.elementMoveExit.duration <= 150, "panels close in " + Appearance.animation.elementMoveExit.duration + " ms, budget 150");
            probe.verdict(Appearance.animation.elementMoveSmall.duration <= 120, "small moves take " + Appearance.animation.elementMoveSmall.duration + " ms, budget 120");
            for (const name of probe.curves) {
                const list = Appearance.animationCurves[name];
                probe.verdict(list !== undefined && probe.yMax(list) <= 1, "curve " + name + " y max " + (list ? probe.yMax(list) : "missing") + ", budget 1");
            }
        } else {
            probe.verdict(Appearance.animationCurves.expressiveFastSpatialDuration === 0 && Appearance.animationCurves.expressiveDefaultSpatialDuration === 0,
                tag + "the direct spatial durations follow the roles");
            probe.verdict(Appearance.animationCurves.workspaceSlideDuration === 0, tag + "the wallpaper's workspace slide is mirrored off");
        }
    }

    function checkLadder(reduced) {
        const tag = reduced ? "reduce motion on: " : "";
        for (const name of probe.rungs) {
            const ms = Appearance.animationDuration[name];
            if (!reduced) probe.verdict(ms > 0, "the " + name + " step is " + ms + " ms");
            else if (name === "snap") probe.verdict(ms > 0 && ms <= 100, tag + "snap keeps its step: " + ms + " ms");
            else probe.verdict(ms === 0, tag + "the " + name + " step is " + ms + " ms, wants 0");
        }
        probe.verdict(Looks.transition.duration === Appearance.animationDuration, tag + "the waffle shares the shell's ladder");
    }

    function checkWaffle(reduced) {
        const tag = reduced ? "reduce motion on: " : "";
        for (const name of probe.waffle) {
            const anim = Looks.transition[name].createObject(bare, {});
            const ms = anim.duration;
            anim.destroy();
            if (!reduced) probe.verdict(ms > 0, "waffle " + name + " takes " + ms + " ms");
            else if (name === "color" || name === "opacity") probe.verdict(ms > 0 && ms <= 100, tag + "waffle " + name + " is an effect: " + ms + " ms, wants a crossfade of at most 100");
            else probe.verdict(ms === 0, tag + "waffle " + name + " is spatial: " + ms + " ms, wants 0");
        }
        probe.verdict(reduced ? Looks.transition.velocity >= 10000 : Looks.transition.velocity === 850, tag + "waffle sliders move at " + Looks.transition.velocity);
        probe.verdict(stack.pushDuration === (reduced ? 0 : 200), tag + "a waffle page slides for " + stack.pushDuration + " ms");
        probe.verdict(panel.closeAnimDuration === (reduced ? 0 : 150), tag + "a bar panel closes in " + panel.closeAnimDuration + " ms");
    }

    // the three dots of the thinking indicator, sampled for 800 ms
    function checkThinking(reduced, done) {
        const tag = reduced ? "reduce motion on: " : "";
        const dots = Array.from(thinking.children[0].children).filter(c => c.radius !== undefined);
        probe.verdict(dots.length === 3, tag + "the thinking indicator has " + dots.length + " dots, wants 3");
        const seen = dots.map(d => [d.opacity]);
        let taken = 0;
        const poll = Qt.createQmlObject("import QtQuick; Timer { interval: 40; repeat: true }", probe);
        poll.triggered.connect(() => {
            dots.forEach((d, i) => seen[i].push(d.opacity));
            if (++taken < 20) return;
            poll.stop();
            poll.destroy();
            const spans = seen.map(list => Math.max(...list) - Math.min(...list));
            const text = spans.map(s => s.toFixed(2)).join(" ");
            if (reduced) probe.verdict(spans.every(s => s === 0), tag + "the thinking dots hold still: opacity spans " + text);
            else probe.verdict(spans.some(s => s > 0.3), "the thinking dots pulse: opacity spans " + text);
            done();
        });
        poll.start();
    }

    // the engine's own clock: each role's NumberAnimation, started on a bare item,
    // from start() to `running` going false; the best of three, like settle
    function timeRoles(reduced, done) {
        const tag = reduced ? "reduce motion on: " : "";
        const queue = probe.roles.filter(name => Appearance.animation[name] && Appearance.animation[name].numberAnimation);
        const next = () => {
            if (queue.length === 0) { done(); return; }
            const name = queue.shift();
            const role = Appearance.animation[name];
            const best = { ms: 1e9, runs: 0 };
            const once = () => {
                const anim = role.numberAnimation.createObject(probe, { target: bare, property: "x", from: 0, to: 100 });
                const t0 = Date.now();
                anim.runningChanged.connect(() => {
                    if (anim.running) return;
                    best.ms = Math.min(best.ms, Date.now() - t0);
                    anim.destroy();
                    if (++best.runs < 3) { once(); return; }
                    console.log("INFO ran " + tag + name + " " + best.ms + " ms");
                    const limit = !reduced ? 260 : role.spatial === false ? 160 : 60;
                    probe.verdict(best.ms <= limit, tag + name + " animation ran " + best.ms + " ms from start to running false, limit " + limit);
                    next();
                });
                anim.start();
            };
            once();
        };
        next();
    }

    // best of three: a stall in the machine only ever makes a run slower. Each run
    // starts from `reset`, waits for it to land, triggers, and times `read` from its
    // first step until it returns `target`; the work a trigger sets off first (a
    // search) is not the animation, and load stretches it.
    function settle(label, budget, reset, trigger, read, target, done) {
        const best = { ms: 1e9, runs: 0 };
        const once = () => {
            reset();
            probe.later(700, () => {
                const rest = read();
                const t0 = Date.now();
                let first = 0;
                trigger();
                const poll = Qt.createQmlObject("import QtQuick; Timer { interval: 3; repeat: true }", probe);
                poll.triggered.connect(() => {
                    const now = Date.now();
                    const value = read();
                    const landed = value === target;
                    if (first === 0 && value !== rest) first = now;
                    if (!landed && now - t0 <= 2500) return;
                    const spent = landed ? now - (first || t0) : now - t0;
                    poll.stop();
                    poll.destroy();
                    best.ms = Math.min(best.ms, spent);
                    if (++best.runs < 3) { once(); return; }
                    console.log("INFO settle " + label + " " + best.ms + " ms");
                    probe.verdict(best.ms <= budget, label + " settles in " + best.ms + " ms, budget " + budget);
                    done();
                });
                poll.start();
            });
        };
        once();
    }

    function proveSettle(done) {
        probe.settle("a jump after a 150 ms block", 60, () => { probe.jump = 0; }, () => {
            const end = Date.now() + 150;
            while (Date.now() < end) {}
            probe.jump = 1;
        }, () => probe.jump, 1, done);
    }

    function findField(item) {
        if (item.placeholderText !== undefined) return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = probe.findField(item.children[i]);
            if (found) return found;
        }
        return null;
    }

    function surfaces(budget, done) {
        const tag = budget < 100 ? "reduce motion on: " : "";
        probe.settle(tag + "drawer opens", budget, () => { drawer.shown = false; }, () => { drawer.shown = true; }, () => drawer.x, 0, () => {
            probe.settle(tag + "drawer closes", budget, () => { drawer.shown = true; }, () => { drawer.shown = false; }, () => drawer.x, drawer.width, () => {
                probe.measureSearch(tag, budget, done);
            });
        });
    }

    function measureSearch(tag, budget, done) {
        const field = probe.findField(search);
        if (!field) { probe.verdict(false, tag + "no text field inside the search widget"); done(); return; }
        GlobalStates.searchOpen = true;
        search.cancelSearch();
        LauncherSearch.query = "";
        probe.later(900, () => {
            probe.narrowWidth = field.implicitWidth;
            LauncherSearch.query = "a";
            probe.later(1300, () => {
                probe.wideWidth = field.implicitWidth;
                probe.verdict(probe.wideWidth > probe.narrowWidth, tag + "the search pill has two widths to move between: " + probe.narrowWidth + " and " + probe.wideWidth);
                probe.settle(tag + "search pill grows", budget, () => { LauncherSearch.query = ""; }, () => { LauncherSearch.query = "a"; },
                    () => field.implicitWidth, probe.wideWidth, () => {
                        GlobalStates.searchOpen = false;
                        done();
                    });
            });
        });
    }

    function runtime(reduced, done) {
        const tag = reduced ? "reduce motion on: " : "";
        box.x = 0;
        probe.later(400, () => {
            box.x = 100;
            probe.later(reduced ? 40 : 50, () => {
                if (reduced) probe.verdict(box.x === 100, tag + "a Behavior on x with elementMove has landed after 40 ms: x " + box.x);
                else probe.verdict(box.x > 0 && box.x < 100, "a Behavior on x with elementMove is still in flight at 50 ms: x " + box.x);
                probe.later(400, () => {
                    probe.verdict(box.x === 100, tag + "and lands on 100: " + box.x);
                    done();
                });
            });
        });
    }

    FloatingWindow {
        visible: true
        implicitWidth: 1000
        implicitHeight: 760
        color: "#202020"
        Item {
            anchors.fill: parent
            Item {
                id: bare
            }
            ThinkingIndicator {
                id: thinking
            }
            WStackView {
                id: stack
            }
            WBarAttachedPanelContent {
                id: panel
                contentItem: Item {}
            }
            Rectangle {
                id: box
                y: 5
                width: 10
                height: 10
                Behavior on x {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
            Item {
                x: 200
                width: 420
                height: 500
                clip: true
                SidebarDrawer {
                    id: drawer
                    title: "probe"
                    sourceComponent: Item {}
                }
            }
            SearchWidget {
                id: search
                x: 100
                y: 520
            }
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            probe.waited++;
            if (probe.waited > 400) {
                console.log("FAIL probe timed out");
                Qt.quit();
                return;
            }
            if (!Config.ready) return;
            running = false;
            probe.checkTokens(false);
            probe.checkLadder(false);
            probe.checkWaffle(false);
            probe.checkThinking(false, () => probe.timeRoles(false, () => probe.runtime(false, () => probe.proveSettle(() => probe.surfaces(300, () => {
                if (!probe.setReduce(true)) { console.log("PROBE DONE"); Qt.quit(); return; }
                probe.later(300, () => {
                    probe.checkTokens(true);
                    probe.checkLadder(true);
                    probe.checkWaffle(true);
                    probe.checkThinking(true, () => probe.timeRoles(true, () => probe.runtime(true, () => probe.surfaces(60, () => {
                        probe.setReduce(false);
                        probe.later(300, () => {
                            probe.verdict(Appearance.animation.elementMove.duration > 0, "with reduce motion off again elementMove moves: " + Appearance.animation.elementMove.duration + " ms");
                            console.log("PROBE DONE " + probe.failures);
                            Qt.quit();
                        });
                    }))));
                });
            })))));
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell" || exit 1
timeout 120 qs -p motion_probe.qml > "$WORK/qs.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY PROBE_ROLES="$roles" PROBE_CURVES="$curves" PROBE_RUNGS="$rungs" PROBE_WAFFLE="$waffle" \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
    XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$WORK/rt" \
    timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|INFO|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q '^ DEBUG qml: PROBE DONE' <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    echo "--- probe output ---" >&2
    grep -vE "qmlscanner|GlobalShortcut|global_shortcuts|MESA|^\s*$" <<< "$out" | tail -40 >&2
    fail "the motion probe did not pass"
fi
if loops="$(grep -E 'Binding loop' <<< "$out")"; then
    echo "$loops" >&2
    fail "a QML binding loop"
fi
(( failed )) && exit 1
echo "ok   probe: every role inside the budget, Reduce Motion collapses spatial roles, the ladder and the waffle with them, the thinking dots hold still, the real drawer and search pill settle inside it"
