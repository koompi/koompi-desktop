.pragma library
.import "browser-rules.js" as Browser

// The pure rules of desktop control (M6): the `desktop` tool's declaration and which
// steps wait for the user. Taint lives in browser-rules.js, whose taintingTools names
// `desktop` too. No QML type is reachable from here: tests/test_ai_desktop_rules.sh
// runs these under bun. DesktopTool.qml imports this as `Rules`.

var ops = ["windows", "tree", "see", "focus", "launch", "act", "type", "key", "close"];

// One tool with an `op`, compact for the same reason as the browser's: gemma4-e4b
// gets only as many declarations per turn as fit 1461 bytes.
var entry = {
    "name": "desktop",
    "priority": 50,
    "risk": "writes-system",
    // most steps run at once; the steps askReason() names wait for the user every time
    "approval": "never",
    "hints": "app apps application program window windows desktop launch start focus switch press type key shortcut dialog menu screen screenshot see look click icon",
    "description": "Use the apps on screen: list windows, read a window's controls or see it with numbered marks, press a button, type into a field, press keys, open an app. Act on the [ref] numbers.",
    "parameters": {
        "type": "object",
        "properties": {
            "op": { "type": "string", "enum": ops },
            "ref": { "type": "integer", "description": "from windows, tree or see" },
            "app": { "type": "string", "description": "for launch" },
            "action": { "type": "string", "enum": ["press", "toggle", "activate", "expand"] },
            "text": { "type": "string", "description": "for type" },
            "submit": { "type": "boolean", "description": "press Enter after type" },
            "keys": { "type": "string", "description": "Escape, ctrl+s" }
        },
        "required": ["op"]
    },
    "formats": ["gemini", "openai", "mistral"],
    "enabled": true
};

// The request the driver gets: only its own fields, each in the type it reads.
function requestOf(args) {
    const a = args ?? {};
    const req = { "op": String(a.op ?? "").trim().toLowerCase() };
    if (a.ref !== undefined) req.ref = Browser.refKey(a.ref);
    if (a.app !== undefined) req.app = String(a.app);
    if (a.action !== undefined) req.action = String(a.action).trim().toLowerCase();
    if (a.text !== undefined) req.text = String(a.text);
    if (a.submit !== undefined) req.submit = Browser.truthy(a.submit);
    // a small model writes `key` as the browser tool spells it
    if (a.keys !== undefined || a.key !== undefined) req.keys = String(a.keys ?? a.key);
    if (a.budget !== undefined) req.budget = a.budget;
    return req;
}

// `ctrl+s` -> { mods: ["ctrl"], key: "s" }; spaces and case do not matter.
function keysOf(keys) {
    const parts = String(keys ?? "").toLowerCase().split("+").map(p => p.trim()).filter(p => p.length > 0);
    return { "mods": parts.slice(0, -1), "key": parts.length > 0 ? parts[parts.length - 1] : "" };
}

// A mark `see` found in the pixels of an app with no accessibility tree: the driver names it
// `region at x,y`, and nothing says what a click there presses.
function isRegion(args, refs) {
    const req = requestOf(args);
    return req.op === "act" && /^region at /.test(String((refs ?? {})[Browser.refKey(req.ref)] ?? ""));
}

// What a desktop dialog commits with that a web page rarely says: the buttons that
// throw work away, change the system or end the session.
var desktopCommitWords = /\b(discard|don'?t save|overwrite|replace|uninstall|install|update|upgrade|format|erase|wipe|empty|trash|restart|reboot|shut ?down|power off|log ?out|sign out|quit|reset|restore|revert|allow|grant|trust|yes|ok)\b/i;

/**
 * Why this step waits for the user, or "" when it runs at once. The rule:
 * - launch: always; a desktop entry runs a command line, and some entries are actions
 *   (log out, reset, uninstall).
 * - act: a ref not in the last windows, tree or see reply; a mark found only in the pixels
 *   (a click there may press anything: the card shows the screenshot); a control whose name carries a
 *   commit word (buy, send, delete, save, ... as in the browser, plus discard,
 *   overwrite, uninstall, restart, log out, allow, yes, ok, ... above); a dialog's
 *   default button, which is what Enter would press.
 * - type: a ref not in the last reply; with submit, unless the field is a search field.
 * - key: any shortcut with a modifier (ctrl+w closes, ctrl+s saves, alt+F4 quits);
 *   Enter, Return, Space and Delete, which act on whatever has focus.
 * Everything else (windows, tree, see, focus, typing without submit, Escape, Tab, arrows)
 * runs; whether a screenshot may go to the model is screen-rules.js's gate, not this. The driver refuses what must never happen whatever is answered here.
 */
function askReason(args, refs) {
    const req = requestOf(args);
    const line = (refs ?? {})[Browser.refKey(req.ref)];
    const parts = Browser.partsOf(line);
    if (req.op === "launch") return "it starts a program";
    if (req.op === "act" || req.op === "type") {
        if (line === undefined) return "its target is not in the last tree";
    }
    if (req.op === "act") {
        if (isRegion(req, refs)) return "a click by pixels: nothing tells what it presses";
        if (Browser.commitWords.test(parts.name)) return "it may send, save, buy or delete";
        if (desktopCommitWords.test(parts.name)) return "it may discard work, change the system or end the session";
        if (/\bdefault\b/.test(parts.states)) return "it is the dialog's default button";
    }
    if (req.op === "type" && req.submit === true && !Browser.searchLike(parts)) return "it submits what was typed";
    if (req.op === "key") {
        const k = keysOf(req.keys);
        if (k.mods.length > 0) return "a shortcut can close, save or send";
        if (/^(enter|return|kpenter|space|delete|del)$/.test(k.key.replace(/[\s_]/g, ""))) return "the key acts on whatever has focus";
    }
    return "";
}

// What the approval card shows: the step in words, with the ref as the driver named it.
function describe(args, refs, windowTitle) {
    const req = requestOf(args);
    const line = (refs ?? {})[Browser.refKey(req.ref)];
    const target = req.ref !== undefined ? `[${req.ref}] ${line ?? "(not in the last tree)"}` : "";
    const where = windowTitle ? ` in "${windowTitle}"` : "";
    switch (req.op) {
    case "launch": return `open the app ${JSON.stringify(req.app ?? "")}`;
    case "act": return `${req.action || (isRegion(req, refs) ? "click" : "press")} ${target}${where}`;
    case "type": return `type ${JSON.stringify(req.text ?? "")} into ${target}${where}${req.submit ? ", then press Enter" : ""}`;
    case "key": return `press ${req.keys ?? ""}${req.ref !== undefined ? " in " + target : where}`;
    case "focus": case "tree": return `${req.op} ${target}`.trim();
    case "see": return `look at ${req.ref !== undefined ? target : (windowTitle ? `"${windowTitle}"` : "the focused window")}`;
    default: return req.op;
    }
}
