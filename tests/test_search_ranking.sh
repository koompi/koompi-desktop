#!/usr/bin/env bash
# J23: one Search list. services/launcherSearch/ranking.js blends the providers'
# rows under section headings (Top Hit, Applications, Commands and Settings,
# Files, Calculator, Clipboard), caps each section, and keeps the Top Hit and
# the cursor where they were when a row arrives late; file-format.js says where
# a file lives and when it changed. Both are pure JavaScript, run as shipped.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$REPO_ROOT/dots/.config/quickshell/koompi/services/launcherSearch"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in ranking.js file-format.js; do
    [[ -f "$DIR/$f" ]] || fail "missing services/launcherSearch/$f"
    # Quickshell's JS engine is not bun's: flatMap threw there, which bun cannot show.
    if grep -nE '\.(flatMap|flat|at|replaceAll|findLast|toSorted|toReversed)\(|Object\.(hasOwn|fromEntries)' "$DIR/$f"; then
        fail "$f uses a method the Quickshell JS engine lacks"
    fi
done
if command -v bun > /dev/null 2>&1; then RUNNER=bun
elif command -v node > /dev/null 2>&1; then RUNNER=node
else echo "skip: neither bun nor node installed, the Search ranking was not run"; exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sed '/^\.pragma /d' "$DIR/ranking.js" > "$WORK/ranking.mjs"
printf '\nexport { blend, tierOf, stableIndex, rankRows, translateText, mathWorthShowing };\n' >> "$WORK/ranking.mjs"
sed '/^\.pragma /d' "$DIR/file-format.js" > "$WORK/file-format.mjs"
printf '\nexport { parseStat, formatModified, describe, parentFolder };\n' >> "$WORK/file-format.mjs"

cat > "$WORK/run.mjs" <<'EOF'
import { blend, tierOf, stableIndex, rankRows, translateText, mathWorthShowing } from "./ranking.mjs";
import { parseStat, formatModified, describe, parentFolder } from "./file-format.mjs";

let failed = 0;
const check = (name, got, want) => {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    if (!ok) { console.error(`FAIL: ${name}\n  got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`); failed++; }
};

const row = (key, name, extra = {}) => Object.assign({ key, name, heading: "", scopePrefix: "" }, extra);
const more = (total, prefix, id) => row(`more|${id}`, `Show all ${total}`, { scopePrefix: prefix });
const run = (query, sections, extra = {}) => blend(Object.assign({ query, sections, topTitle: "Top Hit", makeMore: more }, extra));
const view = result => result.rows.map(r => (r.heading ? `[${r.heading}] ` : "") + r.name);

const apps = names => names.map(n => row(`app|${n}`, n));
const section = (id, title, rows, extra = {}) => Object.assign({ id, title, rows, top: false, prefix: "" }, extra);

// tiers, from a name that is the query down to one that merely contains it
check("tier: exact beats prefix beats word beats inside beats fuzzy",
    ["term", "terminal", "my terminal", "xterminal", "tmr"].map(n => tierOf(n, "term")), [100, 90, 80, 70, 50]);
check("tier: regex characters in the query are not special", tierOf("a (b)", "(b"), 80);

// section order and headings
let result = run("set", [
    section("apps", "Applications", apps(["Settings Daemon", "Reset"]), { top: true }),
    section("windows", "Windows", [row("window|1", "Settings - Firefox")], { top: true }),
    section("commands", "Commands and Settings", [row("command|a", "Setup")], { top: true }),
    section("files", "Files", [row("file|/h/set.txt", "set.txt")], { top: true }),
    section("calc", "Calculator", [row("math", "42")]),
    section("clipboard", "Clipboard", [row("clipboard|x", "set the table")]),
], { tail: [row("shell", "set"), row("web", "set")] });
check("order: Top Hit, then each section in the stated order, the tail last", view(result), [
    "[Top Hit] Settings Daemon", "[Applications] Reset", "[Windows] Settings - Firefox",
    "[Commands and Settings] Setup", "[Files] set.txt", "[Calculator] 42", "[Clipboard] set the table", "set", "set"]);
