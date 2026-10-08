#!/usr/bin/env bash
# Launch feedback (audit 3.11, F10): which window ends a launch's "Opening X".
# services/launch-match.js is run as it is, on the entries and windows a real
# session has: one app is dolphin on xcb and org.kde.dolphin on Wayland, an app
# that raises the window it already has maps nothing, and two launches of one
# app need two windows. Every fixture is a shape the shell really receives.
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
printf '\nexport { record, matches, settle, pidMapped, entryForProgram, programOf };\n' >> "$WORK/match.mjs"

cat > "$WORK/run.mjs" <<'EOF'
import { record, matches, settle, pidMapped, entryForProgram, programOf } from "./match.mjs";

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
const NOW = 1_000_000;
const TTL = 8000;
const launch = (spec, windows = [], active = null) => record(spec, windows, active, NOW);
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

// record: what a launch will answer to, and what was already on screen
const existing = [win("0x1", "dolphin"), win("0x2", "kitty")];
const rec = launch({ id: "fileManager", entryId: "org.kde.dolphin", name: "Dolphin", icon: "org.kde.dolphin", startupClass: "dolphin", program: "dolphin", pid: 55 }, existing, existing[1]);
check("record keeps the windows it started with", rec.known["0x1"] === true && rec.known["0x2"] === true && rec.known["0x3"] === undefined);
check("record remembers the focus", rec.activeAtStart === "0x2");
check("record answers to the id, the entry, its stem, the program and the startup class, once each, in lower case",
    JSON.stringify(rec.names) === JSON.stringify(["filemanager", "org.kde.dolphin", "dolphin", "tui.filemanager"]), JSON.stringify(rec.names));
check("record with no windows and no focus", launch({ entryId: "x" }, [], null).activeAtStart === "");
check("an entry's id is the launch's id when none was given", launch({ entryId: "org.kde.dolphin" }).id === "org.kde.dolphin");
check("an empty launch has no names to match", launch({}).names.length === 0, JSON.stringify(launch({}).names));

// matches, one evidence at a time
const only = (spec, w) => matches(launch(spec), w, entryOf);
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
check("no window is no match", !matches(launch({ entryId: "org.kde.dolphin" }), null, entryOf));

// settle
const dolphin = { id: "org.kde.dolphin", entryId: "org.kde.dolphin", name: "Dolphin" };
const settleAt = (launches, windows, active = null, at = NOW + 100) => settle(launches, windows, active, entryOf, at, TTL);

check("a launch waits while nothing maps", settleAt([launch(dolphin, existing)], []).length === 1);
check("a window it started with does not end it, though it matches", settleAt([launch(dolphin, existing)], existing).length === 1);
check("a new window of the app ends it (xcb)", settleAt([launch(dolphin, existing)], [...existing, win("0x3", "dolphin")]).length === 0);
check("a new window of the app ends it (Wayland)", settleAt([launch(dolphin, existing)], [...existing, win("0x3", "org.kde.dolphin")]).length === 0);
check("a new window of another app does not", settleAt([launch(dolphin, existing)], [...existing, win("0x3", "okular")]).length === 1);
check("a window that has not mapped does not", settleAt([launch(dolphin, existing)], [...existing, win("0x3", "dolphin", { mapped: false })]).length === 1);
check("a window with no mapped flag counts as mapped", settleAt([launch(dolphin, existing)], [...existing, { address: "0x3", "class": "dolphin", pid: 3 }]).length === 0);

const two = [launch({ ...dolphin, id: "a" }, existing), launch({ ...dolphin, id: "b" }, existing)];
check("one new window settles one of two launches of an app, the older", names(settleAt(two, [...existing, win("0x3", "dolphin")])) === "b");
check("two new windows settle both", settleAt(two, [...existing, win("0x3", "dolphin"), win("0x4", "dolphin")]).length === 0);
check("settle leaves its input alone", two.length === 2 && two[0].id === "a");

check("focus moving to a matching window ends it: an app that raises what it has maps nothing",
    settleAt([launch(dolphin, existing, existing[1])], existing, existing[0]).length === 0);
check("focus staying where it was does not end it, though that window matches",
    settleAt([launch(dolphin, existing, existing[0])], existing, existing[0]).length === 1);
check("focus moving to an unrelated window does not", settleAt([launch(dolphin, existing, existing[0])], existing, existing[1]).length === 1);
check("a window that settled one launch is not the focus rule's for another",
    names(settleAt(two, [...existing, win("0x3", "dolphin")], win("0x3", "dolphin"))) === "b");

check("a launch lives until ttl", settleAt([launch(dolphin)], [], null, NOW + TTL - 1).length === 1);
check("a launch is dropped at ttl", settleAt([launch(dolphin)], [], null, NOW + TTL).length === 0);
check("only the expired one is dropped", names(settle([record({ id: "old", entryId: "x" }, [], null, NOW - TTL), launch({ id: "new", entryId: "y" })], [], null, entryOf, NOW + 1, TTL)) === "new");

check("pidMapped sees a window of that process", pidMapped(4242, [win("0x9", "x", { pid: 4242 })]));
check("pidMapped does not for another, or for 0", !pidMapped(4242, existing) && !pidMapped(0, [win("0x9", "x", { pid: 0 })]));

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok   launch-match.js: pid, entry id, StartupWMClass and class end a launch, a window it started with does not, one window settles one launch, ttl drops the rest");
EOF

"$RUNNER" "$WORK/run.mjs" || exit 1
