#!/usr/bin/env bash
# Settings > AI > Providers, the logic half, run as shipped under bun:
#   - services/ai/request-errors.js: OpenAI and Responses errors in plain words
#     (401 sign in again or replace the key, 429 with its reset time, 5xx try again);
#   - modules/settings/ai/endpoint-form.js: the custom-endpoint form and the plan's entries;
#   - the key ids Settings lists and infers agree with ModelRegistry.providers;
#   - the HTTP status trailer end to end: request scripts built by the shipped
#     strategies run curl against a fake server on 127.0.0.1, and their output, fed
#     back through the shipped parsers, reads as the plain words, not a JSON body.
# No network beyond loopback, no keyring, no shell.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AI="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai"
SETTINGS="$REPO_ROOT/dots/.config/quickshell/koompi/modules/settings/ai"
for f in "$AI/request-errors.js" "$SETTINGS/endpoint-form.js" "$AI/ResponsesApiStrategy.qml" "$AI/OpenAiApiStrategy.qml" \
    "$AI/ModelRegistry.qml" "$SETTINGS/ApiKeyProviders.qml"; do
    [[ -f $f ]] || { echo "FAIL: missing $f" >&2; exit 1; }
done
command -v bun > /dev/null || { echo "skip: bun not installed"; exit 0; }
command -v python3 > /dev/null || { echo "skip: python3 not installed"; exit 0; }
command -v curl > /dev/null || { echo "skip: curl not installed"; exit 0; }

fail=0
# the wiring the library is only as good as
grep -q 'scriptContent = Errors.withStatusTrailer(scriptContent);' "$AI/ResponsesApiStrategy.qml" \
    || { echo "FAIL: ResponsesApiStrategy no longer asks curl for the status" >&2; fail=1; }
grep -q 'return Errors.withStatusTrailer(scriptContent);' "$AI/OpenAiApiStrategy.qml" \
    || { echo "FAIL: OpenAiApiStrategy no longer asks curl for the status" >&2; fail=1; }
grep -q 'Errors.render(Errors.explain(' "$AI/ResponsesApiStrategy.qml" \
    || { echo "FAIL: ResponsesApiStrategy does not explain its errors" >&2; fail=1; }
grep -q 'Errors.render(Errors.explain(' "$AI/OpenAiApiStrategy.qml" \
    || { echo "FAIL: OpenAiApiStrategy does not explain its errors" >&2; fail=1; }

tmp="$(mktemp -d)"
server_pid=""
cleanup() {
    [[ -n $server_pid ]] && kill "$server_pid" 2> /dev/null
    rm -rf -- "$tmp"
}
trap cleanup EXIT

# --- a fake provider on loopback: one path per failure ------------------------
cat > "$tmp/server.py" << 'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

def pretty(code, err):
    return code, json.dumps({"error": err}, indent=4), {}

