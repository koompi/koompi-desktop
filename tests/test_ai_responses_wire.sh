#!/usr/bin/env bash
# The OpenAI Responses API, the only route a ChatGPT plan takes: the system prompt is
# `instructions`, the whole history rides in `input`, nothing is stored, and the plan
# route refuses temperature and the other sampling and bookkeeping fields. Runs the
# real functions out of ResponsesApiStrategy.qml and ToolRegistry.qml against a
# recorded event stream. No network.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai"
STRATEGY="$QML_DIR/ResponsesApiStrategy.qml"
REGISTRY="$QML_DIR/ToolRegistry.qml"

[[ -f "$STRATEGY" ]] || { echo "FAIL: missing $STRATEGY" >&2; exit 1; }
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

grep -q '"responses": root.responsesApiStrategy.createObject(root)' "$QML_DIR/ModelRegistry.qml" \
    || { echo "FAIL: ModelRegistry does not register the responses strategy" >&2; exit 1; }
grep -q '"responses": {' "$REGISTRY" \
    || { echo "FAIL: ToolRegistry has no tool set for the responses format" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/run.mjs" <<'EOF'
import { readFileSync, writeFileSync } from "node:fs";

// Lift a function out of a .qml by brace matching, so the test runs the shipped
// source rather than a copy that can drift away from it.
function lift(file, name) {
    const qml = readFileSync(file, "utf8");
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found in ${file}`);
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}
const strip = s => s
    .replace(/function (\w+)\(([^)]*)\): [\w<>]+/g, (_, n, a) => `function ${n}(${a})`)
    .replace(/(\w+): (AiModel|string|real|int|bool|var|list<var>|AiMessageData)(?!\w)/g, "$1");

const [strategyFile, registryFile] = process.argv.slice(2);
const names = ["stripThinking", "inputItems", "buildRequestData", "buildAuthorizationHeader",
    "parseResponseLine", "handleEvent", "noteItem", "callAt", "appendText", "closeThinking",
    "takeCalls", "complete", "fail", "onRequestFinished", "reset"];
writeFileSync("./strategy.mjs", strip(`
const Translation = { tr: s => s };
const root = { emptyParameters: { type: "object", properties: {} } };
let isReasoning = false, pendingCalls = {}, completed = false, failed = false;
const tokenVar = "KOOMPI_CHATGPT_TOKEN";
const forbiddenFields = ${/forbiddenFields: (\[[^\]]*\])/.exec(readFileSync(strategyFile, "utf8"))[1]};
${names.map(n => lift(strategyFile, n)).join("\n")}
${lift(registryFile, "responsesDeclaration")}
export { ${names.join(", ")}, responsesDeclaration };
`));

const s = await import("./strategy.mjs");

let failedChecks = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failedChecks++; }
};
const msg = (over = {}) => Object.assign({
    role: "user", content: "", rawContent: "", functionName: "", functionResponse: "",
    toolCalls: [], toolCallId: "",
}, over);

// --- Request body: a conversation with one tool round trip.
const tool = s.responsesDeclaration({ name: "recall", description: "Search memory",
    parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] } });
const conversation = [
    msg({ role: "user", rawContent: "what editor do i use?" }),
    msg({ role: "assistant", rawContent: "\n\n<think>\n\nlook it up\n\n</think>\n\nChecking.",
        toolCalls: [{ id: "call_abc", name: "recall", arguments: '{"query":"editor"}' }] }),
    msg({ role: "tool", functionName: "recall", functionResponse: "- prefers helix", toolCallId: "call_abc" }),
];
const model = { model: "gpt-5", requires_key: true, extraParams: { temperature: 0.2, metadata: { a: 1 } } };
const body = s.buildRequestData(model, conversation, "You are KOOMPI.", 0.7, [tool], "");
writeFileSync("./body.json", JSON.stringify(body, null, 2));

check("instructions carry the system prompt", body.instructions === "You are KOOMPI.", body.instructions);
check("store is false", body.store === false);
check("stream is true", body.stream === true);
check("the model is named", body.model === "gpt-5");
const raw = JSON.stringify(body);
check("no system role anywhere in the body", !/"role":"(system|developer)"/.test(raw), raw);
for (const field of ["temperature", "max_output_tokens", "previous_response_id", "metadata", "user", "messages"])
    check(`no ${field} field`, !(field in body), JSON.stringify(body[field]));
const call = body.input.find(i => i.type === "function_call");
const output = body.input.find(i => i.type === "function_call_output");
check("the call goes out as a function_call item", call?.name === "recall" && call?.arguments === '{"query":"editor"}', JSON.stringify(call));
check("the result goes out as a function_call_output item", output?.output === "- prefers helix", JSON.stringify(output));
check("call and output pair by call_id", call?.call_id === "call_abc" && output?.call_id === "call_abc");
check("the output follows its call", body.input.indexOf(call) < body.input.indexOf(output));
check("no item id is sent with store false", body.input.every(i => !("id" in i)), raw);
const asst = body.input.find(i => i.role === "assistant");
check("assistant text is output_text without the thinking", asst?.content?.[0]?.type === "output_text"
    && asst.content[0].text === "Checking.", JSON.stringify(asst));
check("the user turn is input_text", body.input[0]?.role === "user" && body.input[0].content[0].type === "input_text");
check("tools are flat", body.tools?.[0]?.type === "function" && body.tools[0].name === "recall"
    && body.tools[0].parameters?.required?.[0] === "query" && !("function" in body.tools[0]), JSON.stringify(body.tools));
const bare = s.buildRequestData({ model: "gpt-5" }, conversation, "sys", 0, [], "");
check("an empty tool list is omitted", bare.tools === undefined);
const legacy = s.buildRequestData({ model: "gpt-5" }, [msg({ role: "tool", functionResponse: "old" })], "sys", 0, [], "");
check("a tool result with no id degrades to a user message", legacy.input[0]?.role === "user", JSON.stringify(legacy.input));

check("a plan model's bearer is read from the token variable",
    s.buildAuthorizationHeader("API_KEY", { auth: "chatgpt" }).includes('"$KOOMPI_CHATGPT_TOKEN"'));
check("a keyed model still uses the key variable",
    s.buildAuthorizationHeader("API_KEY", { requires_key: true }).includes("${API_KEY}"));
check("a keyless model sends no bearer", s.buildAuthorizationHeader("API_KEY", { requires_key: false }) === "");

// --- A recorded stream: reasoning summary, text, one function call, completed.
const ev = o => [`event: ${o.type}`, `data: ${JSON.stringify(o)}`, ""];
const stream = [
    ev({ type: "response.created", response: { id: "resp_1", status: "in_progress" } }),
    ev({ type: "response.output_item.added", output_index: 0, item: { type: "reasoning", id: "rs_1" } }),
    ev({ type: "response.reasoning_summary_text.delta", item_id: "rs_1", output_index: 0, summary_index: 0, delta: "Need memory." }),
    ev({ type: "response.output_item.added", output_index: 1, item: { type: "message", id: "msg_1", role: "assistant" } }),
    ev({ type: "response.output_text.delta", item_id: "msg_1", output_index: 1, content_index: 0, delta: "Let me " }),
    ev({ type: "response.output_text.delta", item_id: "msg_1", output_index: 1, content_index: 0, delta: "check." }),
    ev({ type: "response.output_text.done", item_id: "msg_1", output_index: 1, content_index: 0, text: "Let me check." }),
    ev({ type: "response.output_item.added", output_index: 2, item: { type: "function_call", id: "fc_1", call_id: "call_9", name: "recall", arguments: "" } }),
    ev({ type: "response.function_call_arguments.delta", item_id: "fc_1", output_index: 2, delta: '{"que' }),
    ev({ type: "response.function_call_arguments.delta", item_id: "fc_1", output_index: 2, delta: 'ry":"editor"}' }),
    ev({ type: "response.function_call_arguments.done", item_id: "fc_1", output_index: 2, arguments: '{"query":"editor"}' }),
    ev({ type: "response.output_item.done", output_index: 2, item: { type: "function_call", id: "fc_1", call_id: "call_9", name: "recall", arguments: '{"query":"editor"}' } }),
    ev({ type: "response.completed", response: { id: "resp_1", status: "completed", usage: { input_tokens: 120, output_tokens: 30, total_tokens: 150 } } }),
].flat();

s.reset();
let message = msg({ role: "assistant" });
let results = [];
let finishedBeforeCompleted = false;
for (const line of stream) {
    const r = s.parseResponseLine(line, message);
    if (r?.finished && !line.includes("response.completed")) finishedBeforeCompleted = true;
    results.push(r);
}
const last = results.filter(r => r?.finished).pop();
check("text deltas land in content", message.content.endsWith("Let me check."), JSON.stringify(message.content));
check("text.done does not repeat the text", message.content.split("Let me check.").length === 2, message.content);
check("reasoning lands in a think block", message.rawContent.includes("<think>\n\nNeed memory.\n\n</think>"), message.rawContent);
check("nothing finishes before response.completed", !finishedBeforeCompleted);
check("completed finishes the turn", last?.finished === true);
check("one function call is handed back", last?.functionCalls?.length === 1, JSON.stringify(last));
check("in the OpenAI strategy's shape", last?.functionCall?.name === "recall"
    && last.functionCall.args?.query === "editor" && last.functionCall.id === "call_9", JSON.stringify(last?.functionCall));
check("the assistant turn carries the wire call", message.toolCalls?.[0]?.id === "call_9"
    && message.toolCalls[0].arguments === '{"query":"editor"}', JSON.stringify(message.toolCalls));
check("usage is read", last?.tokenUsage?.input === 120 && last.tokenUsage.output === 30 && last.tokenUsage.total === 150, JSON.stringify(last?.tokenUsage));
check("no stray SSE text in content", !message.content.includes("event:") && !message.content.includes("data:"), message.content);
s.onRequestFinished(message);
check("a completed turn gets no error on exit", !message.content.includes("**Error**"), message.content);

// --- response.failed with the plan's usage limit code.
s.reset();
message = msg({ role: "assistant" });
let r = {};
for (const line of ev({ type: "response.output_text.delta", output_index: 0, delta: "Hel" })) s.parseResponseLine(line, message);
for (const line of ev({ type: "response.failed", response: { status: "failed", error: {
    code: "subscription_sharing_usage_limit_exceeded", message: "Usage limit reached." } } })) {
    r = Object.assign(r, s.parseResponseLine(line, message));
}
check("failed finishes the turn", r.finished === true);
check("failed hands back no tool call", !r.functionCalls);
check("the error code is visible", message.content.includes("subscription_sharing_usage_limit_exceeded"), message.content);
check("the error message is visible", message.content.includes("Usage limit reached."), message.content);

// --- error event, incomplete, and a stream that just stops.
s.reset();
message = msg({ role: "assistant" });
r = s.parseResponseLine("data: " + JSON.stringify({ type: "error", code: "rate_limit_exceeded", message: "Slow down" }), message);
check("an error event finishes with its code", r.finished === true && message.content.includes("rate_limit_exceeded"), message.content);
s.reset();
message = msg({ role: "assistant" });
r = s.parseResponseLine("data: " + JSON.stringify({ type: "response.incomplete", response: { incomplete_details: { reason: "max_output_tokens" } } }), message);
check("incomplete finishes with its reason", r.finished === true && message.content.includes("max_output_tokens"), message.content);
s.reset();
message = msg({ role: "assistant" });
s.parseResponseLine("data: " + JSON.stringify({ type: "response.output_item.done", output_index: 0, item: { type: "function_call", call_id: "c1", name: "recall", arguments: "{}" } }), message);
s.onRequestFinished(message);
check("a stream cut before completed shows an error", message.content.includes("**Error**"), message.content);
check("and dispatches no call", (message.toolCalls ?? []).length === 0, JSON.stringify(message.toolCalls));
s.reset();
message = msg({ role: "assistant" });
s.parseResponseLine('{"error": {"message": "Incorrect API key", "type": "invalid_request_error", "code": "invalid_api_key"}}', message);
check("a plain JSON error body shows its code", message.content.includes("invalid_api_key"), message.content);

if (process.env.SHOW_BODY === "1") console.log(JSON.stringify(body, null, 2));
if (failedChecks > 0) { console.error(`${failedChecks} check(s) failed`); process.exit(1); }
console.log("ok: responses api wire format and stream");
EOF

cd "$tmp" && bun run run.mjs "$STRATEGY" "$REGISTRY"
