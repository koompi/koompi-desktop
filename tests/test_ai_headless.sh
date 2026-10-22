#!/usr/bin/env bash
# scripts/ai/headless.sh runs the real engine with no surfaces against a fake
# OpenAI-compatible server on loopback: a tool round trip reaches the transcript,
# the prompt-dir override is what the model receives, and a tool that asks for
# approval runs only when the job approves it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
HEADLESS="$SHELL_ROOT/scripts/ai/headless.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
for tool in qs kwin_wayland dbus-run-session python3 jq; do
    command -v "$tool" > /dev/null || { echo "skip: $tool not installed"; exit 0; }
done
[[ -x $HEADLESS || -f $HEADLESS ]] || fail "missing $HEADLESS"

tmp="$(mktemp -d)"
server_pid=""
trap '[[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null; rm -rf "$tmp"' EXIT

cat > "$tmp/fake.py" <<'PY'
import http.server, json, sys
log, script = open(sys.argv[2], "a"), json.load(open(sys.argv[3]))
served = [0]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        self.send_response(404); self.end_headers()
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        log.write(json.dumps(body) + "\n"); log.flush()
        reply = script[min(served[0], len(script) - 1)]; served[0] += 1
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        for chunk in reply:
            self.wfile.write(f"data: {chunk if isinstance(chunk, str) else json.dumps(chunk)}\n\n".encode())
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
open(sys.argv[1], "w").write(str(server.server_address[1]))
server.serve_forever()
PY

# start_server SCRIPT.json: a fresh fake server and request log
start_server() {
    [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null
    rm -f "$tmp/port" "$tmp/requests.jsonl"
    python3 -I "$tmp/fake.py" "$tmp/port" "$tmp/requests.jsonl" "$1" &
    server_pid=$!
    for _ in $(seq 1 50); do [[ -s $tmp/port ]] && break; sleep 0.1; done
    [[ -s $tmp/port ]] || fail "fake server did not start"
}

# write_job FILE TURN APPROVALS_JSON
write_job() {
    jq -n --arg port "$(cat "$tmp/port")" --arg turn "$2" --argjson approvals "$3" --arg dir "$tmp/prompts" '{
        model: { model: "fake-llm", endpoint: "http://127.0.0.1:\($port)/v1/chat/completions",
                 api_format: "openai", requires_key: false },
        turns: [$turn], approvals: $approvals, promptDir: $dir, timeoutSec: 60 }' > "$1"
}

tool_call() {
    jq -cn --arg name "$1" --arg args "$2" '{choices: [{index: 0, finish_reason: null, delta: {tool_calls: [
        {index: 0, id: "call_1", type: "function", function: {name: $name, arguments: $args}}]}}]}'
}
final_text() {
    jq -cn --arg text "$1" '{choices: [{index: 0, finish_reason: null, delta: {content: $text}}]}'
}

mkdir -p "$tmp/prompts"
cp "$SHELL_ROOT"/defaults/ai/prompts/system/*.md "$tmp/prompts/"
echo "PROMPT-DIR-MARKER-7731" >> "$tmp/prompts/00-identity.md"

# --- a read-only tool round trip, under the override prompt

jq -n --argjson call "$(tool_call get_shell_config '{}')" --argjson text "$(final_text 'HEADLESS-ANSWER-1')" '[
    [$call, {choices: [{index: 0, delta: {}, finish_reason: "tool_calls"}]}, "[DONE]"],
    [$text, {choices: [{index: 0, delta: {}, finish_reason: "stop"}]}, "[DONE]"]
]' > "$tmp/script1.json"
start_server "$tmp/script1.json"
write_job "$tmp/job1.json" "Where is my bar?" '{}'
bash "$HEADLESS" "$tmp/job1.json" "$tmp/out1.json" || fail "headless run 1 exited $?: $(tail -20 "$tmp/out1.log")"

[[ $(wc -l < "$tmp/requests.jsonl") -eq 2 ]] || fail "expected 2 requests, got $(wc -l < "$tmp/requests.jsonl")"
jq -e '.messages[0].content | contains("PROMPT-DIR-MARKER-7731")' <(head -1 "$tmp/requests.jsonl") > /dev/null \
    || fail "the first request's system message lacks the override prompt"
jq -e '[.messages[] | select(.role == "tool")] | length == 1' <(sed -n 2p "$tmp/requests.jsonl") > /dev/null \
    || fail "the second request does not carry the tool result"
jq -e '.ok and (.messages | any(.functionName == "get_shell_config" or (.functionCall.name // "") == "get_shell_config"))' "$tmp/out1.json" > /dev/null \
    || fail "the transcript lacks the get_shell_config call"
jq -e '.messages | any(.role == "assistant" and (.content | contains("HEADLESS-ANSWER-1")))' "$tmp/out1.json" > /dev/null \
    || fail "the transcript lacks the final answer"
jq -e '(.requests | length) == 2 and (.requests[0].body.messages[0].content | contains("PROMPT-DIR-MARKER-7731"))' "$tmp/out1.json" > /dev/null \
    || fail "the transcript's captured request bodies do not match what the server saw"
echo "  ok: tool round trip, override prompt sent and recorded"

# --- a tool that asks: rejected unless the job approves it

marker="$tmp/ran-$$"
jq -n --argjson call "$(tool_call run_shell_command "$(jq -cn --arg c "touch $marker" '{command: $c}')")" \
    --argjson text "$(final_text 'HEADLESS-ANSWER-2')" '[
    [$call, {choices: [{index: 0, delta: {}, finish_reason: "tool_calls"}]}, "[DONE]"],
    [$text, {choices: [{index: 0, delta: {}, finish_reason: "stop"}]}, "[DONE]"]
]' > "$tmp/script2.json"

start_server "$tmp/script2.json"
write_job "$tmp/job2.json" "Touch the file." '{}'
bash "$HEADLESS" "$tmp/job2.json" "$tmp/out2.json" || fail "headless run 2 exited $?: $(tail -20 "$tmp/out2.log")"
[[ -e $marker ]] && fail "run_shell_command ran without approval"
jq -e '.messages | any(.role == "tool" and (.functionResponse | test("rejected"; "i")))' "$tmp/out2.json" > /dev/null \
    || fail "the rejection did not reach the transcript"
echo "  ok: an unapproved command is rejected and the model is told"

start_server "$tmp/script2.json"
write_job "$tmp/job3.json" "Touch the file." '{"run_shell_command": "approve"}'
bash "$HEADLESS" "$tmp/job3.json" "$tmp/out3.json" || fail "headless run 3 exited $?: $(tail -20 "$tmp/out3.log")"
[[ -e $marker ]] || fail "run_shell_command did not run when the job approved it"
echo "  ok: an approved command runs"

# --- a stubbed tool answers with the job's text and never runs, approved or not

rm -f "$marker"
start_server "$tmp/script2.json"
write_job "$tmp/job4.json" "Touch the file." '{"run_shell_command": "approve"}'
jq '.stubs = {run_shell_command: "STUB-OUTPUT-5521"}' "$tmp/job4.json" > "$tmp/job4s.json"
bash "$HEADLESS" "$tmp/job4s.json" "$tmp/out4.json" || fail "headless run 4 exited $?: $(tail -20 "$tmp/out4.log")"
[[ -e $marker ]] && fail "a stubbed run_shell_command ran"
jq -e '[.messages[] | select(.role == "tool")] | any(.content | contains("STUB-OUTPUT-5521"))' <(sed -n 2p "$tmp/requests.jsonl") > /dev/null \
    || fail "the stub's text did not reach the model"
echo "  ok: a stubbed tool answers with the job's text and does not run"