check("order: the Top Hit leaves its section, so the section is not listed twice", view(result).filter(n => n.endsWith("Settings Daemon")).length, 1);

// a section with nothing in it draws no heading
result = run("zz", [section("apps", "Applications", []), section("files", "Files", [row("file|/z", "z.txt")])]);
check("empty sections vanish; a lone file row is under its own heading", view(result), ["[Files] z.txt"]);
result = run("zz", [section("apps", "Applications", apps(["Zed"]), { top: true })]);
check("the one row there is becomes the Top Hit and leaves no empty section", view(result), ["[Top Hit] Zed"]);

// Top Hit: the best match across providers; a tie goes to the earlier section
result = run("dark mode", [
    section("apps", "Applications", apps(["Dark Mode Settings Tool"]), { top: true }),
    section("commands", "Commands and Settings", [row("command|dark", "Dark mode")], { top: true }),
]);
check("top: an exact command beats a prefix-match app", result.topKey, "command|dark");
result = run("term", [
    section("apps", "Applications", apps(["Terminal"]), { top: true }),
    section("commands", "Commands and Settings", [row("command|t", "Terminate session")], { top: true }),
]);
check("top: a tie goes to the application", result.topKey, "app|Terminal");
result = run("42", [
    section("apps", "Applications", apps(["42 Editor"]), { top: true }),
    section("calc", "Calculator", [row("math", "1764", { tier: 100 })], { top: true }),
]);
check("top: a row carrying a tier (the sum) beats a name match", result.topKey, "math");
result = run("hello", [
    section("clipboard", "Clipboard", [row("clipboard|hello", "hello")], { top: true }),
    section("web", "Applications", []),
]);
check("top: only sections that may supply one do", blend({ query: "hello", topTitle: "Top Hit", makeMore: more,
    sections: [section("clipboard", "Clipboard", [row("clipboard|hello", "hello")])] }).topKey, "");

// five rows a section, then "Show all N" into that section's sigil
const eight = apps(["a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8"]);
result = run("a", [section("apps", "Applications", eight, { prefix: ">" })]);
check("cap: five rows and a Show all row counting all eight", view(result), ["[Applications] a1", "a2", "a3", "a4", "a5", "Show all 8"]);
check("cap: the Show all row switches to the section's sigil", result.rows[5].scopePrefix, ">");
result = run("a", [section("apps", "Applications", eight, { prefix: ">", top: true })]);
check("cap: with a Top Hit taken out the count still covers every match",
    [result.rows[0].heading, result.rows.length, result.rows[result.rows.length - 1].name], ["Top Hit", 7, "Show all 8"]);
result = run("a", [section("clipboard", "Clipboard", ["c1", "c2", "c3", "c4", "c5"].map(n => row(`clipboard|${n}`, n)), { cap: 3, prefix: ";" })]);
check("cap: clipboard shows three", view(result), ["[Clipboard] c1", "c2", "c3", "Show all 5"]);
result = run("a", [section("apps", "Applications", eight.slice(0, 5))]);
check("cap: exactly five rows need no Show all", result.rows.length, 5);
result = run("s", [section("commands", "Commands and Settings",
    ["c1", "c2", "c3", "c4", "c5"].map(n => row(`command|${n}`, n)).concat([row("settings|Sound", "Sound", { scopePrefix: "#" })]), { prefix: "/" })]);
check("cap: a hidden row's own sigil wins over the section's", result.rows[5].scopePrefix, "#");

// a row that arrives late cannot take the Top Hit or move the cursor
const early = [section("apps", "Applications", apps(["Notes App"]), { top: true }), section("files", "Files", [], { top: true })];
const first = run("notes", early);
const late = [section("apps", "Applications", apps(["Notes App"]), { top: true }),
    section("files", "Files", [row("file|/h/notes", "notes")], { top: true })];
