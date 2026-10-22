.pragma library
.import "endpoints.js" as Endpoints

// Screenshots and the model (M7, plan D8): who may see one, and how one rides in a request.
// No QML type is reachable from here: tests/test_ai_screen_rules.sh runs these under bun.
// DesktopTool.qml asks gate() before a `see` runs; Requester.qml asks it again for every
// request, so a screenshot taken for the local model never reaches a remote one the user
// switches to. The strategies render the image part with wire().

// Who is on the other end of `model`: its endpoint's host. A consent names it, and holds for
// that host for the rest of the chat.
function providerOf(model) {
    const host = Endpoints.hostOf(model?.endpoint ?? "");
    const name = `${model?.name ?? model?.model ?? ""}`.trim();
    return { "key": host, "label": name.length > 0 && host.length > 0 ? `${name} (${host})` : (name || host) };
}

/**
 * Whether a screenshot may go to `model`: {send, ask, reason, provider}.
 * - a local endpoint (endpoints.js isLocal, the one rule for local): yes, nothing asked;
 * - policies.ai == 2 (local only): never to anything else, whatever was consented;
 * - a remote endpoint the user consented to in this chat (`consents[host] === true`): yes;
 * - otherwise not yet: `ask` is true and the consent card names the provider.
 */
function gate(model, policyAi, consents) {
    const provider = providerOf(model);
    if (!model || `${model.endpoint ?? ""}`.length === 0)
        return { "send": false, "ask": false, "reason": "no model is chosen", "provider": provider };
    if (Endpoints.isLocal(model.endpoint))
        return { "send": true, "ask": false, "reason": "", "provider": provider };
    if (policyAi === 2)
        return { "send": false, "ask": false, "provider": provider,
            "reason": "this machine lets only local AI models see the screen (policies.ai)" };
    if ((consents ?? {})[provider.key] === true)
        return { "send": true, "ask": false, "reason": "", "provider": provider };
    return { "send": false, "ask": true, "provider": provider,
        "reason": `the user has not allowed ${provider.label} to see the screen in this chat` };
}

// A screenshot path that is safe inside the request script's single quotes and a bash pattern.
function safePath(path) {
    return /^\/[A-Za-z0-9_.\/-]+\.jpg$/.test(`${path ?? ""}`) && `${path}`.indexOf("..") < 0;
}

var placeholderHead = "@@KOOMPI_SCREEN:";
function placeholder(path) {
    return `${placeholderHead}${path}@@`;
}

/**
 * The messages a request is built from, with the newest screenshot in the conversation as a
 * user turn of its own right after the tool results it came with (a tool result cannot carry
 * an image in the chat-completions formats, and a user turn between two results of one call
 * batch is refused). Older screenshots are not resent: their marks are stale anyway. When
 * `allowed` is false, the turn says in words that the image was withheld and why. Plain
 * objects: the strategies read role, rawContent and screenImage.
 */
function withScreens(messages, allowed) {
    const list = (messages ?? []).slice();
    let at = -1;
    for (let i = list.length - 1; i >= 0; i--) {
        if (`${list[i]?.imageFile ?? ""}`.length > 0) { at = i; break; }
    }
    if (at < 0) return list;
    const path = `${list[at].imageFile}`;
    let end = at;
    while (end + 1 < list.length && list[end + 1]?.role === "tool") end++;
    const ok = allowed.send === true && safePath(path);
    const text = ok
        ? "The screenshot from the desktop tool, with its numbered marks:"
        : `(The screenshot was not sent: ${allowed.send === true ? "its file name is not one this shell writes" : allowed.reason}. Use the tree's text instead.)`;
    const turn = { "role": "user", "rawContent": text, "content": text, "screenImage": ok ? path : "" };
    list.splice(end + 1, 0, turn);
    return list;
}

// The image turn in one wire format. Gemini's is a content, Responses' a list of input items.
function wire(format, message) {
    const text = `${message.rawContent ?? ""}`;
    const path = `${message.screenImage ?? ""}`;
    const data = `data:image/jpeg;base64,${placeholder(path)}`;
    switch (format) {
    case "gemini":
        return { "role": "user", "parts": [{ "text": text }].concat(path.length > 0
            ? [{ "inline_data": { "mime_type": "image/jpeg", "data": placeholder(path) } }] : []) };
    case "responses":
        return [{ "type": "message", "role": "user", "content": [{ "type": "input_text", "text": text }].concat(path.length > 0
            ? [{ "type": "input_image", "image_url": data, "detail": "auto" }] : []) }];
    case "mistral":
        return { "role": "user", "content": path.length > 0
            ? [{ "type": "text", "text": text }, { "type": "image_url", "image_url": data }] : text };
    default:
        return { "role": "user", "content": path.length > 0
            ? [{ "type": "text", "text": text }, { "type": "image_url", "image_url": { "url": data } }] : text };
    }
}

function quote(s) {
    return `'${`${s}`.split("'").join("'\\''")}'`;
}

/**
 * How curl gets `body` (the request JSON): {setup, arg}. Without a screenshot, as before:
 * `--data '<json>'`. With one, the script reads the image when it runs, base64 into the
 * placeholder, writes the body to `bodyPath` (0600, the user's runtime dir) and curl sends that
 * file. A JPEG in base64 would also pass the 128 KiB a single argument may have. The image
 * bytes never pass through QML.
 */
function curlBody(body, bodyPath) {
    const paths = [];
    const re = /@@KOOMPI_SCREEN:([^@']+)@@/g;
    let m;
    while ((m = re.exec(body)) !== null) {
        if (paths.indexOf(m[1]) < 0) paths.push(m[1]);
    }
    if (paths.length === 0) return { "setup": "", "arg": `--data ${quote(body)}` };
    let setup = `koompi_body=${quote(body)}\n`;
    for (const path of paths) {
        setup += `koompi_shot=$(base64 -w0 < ${quote(path)}) || { printf 'The screenshot is gone; take a new one with see.\\n'; exit 1; }\n`;
        setup += `koompi_body=\${koompi_body//${quote(placeholder(path))}/"$koompi_shot"}\n`;
    }
    setup += `(umask 077; printf '%s' "$koompi_body" > ${quote(bodyPath)}) || exit 1\n`;
    return { "setup": setup, "arg": `--data-binary ${quote("@" + bodyPath)}` };
}
