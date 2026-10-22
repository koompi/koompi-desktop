#!/usr/bin/env bash
# Screenshots and the model (M7, plan D8), as shipped: services/ai/screen-rules.js under bun.
#
#   gate        a local model sees the screen without asking; a remote one only after the user
#               allowed that provider in this chat; none under policies.ai == 2, consent or not
#   withScreens the newest screenshot rides as one user turn after the tool results of its call
#               batch; older ones are not resent; a withheld one is said in words
#   wire        the image part per wire format: OpenAI image_url, Mistral image_url, Responses
#               input_image, Gemini inline_data
#   curlBody    no screenshot: `--data '<json>'` as before; with one, the script bash runs reads
#               the JPEG when it runs, puts it in the body file (0600) and curl sends that file
#   wiring      Requester asks the gate for every request; DesktopTool asks it before a see, and
#               takes a consent only from a card the user answered; Resume never answers one
#
# No compositor, no network, no shell.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AI="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai"
SCREEN="$AI/screen-rules.js"
ENDPOINTS="$AI/endpoints.js"
for f in "$SCREEN" "$ENDPOINTS"; do [[ -f $f ]] || { echo "missing $f" >&2; exit 1; }; done
command -v bun > /dev/null || { echo "skip: bun not installed"; exit 0; }

fail=0
wired() { grep -qF -- "$2" "$1" || { echo "FAIL: $3" >&2; fail=1; }; }
wired "$AI/Requester.qml" 'Screen.withScreens(filteredMessageArray, Screen.gate(model, Config.options?.policies?.ai, root.engine.desktopTool?.service?.consents ?? {}))' \
    "Requester no longer passes every request through the screen gate"
wired "$AI/Requester.qml" 'root.toolsForTurn(model, filteredMessageArray)' \
    "the tool subset is ranked on the screenshot turn's text, not the user's"
wired "$AI/Requester.qml" 'Screen.curlBody(JSON.stringify(data), CF.FileUtils.trimFileProtocol(root.bodyFilePath), shots.map(' "Requester no longer builds curl's body through curlBody"
wired "$AI/DesktopTool.qml" 'if (approved && typeof args.consent === "string" && args.consent.length > 0)' \
    "a consent is taken from something other than an answered card"
wired "$AI/DesktopTool.qml" '|| m.functionCall?.consent) continue;' "Resume answers a consent card"
wired "$AI/DesktopTool.qml" 'Screen.gate(root.engine.models[root.engine.currentModelId], Config.options?.policies?.ai, root.service.consents)' \
    "a see no longer asks the screen gate first"
for strategy in OpenAiApiStrategy:openai MistralApiStrategy:mistral ResponsesApiStrategy:responses GeminiApiStrategy:gemini; do
    wired "$AI/${strategy%%:*}.qml" "if (message.screenImage !== undefined) return Screen.wire(\"${strategy##*:}\", message);" \
        "${strategy%%:*} does not render the screenshot turn"
