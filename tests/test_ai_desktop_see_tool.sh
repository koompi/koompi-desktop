#!/usr/bin/env bash
# `see` end to end, and who gets the screenshot (M7, plan D8): the real engine
# (scripts/ai/headless.sh inside a nested Hyprland, tests/with-nested-hyprland.sh) drives
# DesktopService and desktop.py against two fixture GTK windows, one with no accessibility tree,
# under a fake model on 127.0.0.1. The fake model cannot look, so it checks what a model would
# be sent: whether an image part arrived, in which turn and format, and that it is a JPEG of the
# right size. It answers with a mark from the refs in the text, as the model names a mark it saw.
#
#   E  a local model: see sends the screenshot as an image part in a user turn right after the
#      tool result, no consent asked; act on the mark over "Add one" asks (a click by pixels,
#      the card carries the screenshot) and, approved, the app is clicked
#   F  a model on another host, consent refused: the card names the provider, no screenshot is
#      taken and no request carries an image
#   G  the same host, consent given (Mistral's wire format): one card for the chat, two sees, the
#      image goes; the click happens
#   H  policies.ai == 2: the remote model is not offered at all, so it is sent nothing
#
# "Another host" is http://127.1:PORT: curl reaches 127.0.0.1, while the shell's isLocal (only
# localhost, 127.0.0.1 and [::1]) takes it for a remote provider. Nothing leaves 127.0.0.1.
# Never touches the real session: the nested compositor is named explicitly and the inherited
# HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY are unset. Prints skip: without Hyprland, KWin,
# qs, grim, wtype, jq, Atspi or Pillow.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NESTED="$REPO_ROOT/tests/with-nested-hyprland.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
for tool in Hyprland hyprctl kwin_wayland dbus-run-session qs grim wtype jq gdbus curl; do
    command -v "$tool" > /dev/null || { echo "skip: $tool not installed"; exit 0; }
done
python3 -c 'import gi; gi.require_version("Atspi", "2.0"); gi.require_version("Gtk", "3.0"); from gi.repository import Atspi, Gtk' 2> /dev/null \
    || { echo "skip: python-gobject with Atspi and GTK 3 not installed"; exit 0; }
