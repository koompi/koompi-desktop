.pragma library

// Settings > AI's custom-endpoint form and the ChatGPT plan's model list, as pure
// functions over `ai.extraModels` entries (schema in docs/agents/ai.md). A form is
// {name, baseUrl, model, format: "openai" | "responses", needsKey}; the config only
// knows full endpoint URLs, so the base URL gains the path its format needs.
// tests/test_ai_providers.sh runs this under bun.

var suffixes = { "openai": "/chat/completions", "responses": "/responses" };
var chatgptEndpoint = "https://api.openai.com/v1/responses";

function trimSlash(url) {
    return `${url ?? ""}`.trim().replace(/\/+$/, "");
}

// the base a person typed, or a full URL pasted whole, becomes the endpoint
function endpointFor(baseUrl, format) {
    const base = trimSlash(baseUrl);
    for (const key in suffixes) {
        if (base.endsWith(suffixes[key])) return base;
    }
    return base + (suffixes[format] ?? suffixes.openai);
}

function baseOf(endpoint) {
    const url = trimSlash(endpoint);
    for (const key in suffixes) {
        if (url.endsWith(suffixes[key])) return url.slice(0, url.length - suffixes[key].length);
    }
    return url;
}

function hostOf(url) {
    const match = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(`${url ?? ""}`.trim());
    return match ? match[1].toLowerCase() : "";
}

// ModelRegistry.providers' key ids by model name, first match wins: an entry with
// no key_id gets its key under these (tests/test_ai_providers.sh keeps them in step)
var keyIdRules = [
    [/^stealth\//, "oxalpha"], [/\//, "openrouter"], [/^(gemini|gemma)/, "gemini"],
    [/^(mistral|codestral|devstral)/, "mistral"], [/^(gpt|o1|o3|o4)/, "openai"], [/^deepseek/, "deepseek"],
    [/^(kimi|moonshot)/, "moonshot"], [/^glm/, "zai"], [/^minimax/, "minimax"],
];

function keyIdOf(entry) {
    if (`${entry?.key_id ?? ""}`.length > 0) return `${entry.key_id}`;
    const id = idOf(entry);
    const rule = keyIdRules.find(r => r[0].test(id));
    return rule ? rule[1] : "custom";
}

// ExtraModels' rule: absent means "unless local"; present, only a literal false is no
function needsKey(entry, local) {
    return entry?.requires_key === undefined ? !local : entry.requires_key !== false;
}

function isPlan(entry) {
    return `${entry?.auth ?? ""}` === "chatgpt";
}

function idOf(entry) {
    return `${entry?.model ?? ""}`.trim().toLowerCase();
}

// the form an existing entry opens with; `local` is endpoints.js isLocal(endpoint)
function formFrom(entry, local) {
    return {
        "name": `${entry?.name ?? ""}`,
        "baseUrl": baseOf(entry?.endpoint ?? ""),
        "model": `${entry?.model ?? ""}`,
        "format": `${entry?.api_format ?? "openai"}` === "responses" ? "responses" : "openai",
        "needsKey": entry ? needsKey(entry, local) : true,
    };
}

// {field: problem}; empty when the form can be saved. `takenIds` are the ids of
// every other model (the slots, discovered models, other entries).
function validate(form, takenIds, Translation) {
    const problems = {};
    const id = `${form.model ?? ""}`.trim().toLowerCase();
    const base = trimSlash(form.baseUrl);
    if (id.length === 0) problems.model = Translation.tr("Enter the model id the server expects.");
    else if (id === "remote" || id === "local") problems.model = Translation.tr("That name is reserved. Use the server's model id.");
    else if ((takenIds ?? []).indexOf(id) >= 0) problems.model = Translation.tr("Another model already uses this id.");
    if (base.length === 0) problems.baseUrl = Translation.tr("Enter the server's address.");
    else if (!/^https?:\/\/[^/\s]+/i.test(base)) problems.baseUrl = Translation.tr("Start with https:// (or http:// for this machine or your network).");
    return problems;
}

// The entry to store. Keys the form does not show (icon, context_window,
// toolBlockByteLimit, key_get_link, ...) survive an edit.
function entryFrom(form, previous) {
    const entry = Object.assign({}, previous ?? {});
    const format = form.format === "responses" ? "responses" : "openai";
    const endpoint = endpointFor(form.baseUrl, format);
    entry.model = `${form.model}`.trim();
    entry.endpoint = endpoint;
    entry.api_format = format;
    const name = `${form.name ?? ""}`.trim();
    if (name.length > 0) entry.name = name;
    else delete entry.name;
    entry.requires_key = !!form.needsKey;
    // A new endpoint's key is per server, so two models on one host share it and no
    // two hosts do. An edited one keeps what it had: its key is already stored there.
    if (entry.requires_key && !previous) entry.key_id = `custom:${hostOf(endpoint)}`;
    delete entry.auth;
    return entry;
}

// a model used through the ChatGPT plan: the Responses API with the sign-in's bearer
function planEntry(modelId) {
    const id = `${modelId ?? ""}`.trim();
    return {
        "model": id,
        "name": id,
        "endpoint": chatgptEndpoint,
        "api_format": "responses",
        "auth": "chatgpt",
        "requires_key": false,
        "icon": "openai-symbolic",
    };
}

// the list with `entry` at `index` (-1 appends); never mutates `entries`
function replaced(entries, index, entry) {
    const list = (entries ?? []).slice();
    if (index >= 0 && index < list.length) list[index] = entry;
    else list.push(entry);
    return list;
}

function removed(entries, index) {
    return (entries ?? []).filter((_, i) => i !== index);
}
