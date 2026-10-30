.pragma library

// What get_shell_config answers, sized for a 16k-window model. The whole config
// is about 14 KB, the system prompt alone 3.5 KB of it: on gemma4-e4b that one
// result pushed the turn into compaction, minutes of it, and the model still read
// `bar.bottom` wrong out of the pile (tests/bench/ai, config-read). So the call
// without a section lists the sections and their keys, and a section answers
// with its own values.

function render(config, section) {
    const path = `${section ?? ""}`.trim().replace(/^config\./, "");
    if (path.length === 0) {
        const lines = Object.keys(config).map(key => {
            const value = config[key];
            const nested = value !== null && typeof value === "object" && !Array.isArray(value);
            return `${key}: ${nested ? Object.keys(value).join(", ") : JSON.stringify(value)}`;
        });
        return "Sections and their keys. Call again with a section, like `bar`, to read its values.\n" + lines.join("\n");
    }
    let node = config;
    for (const part of path.split(".")) {
        if (node === null || typeof node !== "object" || !(part in node))
            return `There is no \`${path}\`. Call without a section to list them.`;
        node = node[part];
    }
    // the model's own prompt, which it already has
    if (path === "ai" && typeof node.systemPrompt === "string")
        node = Object.assign({}, node, { "systemPrompt": "(your system prompt, not repeated here)" });
    return JSON.stringify(node);
}
