#!/usr/bin/env bash
# The tour teaches the tiling moves by keyboard, and every chord it shows is a
# bind the shipped Lua config really declares (steps.js says keys must match
# `hyprctl binds`; nothing checked it).
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$ROOT/dots/.config/quickshell/koompi"
STEPS="$SHELL_ROOT/modules/koompi/tour/steps.js"
BINDS_JS="$SHELL_ROOT/modules/koompi/cheatsheet/cheatsheet-binds.js"
RECORDER="$SHELL_ROOT/services/hyprlandKeybinds/recorder.lua"
HYPR="$ROOT/dots/.config/hypr"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

if command -v bun > /dev/null 2>&1; then RUNNER=bun
elif command -v node > /dev/null 2>&1; then RUNNER=node
else echo "skip: neither bun nor node installed"; exit 0
fi
command -v lua > /dev/null 2>&1 || { echo "skip: lua not installed"; exit 0; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
lua "$RECORDER" "$HYPR" hyprland.keybinds hyprland.keybinds_shell_extra custom.keybinds > "$WORK/binds.json" 2> "$WORK/rec.err" \
    || { cat "$WORK/rec.err" >&2; fail "recorder could not replay the shipped keybinds"; }
sed '/^\.pragma /d' "$BINDS_JS" > "$WORK/binds.mjs"
printf '\nexport { keyLabel };\n' >> "$WORK/binds.mjs"
sed '/^\.pragma /d' "$STEPS" > "$WORK/steps.mjs"
printf '\nexport { steps };\n' >> "$WORK/steps.mjs"

cat > "$WORK/run.mjs" <<'JS'
import { keyLabel } from "./binds.mjs";
import { steps } from "./steps.mjs";
import fs from "node:fs";

let failed = 0;
const check = (name, cond, extra = "") => { if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; } };

const MODS = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]];
const records = JSON.parse(fs.readFileSync(`${process.env.WORK}/binds.json`, "utf8"));
const bound = new Set(records.map(r => [...MODS.filter(([bit]) => r.modmask & bit).map(([, n]) => n), keyLabel(r.key)].join("+")));
const caps = { "Page Down": "PgDn", "Page Up": "PgUp", Delete: "Del" };

const expand = key => key === "←→↑↓" ? ["←", "→", "↑", "↓"] : key === "1–0" ? [..."1234567890"] : [caps[key] ?? key];
const chordsOf = keys => {
    const mods = keys.filter(k => ["Super", "Ctrl", "Alt", "Shift"].includes(k));
    const rest = keys.filter(k => !mods.includes(k));
    return expand(rest[0] ?? "").map(k => [...MODS.map(([, n]) => n).filter(n => mods.includes(n)), k].join("+"));
};

for (const step of steps.filter(s => s.keys.length > 0))
    for (const chord of chordsOf(step.keys))
        check(`"${step.title}": ${chord} is bound`, bound.has(chord));

const shown = steps.map(s => chordsOf(s.keys)[0]);
const at = chord => shown.indexOf(chord);
check("a step teaches focus by Super+arrows", at("Super+←") >= 0);
check("a step teaches sending a window to a desk by Super+Alt+number", at("Super+Alt+1") >= 0);
check("a step teaches Alt+Tab", at("Alt+Tab") >= 0);
check("focus comes before send, send before Alt+Tab", at("Super+←") < at("Super+Alt+1") && at("Super+Alt+1") < at("Alt+Tab"));
const focus = steps[at("Super+←")] ?? { body: "" };
check("the focus step names Shift as the way to move the window", /Shift/.test(focus.body) && /Super/.test(focus.body));
check("the focus step says the mouse still works", /mouse still works/i.test(focus.body) && /drag/i.test(focus.body));
check("no step leads with a mouse-only chord", !steps.some(s => s.keys.includes("drag")));
check("Shift+arrows (move) is bound", ["←", "→", "↑", "↓"].every(k => bound.has(`Super+Shift+${k}`)));

if (failed > 0) { console.error(`${failed} tour key check(s) failed`); process.exit(1); }
console.log("tour keys: every shown chord is bound, tiling moves taught by keyboard");
JS
out="$(cd "$WORK" && WORK="$WORK" "$RUNNER" run.mjs 2>&1)" || { printf '%s\n' "$out" >&2; fail "tour keys"; }
printf 'ok   %s\n' "$out"
