#!/usr/bin/env bash
# Per-turn tool subsetting. gemma4-e4b drops digits out of its own reply once the
# serialised tool array passes its measured ceiling, so no request may cross it — and
# no tool may become permanently unreachable as a result. Runs the real functions out
# of ToolRegistry.qml, with the `browser` and `desktop` entries it is handed from
# browser-rules.js and desktop-rules.js (Ai.qml passes BrowserTool's and DesktopTool's
# entries in as extraEntries). No network.
#
# Set DUMP_DIR to write each turn's subset out as JSON for the corruption harness.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/ToolRegistry.qml"
REQUESTER="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/Requester.qml"
RANKING="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/toolRanking.js"
BROWSER_RULES="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/browser-rules.js"
DESKTOP_RULES="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/desktop-rules.js"
AI_FACADE="$REPO_ROOT/dots/.config/quickshell/koompi/services/Ai.qml"

[[ -f "$REGISTRY" ]] || { echo "missing $REGISTRY" >&2; exit 1; }
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

fail=0

# The budget reaches every turn, and the turn answering a tool result gets the same
# subset rather than none: a bare answering turn cannot chain get_shell_config into
# set_shell_config.
grep -q 'subsetForTurn(format, limit, root.lastUserText(messages))' "$REQUESTER" \
    || { echo "FAIL: Requester no longer subsets an ordinary turn" >&2; fail=1; }
grep -q 'answeringATool' "$REQUESTER" \
    && { echo "FAIL: the turn answering a tool result is special-cased again" >&2; fail=1; }
# The browser is declared beside its handler and joins the registry here.
grep -q '\].concat(root.extraEntries)' "$REGISTRY" \
    || { echo "FAIL: ToolRegistry no longer adds extraEntries to its entries" >&2; fail=1; }