python3 -c 'import PIL' 2> /dev/null || { echo "skip: python-pillow not installed"; exit 0; }
[[ -x /usr/lib/at-spi-bus-launcher && -x /usr/lib/at-spi2-registryd ]] || { echo "skip: at-spi2-core not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/server.py" <<'PY'
# The fake model on POST .../chat/completions (OpenAI and Mistral stream alike). Each request is
# logged as a summary: its roles, and every image part found, decoded. A step is a call or text;
# refLabel puts in the ref of the newest tool line showing that quoted label, markNear [x, y] the
# ref of the newest "region at x,y" mark nearest that point.
import base64, http.server, io, json, re, sys, time
from PIL import Image
port_file, requests_log, script_file = sys.argv[1:4]
script = json.load(open(script_file))
served = [0]

def tool_texts(messages):
    return [str(m.get("content") or "") for m in reversed(messages) if m.get("role") == "tool"]

def ref_for(label, messages):
    for text in tool_texts(messages):
        found = re.search(r'\[(\d+)\][^\n]*"' + re.escape(label) + '"', text)
        if found:
            return int(found.group(1))
    return 9999

def mark_near(point, messages):
    for text in tool_texts(messages):
        marks = [(int(n), int(x), int(y)) for n, x, y in re.findall(r"\[(\d+)\] region at (\d+),(\d+)", text)]
        if marks:
            return min(marks, key=lambda m: abs(m[2] - point[1]) + abs(m[1] - point[0]) / 10)[0]
    return 9999

def images(messages):
    found = []
    for i, m in enumerate(messages):
        parts = m.get("content") if isinstance(m.get("content"), list) else []
        for p in parts:
            if p.get("type") != "image_url":
                continue
            url = p["image_url"]["url"] if isinstance(p["image_url"], dict) else p["image_url"]
            entry = {"at": i, "role": m.get("role"), "after": messages[i - 1].get("role") if i else "",
                     "shape": "object" if isinstance(p["image_url"], dict) else "string"}
            head, _, data = url.partition(",")
            entry["head"] = head
            try:
                raw = base64.b64decode(data, validate=True)
                entry["jpeg"] = raw[:3] == b"\xff\xd8\xff"
                entry["size"] = list(Image.open(io.BytesIO(raw)).size)
            except Exception as e:
                entry["error"] = str(e)[:120]
            found.append(entry)
    return found

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.loads(raw)
        messages = body.get("messages", [])
        with open(requests_log, "a") as log:
            log.write(json.dumps({"bytes": len(raw), "roles": [m.get("role") for m in messages],
                                  "images": images(messages), "placeholder": b"@@KOOMPI_SCREEN" in raw}) + "\n")
        step = script[min(served[0], len(script) - 1)]
        served[0] += 1
        if "call" in step:
            args = dict(step.get("args", {}))
            if "refLabel" in step:
                args["ref"] = ref_for(step["refLabel"], messages)
            if "markNear" in step:
                args["ref"] = mark_near(step["markNear"], messages)
            chunk = {"choices": [{"index": 0, "finish_reason": None, "delta": {"tool_calls": [
                {"index": 0, "id": f"call{served[0]}", "type": "function",
                 "function": {"name": step["call"], "arguments": json.dumps(args)}}]}}]}
            end = "tool_calls"
        else:
            chunk = {"choices": [{"index": 0, "finish_reason": None, "delta": {"content": step["text"]}}]}
            end = "stop"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        for c in (chunk, {"choices": [{"index": 0, "delta": {}, "finish_reason": end}]}):
            self.wfile.write(f"data: {json.dumps(c)}\n\n".encode())
        self.wfile.write(b"data: [DONE]\n\n")

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
open(port_file, "w").write(str(server.server_address[1]))
server.serve_forever()
PY

# the "Add one" button's label in the plain fixture: about 474,40 in the window
cat > "$tmp/e.script.json" <<'JSON'
[{"call": "desktop", "args": {"op": "windows"}},
 {"call": "desktop", "args": {"op": "see"}, "refLabel": "Plain fixture"},
 {"call": "desktop", "args": {"op": "act"}, "markNear": [474, 40]},
 {"text": "DONE-E"}]
JSON
cat > "$tmp/f.script.json" <<'JSON'
[{"call": "desktop", "args": {"op": "windows"}},
 {"call": "desktop", "args": {"op": "see"}, "refLabel": "Plain fixture"},
 {"text": "DONE-F"}]
JSON
cat > "$tmp/g.script.json" <<'JSON'
[{"call": "desktop", "args": {"op": "windows"}},
 {"call": "desktop", "args": {"op": "see"}, "refLabel": "Plain fixture"},
 {"call": "desktop", "args": {"op": "see"}},
 {"call": "desktop", "args": {"op": "act"}, "markNear": [474, 40]},
 {"text": "DONE-G"}]
JSON

cat > "$tmp/inner.sh" <<'SH'
set -uo pipefail
work=$1 repo=$2
source "$repo/tests/ai-desktop-session.sh"
ai_desktop_guard || exit 1
export PATH="$repo/dots/.local/bin:$PATH"
headless="$repo/dots/.config/quickshell/koompi/scripts/ai/headless.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
ai_desktop_a11y_start || exit 1
ai_desktop_fixture desktop.fixture "Desktop fixture" "$work/app.log" || exit 1
NO_AT_BRIDGE=1 ai_desktop_fixture plain.fixture "Plain fixture" "$work/plain.log" || exit 1

mkdir -p "$XDG_STATE_HOME/quickshell/user" "$XDG_CONFIG_HOME/koompi" "$work/bin"
echo greeted > "$XDG_STATE_HOME/quickshell/user/first_run.txt"
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/bin/koompi-shelld"
chmod +x "$work/bin/koompi-shelld"
export KOOMPI_SHELLD="$work/bin/koompi-shelld" KOOMPI_AI_HEADLESS_KEEP_ENV=1 KOOMPI_AI_HEADLESS_DISPLAY="$WAYLAND_DISPLAY"

server_pid=""
start_server() { # start_server SCRIPT
    [[ -n $server_pid ]] && kill "$server_pid" 2> /dev/null
    rm -f "$work/port" "$work/requests.jsonl"
    python3 -I "$work/server.py" "$work/port" "$work/requests.jsonl" "$1" &
    server_pid=$!
    for _ in $(seq 1 50); do [[ -s $work/port ]] && break; sleep 0.1; done
    [[ -s $work/port ]] || fail "the fake model did not start"
    port=$(cat "$work/port")
}
# run_case NAME HOST FORMAT POLICY APPROVALS [TIMEOUT]
run_case() {
    local name=$1 host=$2 format=$3 policy=$4 approvals=$5 timeout=${6:-90}
    jq -n --arg url "http://$host:$port/v1/chat/completions" --arg format "$format" --argjson policy "$policy" \
        '{ai: {tool: "functions", restoreSession: false, memory: {enable: false}, approvals: {shellRules: [], agent: false},
        extraModels: [{model: "fake-llm", name: "Fake Vision", endpoint: $url, api_format: $format, requires_key: false,
                       toolBlockByteLimit: 1461}]},
        policies: {ai: $policy}}' > "$XDG_CONFIG_HOME/koompi/config.json"
    jq -n --arg turn "Click Add one in the plain fixture" --argjson approvals "$approvals" --argjson t "$timeout" \
        '{model: "fake-llm", turns: [$turn], approvals: $approvals, timeoutSec: $t}' > "$work/$name.json"
    bash "$headless" "$work/$name.json" "$work/$name.out.json"
}
cards() { # the cards a run showed: [{summary, consent, image}]
    jq -c '[.messages[] | select(.functionCall.name? == "desktop" and .functionCall.summary? != null)
        | {summary: .functionCall.summary, consent: (.functionCall.consent // ""), image: (.functionCall.image // "")}]' "$1"
}

# --- E: the local model
start_server "$work/e.script.json"
run_case e 127.0.0.1 openai 1 '{"desktop": "approve"}' || fail "E: headless exited $?: $(tail -30 "$work/e.out.log")"
out="$work/e.out.json"
grep -qx "CLICKED 1" "$work/plain.log" || fail "E: the click on the mark did not reach the app: $(cat "$work/plain.log"; cards "$out")"
[[ $(wc -l < "$work/requests.jsonl") -eq 4 ]] || fail "E: expected 4 requests, got $(wc -l < "$work/requests.jsonl")"
jq -se '.[0].images == [] and .[1].images == []' "$work/requests.jsonl" > /dev/null \
    || fail "E: an image went out before any see"
jq -se '.[2].images | length == 1 and (.[0] | .role == "user" and .after == "tool" and .shape == "object"
    and .head == "data:image/jpeg;base64" and .jpeg and .size[0] <= 1600 and .size[1] <= 1000 and .size[1] > 0)' "$work/requests.jsonl" > /dev/null \
    || fail "E: the screenshot did not arrive as one JPEG image part in a user turn after the tool result: $(sed -n 3p "$work/requests.jsonl")"
jq -se 'all(.[]; .placeholder == false)' "$work/requests.jsonl" > /dev/null || fail "E: a placeholder reached the model unfilled"
jq -e '[.[] | select(.consent != "")] == []' <<< "$(cards "$out")" > /dev/null || fail "E: the local model was asked for consent: $(cards "$out")"
jq -e 'length == 1 and (.[0].summary | test("^click \\[[0-9]+\\] region at [0-9]+,[0-9]+ in \"Plain fixture\"$"))
    and (.[0].image | test("/screens/see-[0-9]+\\.jpg$"))' <<< "$(cards "$out")" > /dev/null \
    || fail "E: expected one card, for the click, carrying the screenshot: $(cards "$out")"
jq -e '.messages | any(.role == "tool" and (.functionResponse | test("The image follows this text")))' "$out" > /dev/null \
    || fail "E: the see result did not say an image follows"
jq -e '[.requests[].body | tojson | test("base64,[A-Za-z0-9+/]{100}")] | any | not' "$out" > /dev/null \
    || fail "E: image bytes passed through the shell's own copy of the request"
echo "  ok: E  a local model gets the screenshot as an image part after the tool result; the click by mark asks, then lands"

# --- F: another host, consent refused
start_server "$work/f.script.json"
run_case f 127.1 openai 1 '{}' || fail "F: headless exited $?: $(tail -30 "$work/f.out.log")"
out="$work/f.out.json"
jq -se 'length == 3 and all(.[]; .images == [] and .placeholder == false)' "$work/requests.jsonl" > /dev/null \
    || fail "F: an image reached a model with no consent: $(cat "$work/requests.jsonl")"
jq -e 'length == 1 and .[0].consent == "Fake Vision (127.1)"' <<< "$(cards "$out")" > /dev/null \
    || fail "F: expected one consent card naming the provider: $(cards "$out")"
jq -e '.messages | any(.role == "tool" and .functionName == "desktop" and (.functionResponse | test("rejected"; "i")))' "$out" > /dev/null \
    || fail "F: the refusal did not reach the transcript: $(jq -c '[.messages[] | select(.role == "tool") | .functionResponse[0:160]]' "$out")"
[[ $(grep -c CLICKED "$work/plain.log") -eq 1 ]] || fail "F: something was clicked"
echo "  ok: F  a remote model without consent: one card naming it, no screenshot sent"

# --- G: the same host, consent given, in Mistral's format
start_server "$work/g.script.json"
run_case g 127.1 mistral 1 '{"desktop": "approve"}' || fail "G: headless exited $?: $(tail -30 "$work/g.out.log")"
out="$work/g.out.json"
jq -e '[.[] | select(.consent != "")] | length == 1 and .[0].consent == "Fake Vision (127.1)"' <<< "$(cards "$out")" > /dev/null \
    || fail "G: expected one consent card for the chat, not one per see: $(cards "$out")"
jq -se '.[2].images | length == 1 and (.[0] | .shape == "string" and .role == "user" and .after == "tool" and .jpeg)' "$work/requests.jsonl" > /dev/null \
    || fail "G: the consented screenshot did not arrive in Mistral's shape: $(sed -n 3p "$work/requests.jsonl")"
jq -se '.[3].images | length == 1' "$work/requests.jsonl" > /dev/null || fail "G: the second see's screenshot did not go"
jq -se 'all(.[]; (.images | length) <= 1)' "$work/requests.jsonl" > /dev/null || fail "G: an older screenshot was resent"
grep -qx "CLICKED 2" "$work/plain.log" || fail "G: the click did not happen: $(cat "$work/plain.log")"
echo "  ok: G  consent given once in the chat: both screenshots go, as Mistral's image_url, and the click lands"

# --- H: policies.ai == 2
start_server "$work/f.script.json"
run_case h 127.1 openai 2 '{"desktop": "approve"}' 12
[[ ! -s $work/requests.jsonl ]] || fail "H: a remote model was sent something under policies.ai == 2: $(cat "$work/requests.jsonl")"
jq -e '.ok == false and (.error | test("timeout"))' "$work/h.out.json" > /dev/null \
    || fail "H: the remote model was offered under policies.ai == 2: $(jq -c '{ok, error}' "$work/h.out.json")"
echo "  ok: H  policies.ai == 2: the remote model is not offered, and is sent nothing"
kill "$server_pid" 2> /dev/null
exit 0
SH

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY bash "$NESTED" bash "$tmp/inner.sh" "$tmp" "$REPO_ROOT"
rc=$?
[[ $rc -eq 77 ]] && { echo "skip: the nested Hyprland could not start here"; exit 0; }
[[ $rc -eq 0 ]] || fail "see end to end (exit $rc)"
echo "ok: see end to end: the screenshot goes only where it may, and the model's mark is clicked"