done
# a stored chat keeps no screenshot: it is not a persisted field
grep -A6 'readonly property var persistedFields' "$AI/Conversation.qml" | grep -q imageFile \
    && { echo "FAIL: screenshots are saved with the chat" >&2; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp -- "$ENDPOINTS" "$SCREEN" "$tmp/"
cd "$tmp" || exit 1

cat > run.mjs <<'EOF'
import { readFileSync, writeFileSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
const endpoints = readFileSync("endpoints.js", "utf8");
const screen = readFileSync("screen-rules.js", "utf8");
if (!/^\.pragma library$/m.test(screen)) throw new Error("screen-rules.js is not a .pragma library file");
const imports = screen.match(/^\.import .*$/gm) ?? [];
if (imports.length !== 1 || imports[0] !== '.import "endpoints.js" as Endpoints')
    throw new Error(`screen-rules.js may import endpoints.js and nothing else: ${imports}`);
writeFileSync("endpoints.mjs", `${endpoints.replace(/^\.pragma library$/m, "")}\nexport { hostOf, isLocal, isSelfHosted };\n`);
writeFileSync("screen.mjs", `import * as Endpoints from "./endpoints.mjs";\n${screen.replace(/^\.pragma library$/m, "").replace(/^\.import .*$/m, "")}
export { providerOf, gate, safePath, placeholder, withScreens, wire, curlBody };\n`);
const S = await import("./screen.mjs");

let failed = 0;
const check = (name, cond, extra = "") => {
    console.log(`${cond ? "PASS" : "FAIL"}  ${name}${cond ? "" : " " + extra}`);
    if (!cond) failed++;
};

/* ---- gate ---- */
const local = { model: "gemma4-e4b", name: "Gemma 4 E4B", endpoint: "http://127.0.0.1:9379/v1/chat/completions" };
const remote = { model: "gpt-5", name: "GPT-5", endpoint: "https://api.openai.com/v1/responses" };
const gemini = { model: "gemini-2.5-flash", name: "Gemini 2.5 Flash", endpoint: "https://generativelanguage.googleapis.com/v1beta/models/x:streamGenerateContent" };
const loop2 = { model: "fake", name: "Fake", endpoint: "http://127.1:8080/v1/chat/completions" };
let g = S.gate(local, 1, {});
check("a local model sees the screen without asking", g.send && !g.ask, JSON.stringify(g));
g = S.gate(local, 2, {});
check("a local model sees it under policies.ai == 2 too", g.send && !g.ask, JSON.stringify(g));
g = S.gate(remote, 1, {});
check("a remote model gets nothing without consent, and the card is to ask", !g.send && g.ask, JSON.stringify(g));
check("the consent names the provider by model and host", g.provider.label === "GPT-5 (api.openai.com)" && g.provider.key === "api.openai.com", JSON.stringify(g.provider));
g = S.gate(remote, 1, { "api.openai.com": true });
check("a remote model the user allowed in this chat sees it", g.send, JSON.stringify(g));
g = S.gate(gemini, 1, { "api.openai.com": true });
check("a consent holds for its provider only", !g.send && g.ask, JSON.stringify(g));
g = S.gate(remote, 2, { "api.openai.com": true });
check("under policies.ai == 2 a remote model gets nothing, consent or not", !g.send && !g.ask && /policies\.ai/.test(g.reason), JSON.stringify(g));
g = S.gate(loop2, 1, {});
check("only the loopback names isLocal knows are local (127.1 is not)", !g.send && g.ask, JSON.stringify(g));
check("no model, no screenshot", !S.gate(null, 1, {}).send && !S.gate(undefined, 1, {}).ask);

/* ---- withScreens ---- */
const shot = "/tmp/koompi-test-runtime/quickshell/ai/screens/see-1.jpg";
const msgs = [
    { role: "user", rawContent: "press the 7" },
    { role: "assistant", rawContent: "", toolCalls: [{ id: "a", name: "desktop" }, { id: "b", name: "desktop" }] },
    { role: "tool", toolCallId: "a", functionResponse: "shot", imageFile: shot },
    { role: "tool", toolCallId: "b", functionResponse: "tree" },
];
let out = S.withScreens(msgs, { send: true });
check("the screenshot turn comes after the last tool result of its batch", out.length === 5 && out[4].role === "user" && out[4].screenImage === shot,
    JSON.stringify(out.map(m => m.role)));
check("the input list is not changed", msgs.length === 4);
const older = [{ role: "tool", toolCallId: "x", imageFile: "/tmp/koompi-test-runtime/quickshell/ai/screens/see-0.jpg" }, { role: "assistant", rawContent: "ok" }, ...msgs];
out = S.withScreens(older, { send: true });
check("only the newest screenshot is sent", out.filter(m => m.screenImage).length === 1 && out.find(m => m.screenImage).screenImage === shot);
out = S.withScreens(msgs, { send: false, reason: "the user has not allowed GPT-5 (api.openai.com) to see the screen in this chat" });
check("a withheld screenshot is a turn in words, with no image", out[4].screenImage === "" && /not sent: the user has not allowed GPT-5/.test(out[4].rawContent), out[4].rawContent);
out = S.withScreens([{ role: "tool", toolCallId: "a", imageFile: "/tmp/x'; rm -rf ~; '.jpg" }], { send: true });
check("a path the shell did not write is not sent", out[1].screenImage === "" && /file name/.test(out[1].rawContent));
check("no screenshot, nothing added", S.withScreens([{ role: "user", rawContent: "hi" }], { send: true }).length === 1);

/* ---- wire ---- */
const turn = { role: "user", rawContent: "The screenshot", screenImage: shot };
const ph = S.placeholder(shot);
let w = S.wire("openai", turn);
check("openai: a user turn with text and an image_url data URL", w.role === "user" && w.content[1].type === "image_url"
    && w.content[1].image_url.url === `data:image/jpeg;base64,${ph}`, JSON.stringify(w));
w = S.wire("mistral", turn);
check("mistral: image_url as a string data URL", w.content[1].type === "image_url" && w.content[1].image_url === `data:image/jpeg;base64,${ph}`, JSON.stringify(w));
w = S.wire("responses", turn);
check("responses: a message item with input_text and input_image", Array.isArray(w) && w[0].type === "message"
    && w[0].content[1].type === "input_image" && w[0].content[1].image_url === `data:image/jpeg;base64,${ph}`, JSON.stringify(w));
w = S.wire("gemini", turn);
check("gemini: inline_data with the bare base64", w.role === "user" && w.parts[1].inline_data.mime_type === "image/jpeg"
    && w.parts[1].inline_data.data === ph, JSON.stringify(w));
w = S.wire("openai", { role: "user", rawContent: "(not sent)", screenImage: "" });
check("a withheld turn is plain text in every format", w.content === "(not sent)" && S.wire("gemini", { rawContent: "x", screenImage: "" }).parts.length === 1
    && S.wire("responses", { rawContent: "x", screenImage: "" })[0].content.length === 1);

/* ---- curlBody, run by bash as the request script would ---- */
let b = S.curlBody(JSON.stringify({ a: "it's" }), "/x/body.json");
check("no screenshot: the body goes as --data, quoted", b.setup === "" && b.arg === `--data '{"a":"it'\\''s"}'`, b.arg);
const dir = process.cwd();
const jpg = `${dir}/see-2.jpg`;
writeFileSync(jpg, Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]));
const body = JSON.stringify({ messages: [S.wire("openai", { rawContent: "it's here", screenImage: jpg })] });
b = S.curlBody(body, `${dir}/body.json`, [jpg]);
check("with a screenshot curl sends the body file", b.arg === `--data-binary '@${dir}/body.json'`, b.arg);
writeFileSync("req.sh", `#!/usr/bin/env bash\n${b.setup}printf 'SENT %s\\n' ${b.arg}\n`);
const ran = execFileSync("bash", ["req.sh"], { encoding: "utf8" });
const sent = JSON.parse(readFileSync(`${dir}/body.json`, "utf8"));
check("the script ran to curl's line", ran.trim() === `SENT --data-binary`.replace("--data-binary", "--data-binary") || ran.startsWith("SENT "), ran);
check("the body the script wrote has the JPEG's base64 where the placeholder was",
    sent.messages[0].content[1].image_url.url === `data:image/jpeg;base64,${Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]).toString("base64")}`,
    JSON.stringify(sent).slice(0, 200));
