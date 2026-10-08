#!/usr/bin/env bash
# Launch feedback (audit 3.11, F10): which window ends a launch's "Opening X".
# services/launch-match.js is run as it is, on the entries and windows a real
# session has: one app is dolphin on xcb and org.kde.dolphin on Wayland, an app
# that raises the window it already has maps nothing, two launches of one app
# need two windows, and the notice from a key bind can reach the shell after the
# window it announces has already mapped. Every fixture is a shape the shell
# really receives.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MATCH_JS="$REPO_ROOT/dots/.config/quickshell/koompi/services/launch-match.js"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$MATCH_JS" ]] || fail "missing ${MATCH_JS#"$REPO_ROOT"/}"
# Quickshell's JS engine is not bun's: flatMap threw there, which bun cannot show.
if grep -nE '\.(flatMap|flat|at|replaceAll|findLast|toSorted|toReversed)\(|Object\.(hasOwn|fromEntries)' "$MATCH_JS"; then
    fail "launch-match.js uses a method the Quickshell JS engine lacks"
fi
if command -v bun > /dev/null 2>&1; then RUNNER=bun
elif command -v node > /dev/null 2>&1; then RUNNER=node
else echo "skip: neither bun nor node installed, launch-match.js not run"; exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sed '/^\.pragma /d' "$MATCH_JS" > "$WORK/match.mjs"
printf '\nexport { record, track, matches, settle, entryForProgram, programOf };\n' >> "$WORK/match.mjs"

cat > "$WORK/run.mjs" <<'EOF'
import { record, track, matches, settle, entryForProgram, programOf } from "./match.mjs";

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};

const entries = [
    { id: "org.kde.dolphin", name: "Dolphin", startupClass: "dolphin", command: ["dolphin"] },
    { id: "org.wezfurlong.wezterm", name: "WezTerm", startupClass: "org.wezfurlong.wezterm", command: ["wezterm", "start", "--cwd", "."] },
    { id: "org.telegram.desktop", name: "Telegram", startupClass: "TelegramDesktop", command: ["/usr/bin/Telegram", "--", "%u"] },
    { id: "org.kde.kdialog", name: "KDialog", startupClass: "", command: ["kdialog"] },
    { id: "app.one", name: "One", startupClass: "", command: ["flatpak", "run", "app.one"] },
    { id: "app.two", name: "Two", startupClass: "", command: ["flatpak", "run", "app.two"] },
    { id: "broken", name: "Broken", startupClass: "", command: [] },
];

// DesktopEntries.heuristicLookup on the class, as the shell passes it in
const byClass = {
    "dolphin": "org.kde.dolphin",
    "org.kde.dolphin": "org.kde.dolphin",
    "org.wezfurlong.wezterm": "org.wezfurlong.wezterm",
    "org.telegram.desktop": "org.telegram.desktop",
    "TelegramDesktop": "org.telegram.desktop",
    "org.kde.kdialog": "org.kde.kdialog",
    "": "org.kde.dolphin",
};
const entryOf = cls => byClass[cls] || "";

const win = (address, cls, extra = {}) => ({ address, "class": cls, initialClass: cls, mapped: true, pid: 100 + Number(address.slice(2)), ...extra });
const TTL = 8000;
const names = list => list.map(l => l.id).join(",");

// programOf and entryForProgram: the Exec's first word names the app, unless many entries share it
check("programOf takes the basename of the first word", programOf("/usr/bin/dolphin --new-window") === "dolphin");
check("programOf of nothing is empty", programOf(undefined) === "" && programOf("  ") === "");
check("entryForProgram finds dolphin", entryForProgram("dolphin", entries)?.id === "org.kde.dolphin");
check("entryForProgram strips a path", entryForProgram("/usr/bin/wezterm", entries)?.id === "org.wezfurlong.wezterm");
check("entryForProgram matches an Exec given by path", entryForProgram("Telegram", entries)?.id === "org.telegram.desktop");
check("entryForProgram is case sensitive, as a binary is", entryForProgram("telegram", entries) === null);
check("entryForProgram refuses a launcher shared by two entries", entryForProgram("flatpak", entries) === null);
check("entryForProgram finds nothing for nothing", entryForProgram("", entries) === null && entryForProgram("nope", entries) === null);

