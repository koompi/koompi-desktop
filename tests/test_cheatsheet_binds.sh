#!/usr/bin/env bash
# The Super+/ cheatsheet speaks keys, once each (audit 3.8): what is printed on
# the key instead of Hyprland's raw name, and one row per action with every chord.
# The parse and merge logic is modules/koompi/cheatsheet/cheatsheet-binds.js, run
# here on the binds the shipped Lua config really declares: the recorder replays
# keybinds.lua, keybinds_shell_extra.lua and custom/keybinds.lua, and each
# declaration becomes one bind the way `hyprctl binds` would list it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
BINDS_JS="$SHELL_ROOT/modules/koompi/cheatsheet/cheatsheet-binds.js"
RECORDER="$SHELL_ROOT/services/hyprlandKeybinds/recorder.lua"
HYPR="$REPO_ROOT/dots/.config/hypr"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$BINDS_JS" ]] || fail "missing ${BINDS_JS#"$REPO_ROOT"/}"
[[ -f "$RECORDER" ]] || fail "missing services/hyprlandKeybinds/recorder.lua"
# Quickshell's JS engine is not bun's: flatMap threw there, which bun cannot show.
if grep -nE '\.(flatMap|flat|at|replaceAll|findLast|toSorted|toReversed)\(|Object\.(hasOwn|fromEntries)' "$BINDS_JS"; then
    fail "cheatsheet-binds.js uses a method the Quickshell JS engine lacks"
fi
if command -v bun > /dev/null 2>&1; then RUNNER=bun
elif command -v node > /dev/null 2>&1; then RUNNER=node
else echo "skip: neither bun nor node installed, cheatsheet-binds.js not run"; exit 0
fi
command -v lua > /dev/null 2>&1 || { echo "skip: lua not installed, no recorder to read the shipped binds with"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

lua "$RECORDER" "$HYPR" hyprland.keybinds hyprland.keybinds_shell_extra hyprland.keybinds_groups custom.keybinds > "$WORK/binds.json" 2> "$WORK/rec.err" \
    || { cat "$WORK/rec.err" >&2; fail "recorder could not replay the shipped keybinds"; }

# QML-flavoured JS: drop the pragma, expose the functions.
sed '/^\.pragma /d' "$BINDS_JS" > "$WORK/binds.mjs"
printf '\nexport { keyLabel, buildRows, keycaps, capRuns };\n' >> "$WORK/binds.mjs"

cat > "$WORK/run.mjs" <<'EOF'
import { keyLabel, buildRows, keycaps, capRuns } from "./binds.mjs";
import fs from "node:fs";

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// HyprlandKeybinds.modifiersOf: the order the sheet prints modifiers in.
const MODS = [[4, "Ctrl"], [64, "Super"], [1, "Shift"], [8, "Alt"], [2, "Caps"], [16, "Mod2"], [32, "Mod3"], [128, "Mod5"]];
const records = JSON.parse(fs.readFileSync(`${process.env.WORK}/binds.json`, "utf8"));
const shipped = records.map((r, id) => ({
    id, key: r.key, description: r.description, dispatchable: r.expr !== null,
    mods: MODS.filter(([bit]) => r.modmask & bit).map(([, name]) => name),
}));
const categories = [...new Set(shipped.map(b => b.description.indexOf(":") < 0 ? "" : b.description.split(":")[0]))];
const rowsOf = category => buildRows(shipped, category, {});
const row = (category, text) => rowsOf(category).find(r => r.text === text);
const show = chord => [...chord.mods, chord.key].filter(part => part !== "").join(" + ");
const chordsOf = (category, text) => (row(category, text)?.chords ?? []).map(show);

// 1. what is printed on the key
const printed = {
    grave: "`", Grave: "`", backslash: "\\", Backslash: "\\", Slash: "/", Semicolon: ";", Apostrophe: "'",
    Comma: ",", Period: ".", Minus: "-", Equal: "=", BracketLeft: "[", BracketRight: "]",
    Page_Up: "PgUp", Page_Down: "PgDn", Left: "←", Right: "→", Up: "↑", Down: "↓",
    Return: "Enter", Escape: "Esc", Print: "PrtSc", Delete: "Del",
    "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
    "mouse:275": "Back", "mouse:276": "Forward", mouse_up: "Scroll ↑", mouse_down: "Scroll ↓",
    "code:201": "AI", SUPER_L: "", W: "W", F1: "F1", "1": "1",
};
for (const [raw, want] of Object.entries(printed))
    check(`key ${raw}`, keyLabel(raw) === want, `got ${JSON.stringify(keyLabel(raw))}`);
check("an unknown key renders as itself", keyLabel("XF86Unmapped") === "XF86Unmapped" && keyLabel("code:99") === "code:99");
check("object keys are not key names", keyLabel("constructor") === "constructor" && keyLabel("toString") === "toString");
check("an override wins over the table, whatever its case", keyLabel("Return", { return: "⏎" }) === "⏎" && keyLabel("Super", { Super: "S" }) === "S");

// 2. nothing the shipped config declares reaches the sheet as a raw name or a template
const raw = /^(grave|backslash|slash|semicolon|apostrophe|comma|period|minus|equal|bracket\w+|page_\w+|mouse[:_]\S+|xf86\w+|code:\d+|\w*<\w+>\w*)$/i;
for (const category of categories) {
    const rows = rowsOf(category);
    const texts = rows.map(r => r.text);
    check(`${category || "uncategorized"}: one row per description`, new Set(texts).size === texts.length,
          texts.filter((t, i) => texts.indexOf(t) !== i).join(", "));
    for (const r of rows) {
        check(`${r.text}: no template in the text`, !/<(Number|Direction)>/.test(r.text), r.text);
        for (const chord of r.chords) {
            check(`${r.text}: key ${chord.key} is not a raw name`, !raw.test(chord.key));
            check(`${r.text}: a chord is something to press`, chord.mods.length + chord.key.length > 0);
        }
    }
}

// 3. the rows the audit named
check("Window Move: both mouse buttons in one row", same(chordsOf("Window", "Move"), ["Super + Left click", "Super + Middle click"]), JSON.stringify(chordsOf("Window", "Move")));
check("Window: Send to workspace left is one row of three", chordsOf("Window", "Send to workspace left").length === 3);
check("Window: Send to workspace right is one row of three", chordsOf("Window", "Send to workspace right").length === 3);
check("Window: the ten send-to-workspace chords are one range", same(chordsOf("Window", "Send to workspace 1–10"), ["Super + Alt + 1–0"]), JSON.stringify(chordsOf("Window", "Send to workspace 1–10")));
check("Window: focus is one row, arrows then brackets", same(chordsOf("Window", "Focus left/right/up/down"), ["Super + ←→↑↓", "Super + [ ]"]), JSON.stringify(chordsOf("Window", "Focus left/right/up/down")));
check("Window: move is one row of arrows", same(chordsOf("Window", "Move left/right/up/down"), ["Super + Shift + ←→↑↓"]), JSON.stringify(chordsOf("Window", "Move left/right/up/down")));
check("Window: punctuation keys", same(chordsOf("Window", "Shrink split ratio"), ["Super + ;"]) && same(chordsOf("Window", "Grow split ratio"), ["Super + '"]));
check("Window: Resize to 640x480 is not read as a family", same(chordsOf("Window", "Resize to 640x480"), ["Super + Ctrl + \\"]));
check("Utilities: Record region (no sound) once, two chords", same(chordsOf("Utilities", "Record region (no sound)"), ["Super + Shift + R", "Super + Alt + R"]), JSON.stringify(chordsOf("Utilities", "Record region (no sound)")));
check("App: Terminal once, simplest chord first", same(chordsOf("App", "Terminal"), ["Super + Enter", "Super + T", "Ctrl + Alt + T"]), JSON.stringify(chordsOf("App", "Terminal")));
check("Scratchpad: the backtick and backslash widgets", same(chordsOf("Scratchpad", "Terminal"), ["Super + `"]) && same(chordsOf("Scratchpad", "System monitor"), ["Super + \\"]));
check("Media: Next track once, the media key first", same(chordsOf("Media", "Next track"), ["Next", "Super + Shift + N", "Super + Alt + Shift + Forward"]), JSON.stringify(chordsOf("Media", "Next track")));
check("Workspace: Focus 1–10 on Super+1–0", same(chordsOf("Workspace", "Focus 1–10"), ["Super + 1–0"]));
// the wheel reads as it turns: wherever a row pairs it with PgUp/PgDn, up goes with up
for (const category of categories) {
    for (const r of rowsOf(category)) {
        const keys = r.chords.map(chord => chord.key);
        if (!keys.some(key => key.startsWith("Scroll")) || !keys.some(key => key.startsWith("Pg"))) continue;
        check(`${category}: ${r.text}: the wheel goes the way the page keys do`,
            keys.includes("Scroll ↑") === keys.includes("PgUp") && keys.includes("Scroll ↓") === keys.includes("PgDn"), keys.join(" | "));
    }
}
check("Workspace: Focus left keeps the arrow beside page and scroll keys", chordsOf("Workspace", "Focus left").includes("Super + Ctrl + ←") && chordsOf("Workspace", "Focus left").includes("Super + PgUp"));
check("Shell: the nine bar popups are one row", same(chordsOf("Shell", "Bar popup 1–9 (1 agent usage, 2 battery, 3 pomodoro, 4 clock)"), ["Super + Ctrl + 1–9"]));
check("Shell: Toggle search is Super alone", same(chordsOf("Shell", "Toggle search"), ["Super"]));
check("Kiri: the AI key alone", same(chordsOf("Kiri", "Voice transcription"), ["AI"]), JSON.stringify(chordsOf("Kiri", "Voice transcription")));
check("Kiri: the two Khmer dictation binds are one row, the AI key with Alt first", same(chordsOf("Kiri", "Khmer dictation"), ["Alt + AI", "Super + Shift + K"]), JSON.stringify(chordsOf("Kiri", "Khmer dictation")));
check("Kiri: Cancel dictation", same(chordsOf("Kiri", "Cancel dictation"), ["Super + Esc"]), JSON.stringify(chordsOf("Kiri", "Cancel dictation")));
check("Media: the XF86 volume key is on the sheet", same(chordsOf("Media", "Volume up"), ["Vol +"]));

// 4. the merge on small inputs
const bind = (id, description, key, mods, dispatchable = true) => ({ id, description, key, mods, dispatchable });
const rows = binds => buildRows(binds, "C", {});
check("a family needs every member to be the one its key names",
    same(rows([bind(0, "C: Go left", "Left", ["Super"]), bind(1, "C: Go right", "Right", ["Super"]), bind(2, "C: Go left", "Page_Up", ["Super"])]).map(r => [r.text, r.chords.map(show)]),
         [["Go left", ["Super + ←", "Super + PgUp"]], ["Go right", ["Super + →"]]]));
check("a lone direction is not a family", same(rows([bind(0, "C: Go left", "Left", ["Super"])]).map(r => r.text), ["Go left"]));
check("the same chord twice is one chord, both ids kept", (() => {
    const r = rows([bind(0, "C: Open", "O", ["Super"]), bind(1, "C: Open", "O", ["Super"])]);
    return r.length === 1 && r[0].chords.length === 1 && same(r[0].ids, [0, 1]);
})());
check("a duplicate chord still lends its bind to run", rows([bind(0, "C: Open", "O", ["Super"], false), bind(1, "C: Open", "O", ["Super"])])[0].runId === 1);
check("fewest modifiers first, declared order within a count", same(
    rows([bind(0, "C: Open", "A", ["Ctrl", "Alt"]), bind(1, "C: Open", "B", []), bind(2, "C: Open", "C", ["Super"]), bind(3, "C: Open", "D", ["Super"])])[0].chords.map(show),
    ["B", "Super + C", "Super + D", "Ctrl + Alt + A"]));
check("a row runs its simplest dispatchable chord", (() => {
    const r = rows([bind(0, "C: Open", "A", [], false), bind(1, "C: Open", "B", ["Super"]), bind(2, "C: Open", "C", ["Ctrl", "Alt"])]);
    return r[0].runId === 1;
})());
check("a row with nothing to run says so", rows([bind(0, "C: Open", "A", [], false)])[0].runId === -1);
check("numbers that are not the key's number stay separate", same(
    rows([bind(0, "C: Jump 5", "1", ["Super"]), bind(1, "C: Jump 5", "2", ["Super"])]).map(r => [r.text, r.chords.map(show)]),
    [["Jump 5", ["Super + 1", "Super + 2"]]]));
check("the category picks the rows, and '' picks the uncategorised", (() => {
    const binds = [bind(0, "C: In", "A", []), bind(1, "D: Out", "B", []), bind(2, "Bare", "C", []), bind(3, "", "D", [])];
    return same(buildRows(binds, "C", {}).map(r => r.text), ["In"]) && same(buildRows(binds, "", {}).map(r => r.text), ["Bare"]);
})());
check("overrides label modifiers too", same(buildRows([bind(0, "C: Open", "O", ["Super"])], "C", { Super: "S" })[0].chords[0].mods, ["S"]));

// 5. keycaps: the star never shares a cap with letters, the font has none
const star = "\u{100000}";
check("text modifiers share a keycap", same(keycaps(["Ctrl", "Shift"], false), ["Ctrl Shift"]));
check("the star leads", same(keycaps([star, "Shift", "Alt"], false), [star, "Shift Alt"]));
check("the star trails", same(keycaps(["Ctrl", star], false), ["Ctrl", star]));
check("the star in the middle", same(keycaps(["Ctrl", star, "Shift"], false), ["Ctrl", star, "Shift"]));
check("split buttons are one cap each", same(keycaps(["Ctrl", star, "Shift"], true), ["Ctrl", star, "Shift"]));
check("no modifiers, no keycaps", same(keycaps([], false), []));

check("the star keeps the cap after it when a chord wraps", same(capRuns([star, "Ctrl", "Alt"], false), [[star, "Ctrl Alt"]])
    && same(capRuns([star], false), [[star]]) && same(capRuns(["Ctrl", "Alt"], false), [["Ctrl Alt"]]) && same(capRuns([], false), []));
check("with one cap each the star still keeps the next one", same(capRuns([star, "Ctrl", "Alt", "Shift"], true), [[star, "Ctrl"], ["Alt"], ["Shift"]]));

// 6. one modifier order on every chord: Super (the star) first, then Ctrl, Alt, Shift,
// whatever order the bind was typed in or the service lists them in
const typed = (...mods) => buildRows([bind(0, "C: Open", "T", mods)], "C", { Super: star })[0].chords[0].mods;
const ordered = [star, "Ctrl", "Alt", "Shift"];
check("a bind typed CTRL SUPER ALT and one typed SUPER ALT CTRL give the same caps",
    same(typed("Ctrl", "Super", "Alt"), [star, "Ctrl", "Alt"]) && same(typed("Super", "Alt", "Ctrl"), [star, "Ctrl", "Alt"]),
    JSON.stringify([typed("Ctrl", "Super", "Alt"), typed("Super", "Alt", "Ctrl")]));
check("all four modifiers, from any order", same(typed("Shift", "Alt", "Ctrl", "Super"), ordered) && same(typed("Alt", "Shift", "Super", "Ctrl"), ordered));
check("the same chord typed two ways is one chord", (() => {
    const r = rows([bind(0, "C: Open", "O", ["Ctrl", "Super"]), bind(1, "C: Open", "O", ["Super", "Ctrl"])]);
    return r[0].chords.length === 1 && same(r[0].ids, [0, 1]);
})());
check("an unknown modifier keeps its place after the known ones", same(typed("Hyper", "Shift", "Super"), [star, "Shift", "Hyper"]));
check("the keycaps of an ordered chord, joined", same(keycaps(typed("Shift", "Ctrl", "Super", "Alt"), false), [star, "Ctrl Alt Shift"]));
check("the keycaps of an ordered chord, one each", same(keycaps(typed("Shift", "Ctrl", "Super", "Alt"), true), ordered));
{
    const wrong = [];
    for (const category of categories)
        for (const r of buildRows(shipped, category, { Super: star }))
            for (const chord of r.chords) {
                const place = chord.mods.map(mod => ordered.indexOf(mod));
                if (place.includes(-1) || place.some((at, i) => i > 0 && at < place[i - 1]))
                    wrong.push(`${r.text}: ${chord.mods.join(" ")}`);
            }
    check("no shipped chord has the star after another modifier or the modifiers out of order", wrong.length === 0, wrong.slice(0, 6).join("; "));
}

// 7. `/` is a key of its own, so no cap uses it to join keys
check("keys that share a cap are told apart by a space, not a slash", same(
    rows([bind(0, "C: Go 1", "1", ["Super"]), bind(1, "C: Go 2", "2", ["Super"]), bind(2, "C: Go 4", "4", ["Super"])]).map(r => [r.text, r.chords.map(show)]),
    [["Go 1/2/4", ["Super + 1 2 4"]]]));
{
    const joined = [];
    for (const category of categories)
        for (const r of rowsOf(category))
            for (const chord of r.chords)
                if (chord.key.length > 1 && chord.key.includes("/")) joined.push(`${r.text}: ${chord.key}`);
    check("no shipped chord joins keys with a slash", joined.length === 0, joined.join("; "));
}

// 8. the AI key sends Super and Shift itself, so a chord on it shows only what is added
{
    const ai = (...mods) => buildRows([bind(0, "C: Dictate", "code:201", mods)], "C", { Super: star })[0].chords[0].mods;
    check("the AI key shows neither the Super nor the Shift it sends", same(ai("Super", "Shift"), []) && same(ai("Shift", "Super"), []), JSON.stringify(ai("Super", "Shift")));
    check("the AI key keeps what is added to it", same(ai("Super", "Shift", "Alt"), ["Alt"]) && same(ai("Ctrl", "Super", "Shift"), ["Ctrl"]) && same(ai("Super", "Shift", "Ctrl", "Alt"), ["Ctrl", "Alt"]));
    check("each of the two goes whether or not the other is there", same(ai("Super"), []) && same(ai("Shift"), []) && same(ai("Shift", "Alt"), ["Alt"]));
    check("the key is matched as Hyprland spells it, in any case", same(buildRows([bind(0, "C: Dictate", "CODE:201", ["Super", "Shift"])], "C", {})[0].chords[0].mods, []));
    const others = buildRows([bind(0, "C: Open", "K", ["Super", "Shift"]), bind(1, "C: Close", "code:202", ["Super", "Shift"])], "C", { Super: star }).map(r => r.chords[0].mods);
    check("every other key keeps its modifiers", same(others, [[star, "Shift"], [star, "Shift"]]), JSON.stringify(others));
    const stray = [];
    for (const category of categories)
        for (const r of buildRows(shipped, category, { Super: star }))
            for (const chord of r.chords)
                if (chord.key === "AI" && chord.mods.some(mod => mod === star || mod === "Shift")) stray.push(`${r.text}: ${chord.mods.join(" ")} AI`);
    check("no shipped AI-key chord shows the Super or Shift it sends", stray.length === 0, stray.join("; "));
}

// 9. descriptions in words, every one in a group
{
    const shorthand = shipped.filter(b => /^Utilities:/.test(b.description) && /(>>|&|\s\+\s)/.test(b.description)).map(b => b.description);
    check("no Utilities description uses >>, & or + as shorthand", shorthand.length === 0, shorthand.join("; "));
    const ungrouped = rowsOf("").map(r => r.text);
    check("every shipped bind that is described has a group", ungrouped.length === 0, ungrouped.join("; "));
    const zap = shipped.filter(b => /zap/i.test(b.description)).map(b => b.description);
    check("no description says zap", zap.length === 0, zap.join("; "));
    const naming = shipped.filter(b => /\((AI key|Super|Alt|Ctrl|Shift)/.test(b.description)).map(b => b.description);
    check("no description names its own keys in brackets", naming.length === 0, naming.join("; "));
}
check("Print and Super+Shift+S are one row, they open the same snip", same(chordsOf("Utilities", "Screen snip"), ["PrtSc", "Super + Shift + S"]), JSON.stringify(chordsOf("Utilities", "Screen snip")));
check("the two whole-screen screenshots differ in the notification", chordsOf("Utilities", "Screenshot the whole screen, save and copy it, with a notification").join() === "Shift + PrtSc"
    && chordsOf("Utilities", "Screenshot the whole screen, save and copy it, silently").join() === "Ctrl + PrtSc");
check("Window opens with the tiling moves, in the order a newcomer needs them", same(rowsOf("Window").slice(0, 8).map(r => r.text), [
    "Focus left/right/up/down", "Move left/right/up/down", "Send to workspace 1–10", "Back to the previous window",
    "Next window on this workspace", "Float/Tile", "Fullscreen", "Close"]), JSON.stringify(rowsOf("Window").slice(0, 8).map(r => r.text)));
check("Window: Resize is the next row after the moves", rowsOf("Window").map(r => r.text).indexOf("Resize") === 9);
check("Force quit is one row", same(chordsOf("Window", "Force quit"), ["Super + Alt + Shift + Q"]), JSON.stringify(chordsOf("Window", "Force quit")));

if (failed > 0) { console.error(`${failed} cheatsheet-binds check(s) failed`); process.exit(1); }
console.log(`cheatsheet-binds: ${categories.length} categories, ${shipped.filter(b => b.description).length} described binds, all checks pass`);
EOF

out="$(cd "$WORK" && WORK="$WORK" "$RUNNER" run.mjs 2>&1)" || { printf '%s\n' "$out" >&2; fail "cheatsheet-binds.js"; }
printf 'ok   %s\n' "$out"
