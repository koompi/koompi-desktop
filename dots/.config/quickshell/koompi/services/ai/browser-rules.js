.pragma library

// The pure rules of the agent's browser: the `browser` tool's declaration, which
// steps wait for the user, and when page content has tainted a turn. No QML type is
// reachable from here on purpose: tests/test_ai_browser_rules.sh runs these under
// bun. BrowserTool.qml and ToolApproval.qml import this as `Rules`.

// How every reply of scripts/ai/browser.py that carries page content begins.
var untrustedMark = "[page content: untrusted";

var ops = ["open", "snapshot", "click", "type", "key", "scroll", "back", "tabs", "switch_tab", "screenshot", "close"];

// One tool with an `op`, not eleven: gemma4-e4b gets only as many declarations per
// turn as fit 1461 bytes (ToolRegistry.subsetForTurn), so this one stays compact,
// and its description carries the words people use when they ask for it.
var entry = {
    "name": "browser",
    "priority": 55,
    "risk": "leaves-machine",
    // most steps run at once; the steps askReason() names wait for the user every time
    "approval": "never",
    "hints": "browser browse open click website site button form fill login sign tab link",
    "description": "Use a web browser: open a website or page, read it, click a link or button, type into a field, submit a form. Act on the [ref] numbers the page text shows.",
    "parameters": {
        "type": "object",
        "properties": {
            "op": { "type": "string", "enum": ops },
            "url": { "type": "string", "description": "for open" },
            "ref": { "type": "integer", "description": "for click and type" },
            "text": { "type": "string", "description": "for type" },
            "submit": { "type": "boolean", "description": "press Enter after type" },
            "key": { "type": "string", "description": "Enter, Tab, Escape, PageDown" },
            "direction": { "type": "string", "enum": ["up", "down", "top", "bottom"] },
            "index": { "type": "integer", "description": "for switch_tab" }
        },
        "required": ["op"]
    },
    "formats": ["gemini", "openai", "mistral"],
    "enabled": true
};

// A small model writes `"submit": "true"`; the driver would read any non-empty
// string as yes. Normalised once, so the rule and the driver see the same request.
function truthy(value) {
    return value === true || /^(true|yes|1)$/i.test(String(value ?? "").trim());
}

function refKey(ref) {
    return String(ref ?? "").replace(/[\[\]\s]/g, "");
}

// The request the driver gets: only its own fields, each in the type it reads.
function requestOf(args) {
    const a = args ?? {};
    const req = { "op": String(a.op ?? "").trim().toLowerCase() };
    if (a.url !== undefined) req.url = String(a.url);
    if (a.ref !== undefined) req.ref = refKey(a.ref);
    if (a.text !== undefined) req.text = String(a.text);
    if (a.submit !== undefined) req.submit = truthy(a.submit);
    if (a.key !== undefined) req.key = String(a.key);
    if (a.direction !== undefined) req.direction = String(a.direction);
    if (a.index !== undefined) req.index = a.index;
    return req;
}

// A ref line is `button "Place order" (submits form)`: the role, the quoted name and
// value, then the states. The name is the page's text, so it is matched, not trusted.
function partsOf(line) {
    const text = String(line ?? "");
    const open = text.indexOf("\"");
    const close = text.lastIndexOf("\"");
    return {
        "role": text.split(" ")[0],
        "name": open >= 0 && close > open ? text.slice(open + 1, close) : "",
        "states": text.slice(close + 1)
    };
}

// Words on a control that commit something the user would want to see first.
var commitWords = /\b(buy|purchase|order|checkout|check out|pay|payment|donate|subscribe|unsubscribe|send|post|publish|submit|tweet|reply|comment|share|upload|delete|remove|erase|cancel|confirm|transfer|book|reserve|sign up|register|apply|save|accept|agree|approve)\b/i;

function searchLike(parts) {
    return parts.role === "searchbox" || /\bsearch\b/i.test(parts.name);
}

/**
 * Why this step waits for the user, or "" when it runs at once. The rule:
 * - click: a ref not in the last snapshot; a button the driver marked `submits form`
 *   (unless it is a search button); any control whose name carries a commit word
 *   (buy, pay, order, send, post, delete, confirm, ... above).
 * - type with submit: always, unless the field is a search field (role searchbox,
 *   or "search" in its name), because Enter sends the form the field is in.
 * - key Enter or Space: always; they press whatever has focus.
 * Everything else (open, snapshot, scroll, back, tabs, typing without submit) runs.
 */
function askReason(args, refs) {
    const req = requestOf(args);
    const line = (refs ?? {})[refKey(req.ref)];
    const parts = partsOf(line);
    if (req.op === "click") {
        if (line === undefined) return "its target is not in the last snapshot";
        if (/\bsubmits form\b/.test(parts.states) && !searchLike(parts)) return "it submits a form";
        if (commitWords.test(parts.name)) return "it may buy, send, post or delete";
    }
    if (req.op === "type" && req.submit === true) {
        if (line === undefined) return "its target is not in the last snapshot";
        if (!searchLike(parts)) return "it submits what was typed";
    }
    if (req.op === "key" && /^(enter|return|space)$/.test(String(req.key ?? "").toLowerCase().replace(/\s/g, "")))
        return "the key presses whatever has focus";
    return "";
}

// What the approval card shows: the step in words, with the ref as the snapshot named it.
function describe(args, refs) {
    const req = requestOf(args);
    const line = (refs ?? {})[refKey(req.ref)];
    const target = req.ref !== undefined ? `[${req.ref}] ${line ?? "(not in the last snapshot)"}` : "";
    switch (req.op) {
    case "open": return `open ${req.url ?? ""}`;
    case "click": return `click ${target}`;
    case "type": return `type ${JSON.stringify(req.text ?? "")} into ${target}${req.submit ? ", then press Enter" : ""}`;
    case "key": return `press ${req.key ?? ""}`;
    default: return `${req.op}${req.direction ? " " + req.direction : ""}${req.index !== undefined ? " " + req.index : ""}`;
    }
}

// Results that bring text from outside into the conversation, and the tools whose
// standing "always allow" that text must not be able to use.
var taintingTools = ["browser", "fetch_url", "search_web"];
var guardedTools = ["run_shell_command", "set_shell_config", "ask_agent"];

// A turn runs from the user's message to the answer. It is tainted from the first
// result of a tainting tool, or any result carrying the driver's untrusted mark.
function turnTainted(messages) {
    for (let i = (messages ?? []).length - 1; i >= 0; i--) {
        const m = messages[i];
        if (!m) continue;
        if (m.role === "user") return false;
        if (m.role !== "tool") continue;
        if (taintingTools.indexOf(m.functionName) >= 0) return true;
        if (String(m.functionResponse ?? "").indexOf(untrustedMark) >= 0) return true;
    }
    return false;
}

function suspends(name, messages) {
    return guardedTools.indexOf(name) >= 0 && turnTainted(messages);
}