// record: what a launch answers to, and when it began
const rec = record({ id: "fileManager", entryId: "org.kde.dolphin", name: "Dolphin", icon: "org.kde.dolphin", startupClass: "dolphin", program: "dolphin", pid: 55, startedAt: 900 }, 1000);
check("record answers to the id, the entry, its stem, the program and the startup class, once each, in lower case",
    JSON.stringify(rec.names) === JSON.stringify(["filemanager", "org.kde.dolphin", "dolphin", "tui.filemanager"]), JSON.stringify(rec.names));
check("record begins at the time it was given", rec.startedAt === 900);
check("record begins now when it was given no time", record({ entryId: "x" }, 1000).startedAt === 1000);
check("record does not begin in the future, which no ttl would ever end", record({ entryId: "x", startedAt: 5000 }, 1000).startedAt === 1000);
check("an entry's id is the launch's id when none was given", record({ entryId: "org.kde.dolphin" }, 1000).id === "org.kde.dolphin");
check("an empty launch has no names to match", record({}, 1000).names.length === 0, JSON.stringify(record({}, 1000).names));

// matches, one evidence at a time
const only = (spec, w) => matches(record(spec, 1000), w, entryOf);
check("pid: the launched process's window", only({ pid: 4242 }, win("0x9", "anything", { pid: 4242 })));
check("pid: another process is not it", !only({ pid: 4242 }, win("0x9", "anything", { pid: 4243 })));
check("pid 0 matches no window, whatever its pid", !only({ pid: 0 }, win("0x9", "anything", { pid: 0 })));
check("entry id: xcb class", only({ entryId: "org.kde.dolphin" }, win("0x9", "dolphin")));
check("entry id: Wayland class", only({ entryId: "org.kde.dolphin" }, win("0x9", "org.kde.dolphin")));
check("entry id: a class only the lookup knows", only({ entryId: "org.telegram.desktop" }, win("0x9", "TelegramDesktop")));
check("entry id: another app is not it", !only({ entryId: "org.kde.dolphin" }, win("0x9", "org.wezfurlong.wezterm")));
check("StartupWMClass: matched without the entry lookup, in any case", only({ startupClass: "TelegramDesktop" }, win("0x9", "telegramdesktop")));
check("StartupWMClass: a neighbour's class is not it", !only({ startupClass: "TelegramDesktop" }, win("0x9", "telegram")));
check("class: the id the launch was given", only({ id: "slow-probe" }, win("0x9", "Slow-Probe")));
check("class: the program the launch ran", only({ program: "kdialog" }, win("0x9", "kdialog")));
check("class: the stem of the entry id is the xcb class", only({ entryId: "org.kde.kdialog" }, win("0x9", "kdialog")));
check("class: a TUI window is named TUI.<id>", only({ id: "sysmon-scratch", program: "wezterm" }, win("0x9", "TUI.sysmon-scratch")));
check("class: a longer name that merely ends the same is not it", !only({ entryId: "org.telegram.desktop" }, win("0x9", "org.foo.desktop")));
check("initialClass: the class a window had when it mapped", only({ entryId: "org.kde.dolphin" }, { address: "0x9", "class": "", initialClass: "dolphin", mapped: true, pid: 1 }));
check("an empty class never goes to the lookup, which answers an arbitrary entry for \"\"",
    !only({ entryId: "org.kde.dolphin" }, { address: "0x9", "class": "", initialClass: "", mapped: true, pid: 1 }));
check("no window is no match", !matches(record({ entryId: "org.kde.dolphin" }, 1000), null, entryOf));

// track: what the shell has seen, and when
const EMPTY = { first: {}, focus: "", focusSince: 0 };
const old = [win("0x1", "dolphin"), win("0x2", "kitty")];
const t100 = track(EMPTY, old, old[1], 100);
check("track stamps every window with the time it was first seen", t100.first["0x1"] === 100 && t100.first["0x2"] === 100);
const t200 = track(t100, [...old, win("0x3", "okular")], old[1], 200);
check("track keeps the first time of a window it knew, and stamps a new one", t200.first["0x1"] === 100 && t200.first["0x3"] === 200);
check("track forgets a window that is gone", track(t200, [old[0]], old[0], 300).first["0x2"] === undefined);
check("track moves the focus time only when the focus moves", t200.focusSince === 100 && track(t200, old, old[0], 300).focusSince === 300);
check("track with no focus", track(t200, old, null, 300).focus === "");