ROUTES = {
    "/plan401/responses": pretty(401, {"message": "Your authentication token has expired.", "type": "invalid_request_error", "code": "token_expired"}),
    "/key401/chat/completions": pretty(401, {"message": "Incorrect API key provided.", "type": "invalid_request_error", "code": "invalid_api_key"}),
    "/usage/responses": pretty(429, {"message": "You have hit your usage limit.", "type": "usage_limit_reached", "code": None, "resets_in_seconds": 7200}),
    "/rate/chat/completions": (429, json.dumps({"error": {"message": "Rate limit reached", "type": "requests", "code": "rate_limit_exceeded"}}, indent=2), {"Retry-After": "300"}),
    "/down/responses": (503, "<html>Service Unavailable</html>", {}),
    "/ok/responses": (200, "".join(f"event: {e['type']}\ndata: {json.dumps(e)}\n\n" for e in [
        {"type": "response.output_text.delta", "output_index": 0, "delta": "Hello."},
        {"type": "response.completed", "response": {"usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}}]), {}),
}

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        status, body, headers = ROUTES.get(self.path, (404, "{}", {}))
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/event-stream" if status == 200 else "application/json")
        for k, v in headers.items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a):
        pass

server = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(server.server_address[1]))
server.serve_forever()
PY
python3 -I "$tmp/server.py" "$tmp/port" &
server_pid=$!
for _ in $(seq 50); do [[ -s $tmp/port ]] && break; sleep 0.1; done
[[ -s $tmp/port ]] || { echo "FAIL: the fake provider did not start" >&2; exit 1; }

cat > "$tmp/run.mjs" << 'JS'
import { readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const [aiDir, settingsDir, port] = process.argv.slice(2);
const lib = (dir, file, names) => {
    const out = `./${file.replace(/\.js$/, ".mjs")}`;
    writeFileSync(out, readFileSync(`${dir}/${file}`, "utf8").replace(/^\.pragma library\s*$/m, "")
        + `\nexport { ${names.join(", ")} };\n`);
    return import(out);
};
const E = await lib(aiDir, "request-errors.js", ["trailerType", "withStatusTrailer", "fromBody", "fromError", "explain", "render"]);
const F = await lib(settingsDir, "endpoint-form.js", ["keyIdRules", "keyIdOf", "needsKey", "endpointFor", "baseOf", "hostOf", "isPlan", "idOf",
    "formFrom", "validate", "entryFrom", "planEntry", "replaced", "removed", "chatgptEndpoint"]);
const T = { tr: s => s };

let failed = 0;
const check = (name, cond, extra = "") => {
    console.log(`${cond ? "PASS" : "FAIL"}  ${name}${cond ? "" : "  " + extra}`);
    if (!cond) failed++;
};
const say = err => E.explain(err, T, 1_000_000_000_000);

// --- request-errors.js ---------------------------------------------------------
let r = say({ status: 401, code: "token_expired", auth: "chatgpt" });
check("401 on the plan: sign in again", r.title === "Sign in again." && r.action === "sign_in" && r.text.includes("Continue with ChatGPT"), JSON.stringify(r));
r = say({ status: 401, code: "invalid_api_key", auth: "key" });
check("401 with a key: replace the key", r.title === "API key refused." && r.action === "key", JSON.stringify(r));
r = say({ code: "invalid_api_key", auth: "chatgpt" });
check("an auth code with no status on the plan still says sign in", r.action === "sign_in", JSON.stringify(r));
r = say({ code: "chatgpt_auth_4" });
check("the helper's exit 4: sign in again", r.title === "Sign in again.", JSON.stringify(r));
r = say({ code: "chatgpt_auth_3" });
check("the helper's exit 3: plan not included", r.title === "Plan not included." && r.action === "sign_in", JSON.stringify(r));
r = say({ code: "chatgpt_auth_5" });
check("the helper's exit 5: can't reach OpenAI", r.title === "Can't reach OpenAI." && r.action === "retry", JSON.stringify(r));
r = say({ status: 429, code: "usage_limit_reached", resetsInSeconds: 7200, auth: "chatgpt" });
check("429 plan limit with resets_in_seconds says when", r.title === "Usage limit reached." && r.text.includes("resets in about 2 hours"), JSON.stringify(r));
r = say({ status: 429, auth: "chatgpt", resetsAt: (1_000_000_000_000 / 1000) + 25 * 60 });
check("429 plan limit with resets_at (unix seconds) says when", r.text.includes("about 25 minutes"), JSON.stringify(r));
r = say({ status: 429, auth: "chatgpt", resetsAt: new Date(1_000_000_000_000 + 3 * 86400_000).toISOString() });
check("429 plan limit with an ISO resets_at says when", r.text.includes("about 3 days"), JSON.stringify(r));
r = say({ code: "subscription_sharing_usage_limit_exceeded" });
check("a usage-limit code without a status is the plan limit", r.title === "Usage limit reached." && r.text.includes("Try again later"), JSON.stringify(r));
r = say({ status: 429, code: "rate_limit_exceeded", retryAfter: "45", auth: "key" });
check("429 rate limit with Retry-After seconds", r.title === "Too many requests." && r.text.includes("about a minute"), JSON.stringify(r));
r = say({ status: 429, code: "rate_limit_exceeded", auth: "key" });
check("429 rate limit with no reset: wait a moment", r.text.includes("Wait a moment"), JSON.stringify(r));
r = say({ status: 429, code: "insufficient_quota", auth: "key" });
check("insufficient_quota is out of credit, not a wait", r.title === "Out of credit.", JSON.stringify(r));
for (const status of [500, 502, 503, 504]) {
    r = say({ status, auth: "chatgpt" });
    check(`${status}: try again`, r.title === "The service had a problem." && r.action === "retry" && r.code === `HTTP ${status}`, JSON.stringify(r));
}
r = say({ code: "server_error" });
check("server_error with no status: try again", r.action === "retry", JSON.stringify(r));
r = say({ code: "context_length_exceeded", status: 400 });
check("context_length_exceeded: too long", r.title === "Conversation too long.", JSON.stringify(r));
r = say({ status: 404, code: "model_not_found" });
check("404 model_not_found", r.title === "Model not found.", JSON.stringify(r));
r = say({ status: 403, code: "unsupported_country_region_territory" });
check("403 not allowed", r.title === "Not allowed.", JSON.stringify(r));
r = say({ code: "incomplete_stream" });
check("a cut stream", r.title === "The reply was cut off.", JSON.stringify(r));
r = say({ status: -1, code: "unreachable" });
check("no answer at all", r.title === "Can't reach the model." && r.code === "unreachable", JSON.stringify(r));
r = say({ status: 400, code: "weird_new_code", message: "Something specific." });
check("an unknown code keeps the server's words and its code", r.text === "Something specific." && r.code === "weird_new_code", JSON.stringify(r));
check("render puts the words first and the code last",
    E.render(say({ status: 401, auth: "chatgpt", code: "token_expired" })) === "\n\n**Sign in again.** Your ChatGPT sign-in has ended. Open Settings > AI and choose Continue with ChatGPT. `token_expired`");
check("fromBody reads a pretty error body", E.fromBody('{\n  "error": {\n    "code": "x", "message": "m", "resets_at": 5\n  }\n}')?.resetsAt === 5);
check("fromBody reads a string error", E.fromBody('{"error":"invalid_grant","error_description":"d"}')?.code === "invalid_grant");
check("fromBody refuses HTML", E.fromBody("<html>Service Unavailable</html>") === null);
const trailed = E.withStatusTrailer("#!/usr/bin/env bash\nexec curl --no-buffer \"u\" --data 'x'\n");
check("the trailer goes on the exec'd curl, before its arguments", /exec curl --write-out '.*%\{http_code\}.*' --no-buffer/.test(trailed), trailed);
check("a script without exec curl is left alone (the compactor's)", E.withStatusTrailer("curl x") === "curl x");

// --- endpoint-form.js ----------------------------------------------------------
check("a base URL gains /chat/completions", F.endpointFor("https://h.example/v1/", "openai") === "https://h.example/v1/chat/completions");
check("a base URL gains /responses", F.endpointFor("https://h.example/v1", "responses") === "https://h.example/v1/responses");
check("a pasted full URL is kept", F.endpointFor("https://h.example/v1/chat/completions", "responses") === "https://h.example/v1/chat/completions");
check("baseOf undoes it", F.baseOf("https://h.example/v1/responses") === "https://h.example/v1");
const taken = ["remote", "local", "gpt-5"];
let p = F.validate({ model: "", baseUrl: "" }, taken, T);
check("empty form: both fields have a problem", !!p.model && !!p.baseUrl, JSON.stringify(p));
p = F.validate({ model: "GPT-5", baseUrl: "https://x" }, taken, T);
check("a taken id is refused, case-blind", (p.model ?? "").includes("already uses"), JSON.stringify(p));
p = F.validate({ model: "local", baseUrl: "https://x" }, [], T);
check("a slot name is refused", (p.model ?? "").includes("reserved"), JSON.stringify(p));
p = F.validate({ model: "m", baseUrl: "ftp://x" }, [], T);
check("a non-http URL is refused", !!p.baseUrl, JSON.stringify(p));
p = F.validate({ model: "qwen3", baseUrl: "http://192.168.1.5:8080/v1" }, taken, T);
check("a good form has no problems", Object.keys(p).length === 0, JSON.stringify(p));
let entry = F.entryFrom({ name: " Box ", baseUrl: "http://192.168.1.5:8080/v1", model: "qwen3", format: "openai", needsKey: true }, null);
check("a new entry", entry.model === "qwen3" && entry.endpoint === "http://192.168.1.5:8080/v1/chat/completions"
    && entry.api_format === "openai" && entry.name === "Box" && entry.requires_key === true && entry.key_id === "custom:192.168.1.5:8080", JSON.stringify(entry));
const old = { model: "stealth/ox-alpha", endpoint: "https://tokenra.io/v1/chat/completions", name: "Custom: 0xAlpha", icon: "oxalpha-symbolic",
    context_window: 131072, toolBlockByteLimit: 1461, key_get_link: "https://oxalpha.io/" };
entry = F.entryFrom(Object.assign(F.formFrom(old, false), { format: "responses" }), old);
check("an edit keeps the keys the form does not show", entry.icon === "oxalpha-symbolic" && entry.context_window === 131072
    && entry.toolBlockByteLimit === 1461 && entry.key_get_link === "https://oxalpha.io/", JSON.stringify(entry));
check("an edit keeps an absent key_id absent (the key stays where it is)", !("key_id" in entry) && F.keyIdOf(entry) === "oxalpha", JSON.stringify(entry));
check("an edit that changes the format moves the path", entry.endpoint === "https://tokenra.io/v1/chat/completions" || entry.endpoint.endsWith("/responses"), entry.endpoint);
check("formFrom: absent requires_key on a local endpoint means no key", F.formFrom({ model: "m", endpoint: "http://127.0.0.1:1/v1/chat/completions" }, true).needsKey === false);
check("formFrom: absent requires_key remote means a key", F.formFrom({ model: "m", endpoint: "https://x/v1/chat/completions" }, false).needsKey === true);
entry = F.entryFrom({ baseUrl: "http://127.0.0.1:9/v1", model: "m", format: "openai", needsKey: false }, null);
check("no key: requires_key false and no key_id", entry.requires_key === false && !("key_id" in entry), JSON.stringify(entry));
const plan = F.planEntry(" gpt-5 ");
check("a plan entry is the Responses API with the sign-in", plan.model === "gpt-5" && plan.auth === "chatgpt" && plan.api_format === "responses"
    && plan.requires_key === false && plan.endpoint === "https://api.openai.com/v1/responses" && F.isPlan(plan), JSON.stringify(plan));
const list = [{ model: "a" }, { model: "b" }];
check("replaced appends at -1 and leaves the input alone", F.replaced(list, -1, { model: "c" }).length === 3 && list.length === 2);
check("replaced swaps at an index", F.replaced(list, 1, { model: "z" })[1].model === "z" && list[1].model === "b");
check("removed drops one", JSON.stringify(F.removed(list, 0)) === JSON.stringify([{ model: "b" }]));

// --- the key ids agree with ModelRegistry.providers -----------------------------
const registry = readFileSync(`${aiDir}/ModelRegistry.qml`, "utf8");
const block = /readonly property var providers: \[([\s\S]*?)\n    \]/.exec(registry)?.[1] ?? "";
const rules = [...block.matchAll(/^\s*\[(\/.*?\/), "[^"]*", "[^"]*", "([^"]+)"/gm)].map(m => [m[1], m[2]]);
check("ModelRegistry.providers was read", rules.length >= 9, JSON.stringify(rules));
const named = rules.filter(rule => rule[0] !== "/./");
check("endpoint-form.js keyIdRules match ModelRegistry.providers rule for rule",
    JSON.stringify(named) === JSON.stringify(F.keyIdRules.map(rule => [rule[0].toString(), rule[1]])),
    JSON.stringify({ registry: named, form: F.keyIdRules.map(rule => [rule[0].toString(), rule[1]]) }));
check("the fallback key id is custom in both", rules.find(rule => rule[0] === "/./")?.[1] === "custom" && F.keyIdOf({ model: "zzz" }) === "custom");
const listed = [...readFileSync(`${settingsDir}/ApiKeyProviders.qml`, "utf8").matchAll(/"keyId": "([^"]+)"/g)].map(m => m[1]).sort();
const known = [...new Set(named.map(rule => rule[1]))].sort();
check("Settings lists a key row for every provider ModelRegistry infers", JSON.stringify(listed) === JSON.stringify(known), JSON.stringify({ listed, known }));

// --- the status trailer, end to end on loopback -----------------------------------
const lift = (qml, name) => {
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found`);
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
};
const strip = s => s.replace(/function (\w+)\(([^)]*)\): [\w<>]+/g, (_, n, a) => `function ${n}(${a})`)
    .replace(/(\w+): (AiModel|string|real|int|bool|var|list<var>|AiMessageData)(?!\w)/g, "$1");
const responsesQml = readFileSync(`${aiDir}/ResponsesApiStrategy.qml`, "utf8");
const respNames = ["parseResponseLine", "onStatus", "handleEvent", "noteItem", "callAt", "appendText", "closeThinking",
    "takeCalls", "complete", "fail", "onRequestFinished", "reset", "finalizeScriptContent", "buildRequestData", "inputItems", "stripThinking"];
writeFileSync("./responses.mjs", strip(`import * as Errors from "./request-errors.mjs";
const Translation = { tr: s => s };
let isReasoning = false, pendingCalls = {}, completed = false, failed = false, authKind = "", heldBody = "";
const tokenVar = "KOOMPI_CHATGPT_TOKEN"; const forbiddenFields = [];
${respNames.map(n => lift(responsesQml, n)).join("\n")}
export { ${respNames.join(", ")} };`));
const openaiQml = readFileSync(`${aiDir}/OpenAiApiStrategy.qml`, "utf8");
const oaNames = ["parseResponseLine", "onStatus", "explainError", "takeCompletedToolCalls", "finalizeScriptContent", "reset", "buildRequestData", "wireMessage"];
writeFileSync("./openai.mjs", strip(`import * as Errors from "./request-errors.mjs";
const Translation = { tr: s => s };
let isReasoning = false, pendingToolCalls = {}, toolCallEmitted = false, failed = false, authKind = "", heldBody = "";
${oaNames.map(n => lift(openaiQml, n)).join("\n")}
export { ${oaNames.join(", ")} };`));
const R = await import("./responses.mjs");
const O = await import("./openai.mjs");

// what Requester.makeRequest writes, run by bash, its stdout fed line by line
function turn(strategy, model, url) {
    strategy.reset();
    strategy.buildRequestData(model, [], "sys", 0, [], "");
    const script = strategy.finalizeScriptContent("#!/usr/bin/env bash\n"
        + `exec curl --no-buffer --max-time 10 "${url}" -H 'Content-Type: application/json' --data '{}'\n`);
    writeFileSync("./request.sh", script);
    let out = "";
    try {
        out = execFileSync("bash", ["./request.sh"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    } catch (e) {
        out = e.stdout ?? "";
    }
    const message = { role: "assistant", content: "", rawContent: "", toolCalls: [], functionName: "" };
    let finished = false;
    const log = console.log;
    console.log = () => {}; // the strategy logs each line of an error body it cannot parse
    for (const line of out.split("\n")) {
        if (line.length === 0) continue; // SplitParser hands over no empty lines
        if (strategy.parseResponseLine(line, message)?.finished) finished = true;
    }
    console.log = log;
    strategy.onRequestFinished?.(message);
    return { message, finished };
}
const base = `http://127.0.0.1:${port}`;
const planModel = { model: "gpt-5", auth: "chatgpt", requires_key: false };
const keyed = { model: "gpt-5", requires_key: true };
let t = turn(R, planModel, `${base}/plan401/responses`);
check("e2e: a plan 401 with a pretty body reads Sign in again", t.message.content.includes("**Sign in again.**") && t.finished, JSON.stringify(t.message.content));
check("e2e: and the JSON body is gone from the transcript", !t.message.content.includes('"error"') && !t.message.content.includes("{"), JSON.stringify(t.message.content));
t = turn(R, planModel, `${base}/usage/responses`);
check("e2e: a plan 429 says when it resets", t.message.content.includes("It resets in about 2 hours."), JSON.stringify(t.message.content));
t = turn(R, planModel, `${base}/down/responses`);
check("e2e: a 503 with an HTML body says try again", t.message.content.includes("**The service had a problem.**") && t.message.content.includes("`HTTP 503`")
    && !t.message.content.includes("<html>"), JSON.stringify(t.message.content));
t = turn(R, planModel, `${base}/ok/responses`);
check("e2e: a good stream is untouched by its 200 trailer", t.message.content === "Hello.", JSON.stringify(t.message.content));
t = turn(R, planModel, "http://127.0.0.1:1/v1/responses");
check("e2e: nothing listening reads Can't reach the model", t.message.content.includes("**Can't reach the model.**"), JSON.stringify(t.message.content));
t = turn(O, keyed, `${base}/key401/chat/completions`);
check("e2e: a chat-completions 401 with a key says replace it", t.message.content.includes("**API key refused.**") && !t.message.content.includes("{"), JSON.stringify(t.message.content));
t = turn(O, keyed, `${base}/rate/chat/completions`);
check("e2e: a chat-completions 429 reads Retry-After", t.message.content.includes("Try again in about 5 minutes."), JSON.stringify(t.message.content));

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok: request errors in plain words, the endpoint form, provider key ids, the status trailer end to end");
JS

(cd "$tmp" && bun run run.mjs "$AI" "$SETTINGS" "$(cat "$tmp/port")") || fail=1
exit "$fail"