check("late: unpinned, the exact file name takes the top", run("notes", late).topKey, "file|/h/notes");
check("late: pinned to the Top Hit already shown, it stays", run("notes", late, { pinnedTop: first.topKey }).topKey, "app|Notes App");
check("late: the late file still appears, in its own section", view(run("notes", late, { pinnedTop: first.topKey })), ["[Top Hit] Notes App", "[Files] notes"]);
check("late: a pin from another query's list that is gone changes nothing", run("notes", late, { pinnedTop: "app|Gone" }).topKey, "file|/h/notes");
check("cursor: stays on its row when rows are added above and below",
    stableIndex("file|a", ["x", "y", "file|a", "z"], 0), 2);
check("cursor: row gone, the same index, clamped", stableIndex("gone", ["x", "y"], 5), 1);
check("cursor: no row held, the first", stableIndex("", ["x", "y"], 0), 0);
check("cursor: empty list", stableIndex("k", [], 3), 0);

// ordering inside a merged section
check("rank: the closer name first, the providers' order within a tier",
    rankRows([row("1", "Display"), row("2", "Dark mode"), row("3", "Dark")], "dark").map(r => r.name), ["Dark", "Dark mode", "Display"]);

// translate
check("translate: text after the word", translateText("translate hello world", "translate"), "hello world");
check("translate: the word alone asks for the selection", translateText("Translate", "translate"), "");
check("translate: another word is not it", translateText("translated", "translate"), null);
check("translate: nor is it a prefix of something longer", translateText("translating", "translate"), null);

// calculator
check("math: a sum has a row", mathWorthShowing("2+2", "4"), true);
check("math: qalc echoing a word back does not", mathWorthShowing("term", "term"), false);
check("math: a query without a digit never does", mathWorthShowing("set", "1 s"), false);
check("math: an empty result does not", mathWorthShowing("2+", ""), false);

// file rows: folder and date, from one stat per result set
const labels = { today: "Today", yesterday: "Yesterday" };
const pattern = (date, p) => ({ "HH:mm": `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`,
    "d MMM": `${date.getDate()} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.getMonth()]}`,
    "d MMM yyyy": `${date.getDate()} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.getMonth()]} ${date.getFullYear()}` })[p];
const now = new Date(2026, 9, 10, 15, 30).getTime();
const at = (y, m, d, h = 0, min = 0) => new Date(y, m, d, h, min).getTime();
check("date: today carries the time", formatModified(at(2026, 9, 10, 14, 2), now, pattern, labels), "Today 14:02");
check("date: yesterday carries the time", formatModified(at(2026, 9, 9, 9, 5), now, pattern, labels), "Yesterday 09:05");
check("date: earlier this year is day and month", formatModified(at(2026, 9, 3, 8, 0), now, pattern, labels), "3 Oct");
check("date: another year adds the year", formatModified(at(2025, 9, 3, 8, 0), now, pattern, labels), "3 Oct 2025");
check("date: unknown stays empty", formatModified(0, now, pattern, labels), "");
check("folder: under home it is ~-relative", parentFolder("/home/u/Documents/a.pdf", "/home/u"), "~/Documents");
check("folder: outside home it is absolute", parentFolder("/srv/a.pdf", "/home/u"), "/srv");
check("describe: folder, then date", describe("/home/u/Documents/a.pdf", at(2026, 9, 10, 14, 2), "/home/u", now, pattern, labels), "~/Documents  ·  Today 14:02");
check("describe: no date, just the folder", describe("/home/u/a.pdf", 0, "/home/u", now, pattern, labels), "~");
const stat = parseStat("1791625182\t/home/u/a b.txt\nnot a line\n\t/x\n12\t\n1700000000\t/home/u/c\ttab.md\n");
check("stat: seconds become ms, names are basenames, bad lines are dropped, a tab in a name survives",
    stat, [{ path: "/home/u/a b.txt", name: "a b.txt", modified: 1791625182000 }, { path: "/home/u/c\ttab.md", name: "c\ttab.md", modified: 1700000000000 }]);
check("stat: nothing found is an empty list", parseStat(""), []);

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("search ranking ok");
EOF
"$RUNNER" "$WORK/run.mjs" || fail "the Search ranking checks failed"
echo "ok   ranking: sections in order under headings, a Top Hit across providers, five rows a section with Show all, a late row cannot move the Top Hit or the cursor, file rows read folder and date"