// settle: a window counts when it first showed up after the launch began
const dolphin = { id: "org.kde.dolphin", entryId: "org.kde.dolphin", name: "Dolphin" };
const begin = (spec, at) => record({ ...spec, startedAt: at }, at);
const seenAt = (windows, active, at, from = t100) => track(from, windows, active, at);
const settleAt = (launches, windows, active, at, seen = seenAt(windows, active, at)) => settle(launches, windows, active, entryOf, at, TTL, seen);
const dolphin1000 = () => [begin(dolphin, 1000)];

check("a launch waits while nothing maps", settleAt(dolphin1000(), [], null, 1100).length === 1);
check("a window it started with does not end it, though it matches", settleAt(dolphin1000(), old, old[1], 1100).length === 1);
check("a new window of the app ends it (xcb)", settleAt(dolphin1000(), [...old, win("0x3", "dolphin")], null, 1500).length === 0);
check("a new window of the app ends it (Wayland)", settleAt(dolphin1000(), [...old, win("0x3", "org.kde.dolphin")], null, 1500).length === 0);
check("a new window of another app does not", settleAt(dolphin1000(), [...old, win("0x3", "okular")], null, 1500).length === 1);
check("a window that has not mapped does not", settleAt(dolphin1000(), [...old, win("0x3", "dolphin", { mapped: false })], null, 1500).length === 1);
check("a window with no mapped flag counts as mapped", settleAt(dolphin1000(), [...old, { address: "0x3", "class": "dolphin", pid: 3 }], null, 1500).length === 0);

// the notice of a key bind is a qs process of its own: it can reach the shell after the window
const mapped = [...old, win("0x3", "dolphin")];
const seenMapped = seenAt(mapped, null, 1500);
const late = begin(dolphin, 1000);
check("a window that mapped before the shell heard of the launch still ends it", settleAt([late], mapped, null, 1700, seenMapped).length === 0);
check("a window seen before the launch began never does, however late the notice", settleAt([begin(dolphin, 1600)], mapped, null, 1700, seenMapped).length === 1);
check("a window first seen in the very millisecond the launch began is not new", settleAt([begin(dolphin, 1500)], mapped, null, 1700, seenMapped).length === 1);

const two = [begin({ ...dolphin, id: "a" }, 1000), begin({ ...dolphin, id: "b" }, 1100)];
check("one new window settles one of two launches of an app, the older", names(settleAt(two, mapped, null, 1500, seenMapped)) === "b");
check("two new windows settle both", settleAt(two, [...mapped, win("0x4", "dolphin")], null, 1500).length === 0);
check("settle leaves its input alone", two.length === 2 && two[0].id === "a");

check("focus moving to a matching window ends it: an app that raises what it has maps nothing",
    settleAt(dolphin1000(), old, old[0], 1500).length === 0);
check("focus staying where it was does not end it, though that window matches",
    settleAt(dolphin1000(), old, old[0], 1500, track(track(EMPTY, old, old[0], 100), old, old[0], 1500)).length === 1);
check("focus moving to an unrelated window does not", settleAt(dolphin1000(), old, old[1], 1500, track(track(EMPTY, old, old[0], 100), old, old[1], 1500)).length === 1);
check("a window that settled one launch is not the focus rule's for another", names(settleAt(two, mapped, mapped[2], 1500, seenMapped)) === "b");

check("a launch lives until ttl", settleAt(dolphin1000(), [], null, 1000 + TTL - 1).length === 1);
check("a launch is dropped at ttl", settleAt(dolphin1000(), [], null, 1000 + TTL).length === 0);
check("only the expired one is dropped", names(settleAt([begin({ id: "old", entryId: "x" }, 0 + 1), begin({ id: "new", entryId: "y" }, 9000)], [], null, 9500)) === "new");

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok   launch-match.js: pid, entry id, StartupWMClass and class end a launch, a window it started with does not, a late notice does not lose its window, one window settles one launch, ttl drops the rest");
EOF

"$RUNNER" "$WORK/run.mjs" || exit 1