grep -q 'ToolRegistry { extraEntries: \[root.browserTool.entry, root.desktopTool.entry\] }' "$AI_FACADE" \
    || { echo "FAIL: Ai.qml no longer hands the browser and desktop entries to the registry" >&2; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/run.mjs" <<'EOF'
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const qml = readFileSync(process.argv[2], "utf8");
const ranking = readFileSync(process.argv[3], "utf8").replace(".pragma library", "");
const browserRules = readFileSync(process.argv[4], "utf8");
if (!/^\.pragma library$/m.test(browserRules)) throw new Error("browser-rules.js is not a .pragma library file");
writeFileSync("./browser-rules.mjs", `${browserRules.replace(/^\.pragma library$/m, "")}\nexport { entry, refKey, truthy, partsOf, commitWords, searchLike };\n`);
const desktopRules = readFileSync(process.argv[5], "utf8");
writeFileSync("./desktop-rules.mjs", `import * as Browser from "./browser-rules.mjs";\n${desktopRules
    .replace(/^\.pragma library$/m, "").replace(/^\.import .*$/m, "")}\nexport { entry };\n`);

function liftBlock(header, open, close) {
    const start = qml.indexOf(header);
    if (start < 0) throw new Error(`${header} not found in ToolRegistry.qml`);
    let depth = 0;
    for (let j = qml.indexOf(open, start); j < qml.length; j++) {
        if (qml[j] === open) depth++;
        else if (qml[j] === close && --depth === 0) return qml.slice(qml.indexOf(open, start), j + 1);
    }
    throw new Error(`unbalanced ${open} in ${header}`);
}

function liftFn(name) {
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found in ToolRegistry.qml`);
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}

const FNS = ["activeEntries", "withText", "geminiDeclaration", "openaiDeclaration", "renderDeclaration",
             "wrapDeclarations", "rankedEntries", "subsetForTurn"];

const strip = s => s
    .replace(/function (\w+)\(([^)]*)\): \w+/g, (_, n, a) => `function ${n}(${a})`)
    .replace(/(\w+): (string|int|var|real|bool)\b/g, "$1")
    .replace(/\broot\./g, "");

writeFileSync("./registry.mjs", `import { entry as browserEntry } from "./browser-rules.mjs";
import { entry as desktopEntry } from "./desktop-rules.mjs";
const extraEntries = [browserEntry, desktopEntry];
` + strip(`
const emptyParameters = ${liftBlock("readonly property var emptyParameters:", "(", ")").slice(1, -1)};
const webToolsEnabled = true;
const agentToolEnabled = true;
const toolText = null;
const Ranking = (() => { ${ranking}; return { relevanceScore }; })();
const entries = ${liftBlock("readonly property var entries:", "[", "]")}.concat(extraEntries);
${FNS.map(liftFn).join("\n")}
export { entries, subsetForTurn, rankedEntries, activeEntries, renderDeclaration, wrapDeclarations };
`).replace(/webToolsEnabled/g, "webToolsEnabled").replace(/agentToolEnabled/g, "agentToolEnabled"));

const R = await import("./registry.mjs");

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};

// The limit measured against gemma4-e4b on LiteRT-LM. Must match ModelRegistry.
const LIMIT = 1461;

// One per thing a user actually opens the assistant to do.
const TURNS = {
    "machine":  "what laptop is this, and how much RAM and disk does it have?",
    "web":      "search the web for the KOOMPI Ministation price",
    "page":     "read https://koompi.com/about and summarise it",
    "shell":    "run uptime and tell me the load average",
    "memory":   "remember that I prefer the helix editor",
    "namecall": "my name is Rithy, call me that from now on",
    "config":   "make the bar borderless in the shell config",
    "recall":   "what do you know about my editor preferences?",
    "chat":     "hey, what can you do?",
    "browse":   "open koompi.com in the browser and click the About link",
    "desktop":  "open the Calculator app and press the 7 button",
    "empty":    "",
};

const namesOf = (format, subset) => {
    const list = format === "gemini" ? subset[0].functionDeclarations : subset;
    return list.map(d => format === "gemini" ? d.name : d.function.name);
};

const seen = new Set();
const rows = [];
for (const format of ["openai", "gemini"]) {
    for (const [label, text] of Object.entries(TURNS)) {
        const subset = R.subsetForTurn(format, LIMIT, text);
        const bytes = JSON.stringify(subset).length;
        const names = namesOf(format, subset);
        check(`${format}/${label} stays under the ceiling`, bytes <= LIMIT, `${bytes} > ${LIMIT}`);
        check(`${format}/${label} carries the core tool`, names.includes("recall"), names.join(","));
        check(`${format}/${label} is not empty`, names.length > 0);
        if (format === "openai") {
            names.forEach(n => seen.add(n));
            rows.push({ label, bytes, names });
        }
    }
}

// Nothing may be permanently unreachable: every enabled tool has to be in reach of
// at least one of the turns a user would actually type.
const all = R.activeEntries("openai").map(e => e.name);
const unreachable = all.filter(n => !seen.has(n));
check("every tool is reachable from some turn", unreachable.length === 0, `unreachable: ${unreachable}`);

// The ranking has to be doing real work, not just returning the static prior.
const machine = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.machine));
const web = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.web));
const config = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.config));
check("a machine question reaches the agent", machine.includes("ask_agent"), machine.join(","));
check("a search reaches search_web", web.includes("search_web"), web.join(","));
check("a config change reaches set_shell_config", config.includes("set_shell_config"), config.join(","));
// Short turns with no tool's name in them, which only the hints can route.
for (const [text, tool] of [["How much does the KOOMPI E13 cost?", "search_web"],
                            ["Move my bar to the bottom of the screen.", "set_shell_config"],
                            ["Move my bar to the bottom of the screen.", "get_shell_config"],
                            ["Actually, please call me Sokha from now on.", "set_owner_name"],
                            ["What does https://example.org/pricing say?", "fetch_url"],
                            ["Which graphics card is in this machine?", "ask_agent"],
                            ["Go to koompi.com and click the About link.", "browser"],
                            ["Press ctrl+s in my text editor window.", "desktop"],
                            ["Close the dialog in the Files app.", "desktop"],
                            ["Which windows are open right now?", "desktop"]]) {
    const names = namesOf("openai", R.subsetForTurn("openai", LIMIT, text));
    check(`"${text}" reaches ${tool}`, names.includes(tool), names.join(","));
}
const browse = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.browse));
check("a browsing turn reaches the browser", browse.includes("browser"), browse.join(","));
const browseGemini = namesOf("gemini", R.subsetForTurn("gemini", LIMIT, TURNS.browse));
check("a browsing turn reaches the browser in gemini format", browseGemini.includes("browser"), browseGemini.join(","));
check("the browser is in the registry", all.includes("browser"), all.join(","));
check("the desktop is in the registry", all.includes("desktop"), all.join(","));
const desk = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.desktop));
check("a desktop turn reaches the desktop tool", desk.includes("desktop"), desk.join(","));
const deskGemini = namesOf("gemini", R.subsetForTurn("gemini", LIMIT, TURNS.desktop));
check("a desktop turn reaches the desktop tool in gemini format", deskGemini.includes("desktop"), deskGemini.join(","));
const deskBytes = JSON.stringify(R.renderDeclaration("openai", R.activeEntries("openai").find(e => e.name === "desktop"))).length;
console.log(`desktop declaration, openai-rendered: ${deskBytes} bytes of the ${LIMIT}-byte ceiling`);
check("the subset actually varies by turn", JSON.stringify(machine) !== JSON.stringify(config),
    machine.join(","));

// A model with no measured ceiling is not subsetted at all.
const unlimited = namesOf("openai", R.subsetForTurn("openai", 0, TURNS.chat));
check("budget 0 keeps every tool", unlimited.length === all.length, `${unlimited.length} of ${all.length}`);

// A budget too small for anything must not produce a malformed array.
const starved = R.subsetForTurn("openai", 10, TURNS.chat);
check("an impossible budget yields an empty array", Array.isArray(starved) && starved.length === 0,
    JSON.stringify(starved));

if (process.env.DUMP_DIR) {
    mkdirSync(process.env.DUMP_DIR, { recursive: true });
    for (const [label, text] of Object.entries(TURNS)) {
        writeFileSync(`${process.env.DUMP_DIR}/${label}.json`,
            JSON.stringify(R.subsetForTurn("openai", LIMIT, text)));
    }
    console.log(rows.map(r => `${r.label.padEnd(9)} ${String(r.bytes).padStart(5)}B  ${r.names.join(" ")}`).join("\n"));
}

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok: per-turn tool subsetting");
EOF

cd "$tmp" && DUMP_DIR="${DUMP_DIR:-}" bun run run.mjs "$REGISTRY" "$RANKING" "$BROWSER_RULES" "$DESKTOP_RULES" || fail=1

exit "$fail"