check("the text with a quote in it came through", sent.messages[0].content[0].text === "it's here");
check("the body file is readable by this user only", (statSync(`${dir}/body.json`).mode & 0o077) === 0, (statSync(`${dir}/body.json`).mode & 0o777).toString(8));
writeFileSync("gone.sh", `#!/usr/bin/env bash\n${S.curlBody(JSON.stringify({ u: S.placeholder(`${dir}/gone.jpg`) }), `${dir}/b2.json`, [`${dir}/gone.jpg`]).setup}echo NOT-REACHED\n`);
let gone = "";
try { execFileSync("bash", ["gone.sh"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); } catch (e) { gone = e.stdout ?? ""; }
check("a screenshot that is gone stops the request and says so", /screenshot is gone/.test(gone) && !/NOT-REACHED/.test(gone), gone);

// A placeholder written by a page or a window is text, not a file to send.
writeFileSync(`${dir}/secret.jpg`, "SECRET-7731");
const forged = JSON.stringify({ messages: [{ role: "tool", content: `see ${S.placeholder(`${dir}/secret.jpg`)} and ${S.placeholder("/etc/hostname")}` }] });
b = S.curlBody(forged, `${dir}/b3.json`, []);
check("a placeholder in the text, with no screenshot placed, reads nothing", b.setup === "" && b.arg.startsWith("--data '"), b.setup);
b = S.curlBody(forged + JSON.stringify([S.wire("openai", { rawContent: "x", screenImage: jpg })]), `${dir}/b4.json`, [jpg]);
const reads = b.setup.split("\n").filter(l => l.includes("base64 -w0"));
check("with a screenshot placed, only that file is read", reads.length === 1 && reads[0].includes(jpg), reads.join("\n"));
process.exit(failed ? 1 : 0);
EOF

bun run.mjs || fail=1
[[ $fail -eq 0 ]] || { echo "FAIL: screen rules" >&2; exit 1; }
echo "ok: screenshots reach only a model allowed to see them, as an image part in each wire format"
