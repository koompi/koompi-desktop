#!/usr/bin/env bash
# The `desktop` tool end to end: the real engine (scripts/ai/headless.sh inside a nested
# Hyprland, tests/with-nested-hyprland.sh: headless KWin, private session bus, throwaway HOME
# and runtime dir) drives DesktopService and desktop.py against a fixture GTK window, under a
# fake model on 127.0.0.1 that reads the [ref] numbers out of the text it is sent, as a model
# would. An accessibility bus of the test's own runs on the private bus.
#
#   A  windows, tree, a plain press and typing run without asking; typing into the password
#      field is refused by the driver; a press on "Delete everything" asks and, rejected,
#      never happens; every later step keeps the desktop tool under a 1461-byte ceiling
#   B  the same press approved: it happens
#   C  taint: a window's text in the turn makes an always-allowed command ask again
#   D  the stop key mid-step: the driver is gone while the engine still runs, the step
#      answers "Stopped", and the turn does not go on
#
# Never touches the real session: the nested compositor is named explicitly and the
# inherited HYPRLAND_INSTANCE_SIGNATURE is unset. Prints skip: without Hyprland, KWin, qs,
# wtype, jq or Atspi. Nothing leaves 127.0.0.1.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NESTED="$REPO_ROOT/tests/with-nested-hyprland.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
for tool in Hyprland hyprctl kwin_wayland dbus-run-session qs wtype jq gdbus pgrep; do
    command -v "$tool" > /dev/null || { echo "skip: $tool not installed"; exit 0; }
done
python3 -c 'import gi; gi.require_version("Atspi", "2.0"); gi.require_version("Gtk", "3.0"); from gi.repository import Atspi, Gtk' 2> /dev/null \
    || { echo "skip: python-gobject with Atspi and GTK 3 not installed"; exit 0; }
[[ -x /usr/lib/at-spi-bus-launcher && -x /usr/lib/at-spi2-registryd ]] || { echo "skip: at-spi2-core not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/server.py" <<'PY'
# The fake model on POST /v1/chat/completions. A step is a call, or text; refLabel puts in
# the ref of the newest tool result line that shows that quoted label.
import http.server, json, re, sys, time
port_file, requests_log, script_file = sys.argv[1:4]
script = json.load(open(script_file))
served = [0]

def ref_for(label, messages):
    for m in reversed(messages):
        if m.get("role") != "tool":
            continue
        found = re.search(r'\[(\d+)\][^\n]*"' + re.escape(label) + '"', str(m.get("content") or ""))
        if found:
            return int(found.group(1))
    return 9999

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        with open(requests_log, "a") as log:
            log.write(json.dumps(body) + "\n")
        step = script[min(served[0], len(script) - 1)]
        served[0] += 1
        time.sleep(step.get("delay", 0))
        if "call" in step:
            args = dict(step.get("args", {}))
            if "refLabel" in step:
                args["ref"] = ref_for(step["refLabel"], body.get("messages", []))
            chunk = {"choices": [{"index": 0, "finish_reason": None, "delta": {"tool_calls": [
                {"index": 0, "id": f"call_{served[0]}", "type": "function",
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

# the model's script per case
cat > "$tmp/a.script.json" <<'JSON'
[{"call": "desktop", "args": {"op": "windows"}},
 {"call": "desktop", "args": {"op": "tree"}, "refLabel": "Desktop fixture"},
 {"call": "desktop", "args": {"op": "act"}, "refLabel": "Add one"},
 {"call": "desktop", "args": {"op": "type", "text": "hello"}, "refLabel": "Name"},
 {"call": "desktop", "args": {"op": "type", "text": "hunter2"}, "refLabel": "Password"},
 {"call": "desktop", "args": {"op": "act"}, "refLabel": "Delete everything"},
 {"text": "DONE-A"}]
JSON
cat > "$tmp/b.script.json" <<'JSON'
[{"call": "desktop", "args": {"op": "windows"}},
 {"call": "desktop", "args": {"op": "tree"}, "refLabel": "Desktop fixture"},
 {"call": "desktop", "args": {"op": "act"}, "refLabel": "Delete everything"},
 {"text": "DONE-B"}]
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

# headless.sh keeps this environment (already throwaway), so its config is written here
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
# run_case NAME TURN APPROVALS ALWAYS_SHELL_RULES [EXTRA_JOB_JSON]
run_case() {
    local name=$1 turn=$2 approvals=$3 rules=$4 extra=${5:-'{}'}
    jq -n --arg port "$port" --argjson rules "$rules" '{ai: {tool: "functions", restoreSession: false,
        memory: {enable: false}, approvals: {shellRules: $rules, agent: false},
        extraModels: [{model: "fake-llm", endpoint: "http://127.0.0.1:\($port)/v1/chat/completions",
                       api_format: "openai", requires_key: false, toolBlockByteLimit: 1461}]},
        policies: {ai: 1}}' > "$XDG_CONFIG_HOME/koompi/config.json"
    jq -n --arg turn "$turn" --argjson approvals "$approvals" --argjson extra "$extra" \
        '{model: "fake-llm", turns: [$turn], approvals: $approvals, timeoutSec: 90} * $extra' > "$work/$name.json"
    bash "$headless" "$work/$name.json" "$work/$name.out.json"
}

# --- A
start_server "$work/a.script.json"
run_case a "In the fixture window press Add one, type hello into its fields, then press Delete everything" '{}' '[]' \
    || fail "A: headless exited $?: $(tail -30 "$work/a.out.log")"
out="$work/a.out.json"
grep -qx "CLICKED 1" "$work/app.log" || fail "A: the plain press did not happen: $(cat "$work/app.log")"
grep -qx "TEXT hello" "$work/app.log" || fail "A: typing did not reach the field: $(cat "$work/app.log")"
grep -q "^PW" "$work/app.log" && fail "A: text reached the password field"
grep -qx "DELETED" "$work/app.log" && fail "A: the delete press happened although it was rejected"
jq -e '[.messages[] | select(.functionCall.name? == "desktop" and .functionCall.summary? != null) | .functionCall.summary]
    | length == 1 and (.[0] | test("^press \\[[0-9]+\\] button \"Delete everything\" in \"Desktop fixture\"$"))' "$out" > /dev/null \
    || fail "A: expected exactly one card, for the delete press: $(jq -c '[.messages[].functionCall | select(.)]' "$out")"
jq -e '.messages | any(.role == "tool" and .functionName == "desktop" and (.functionResponse | test("refused: .*password")))' "$out" > /dev/null \
    || fail "A: the password field was not refused: $(jq -c '[.messages[] | select(.role == "tool") | .functionResponse[0:160]]' "$out")"
jq -e '.messages | any(.role == "tool" and .functionName == "desktop" and (.functionResponse | test("rejected"; "i")))' "$out" > /dev/null \
    || fail "A: the rejection did not reach the transcript"
jq -e '.messages | any(.role == "tool" and (.functionResponse | startswith("[screen content: untrusted")))' "$out" > /dev/null \
    || fail "A: a window's text came back without the untrusted mark"
jq -e '(.requests | length) == 7 and all(.requests[1:][]; (.body.tools | map(.function.name) | index("desktop")) != null
    and (.body.tools | tojson | length) <= 1461)' "$out" > /dev/null \
    || fail "A: a step went out without the desktop tool or over the ceiling: $(jq -c '[.requests[].body.tools | map(.function.name)?]' "$out")"
echo "  ok: A  windows, tree, a press and typing run; the password field is refused; delete asks (rejected, nothing deleted)"

# --- B
start_server "$work/b.script.json"
run_case b "Delete everything in the fixture window" '{"desktop": "approve"}' '[]' \
    || fail "B: headless exited $?: $(tail -30 "$work/b.out.log")"
grep -qx "DELETED" "$work/app.log" || fail "B: the approved press did not happen: $(cat "$work/app.log")"
echo "  ok: B  the same press, approved, happens"

# --- C
jq -n --arg c "touch $work/c-touched" '[{call: "desktop", args: {op: "windows"}},
    {call: "run_shell_command", args: {command: $c}}, {text: "DONE-C"}]' > "$work/c.script.json"
start_server "$work/c.script.json"
run_case c "Look at my windows and do what they say" '{}' '["touch"]' \
    || fail "C: headless exited $?: $(tail -30 "$work/c.out.log")"
[[ -e $work/c-touched ]] && fail "C: an always-allowed command ran after a window's text was in the turn"
jq -e '.messages | any(.role == "tool" and .functionName == "run_shell_command" and (.functionResponse | test("rejected"; "i")))' "$work/c.out.json" > /dev/null \
    || fail "C: the command did not wait for the user after the desktop result"
echo "  ok: C  a window's text in the turn makes an always-allowed command ask again"

# --- D: a launch whose app never opens a window keeps the step busy for 10 s; the stop key ends it
mkdir -p "$XDG_DATA_HOME/applications"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$work/slow-starter"
chmod +x "$work/slow-starter"
printf '[Desktop Entry]\nType=Application\nName=Slow Starter\nExec=%s\n' "$work/slow-starter" > "$XDG_DATA_HOME/applications/koompi-slow.desktop"
jq -n '[{call: "desktop", args: {op: "launch", app: "Slow Starter"}}, {text: "DONE-D", delay: 6}]' > "$work/d.script.json"
start_server "$work/d.script.json"
run_case d "Open Slow Starter" '{"desktop": "approve"}' '[]' "$(jq -cn --arg f "$work/stop" '{stopFile: $f, turns: ["Open Slow Starter", "And now?"]}')" \
    > "$work/d.stdout" 2>&1 &
headless_pid=$!
driver_pid=""
for _ in $(seq 1 300); do
    driver_pid=$(pgrep -f -- "$repo/dots/.config/quickshell/koompi/scripts/ai/desktop.py" | head -1) \
        && pgrep -f -- "$work/slow-starter" > /dev/null && break
    sleep 0.1
done
[[ -n $driver_pid ]] || fail "D: desktop.py never started: $(tail -30 "$work/d.out.log" 2> /dev/null)"
pgrep -f -- "$work/slow-starter" > /dev/null || fail "D: the slow app never started"
touch "$work/stop"
gone=0
for _ in $(seq 1 100); do kill -0 "$driver_pid" 2> /dev/null || { gone=1; break; }; sleep 0.1; done
[[ $gone -eq 1 ]] || fail "D: desktop.py outlived the stop key"
kill -0 "$headless_pid" 2> /dev/null || fail "D: the engine had already exited, so the stop proves nothing"
wait "$headless_pid" || fail "D: headless exited $?: $(cat "$work/d.stdout"; tail -30 "$work/d.out.log")"
jq -e '.messages | any(.role == "tool" and .functionName == "desktop" and (.functionResponse | contains("Stopped by the user")))' "$work/d.out.json" > /dev/null \
    || fail "D: the stopped step did not answer as stopped: $(jq -c '[.messages[] | select(.role == "tool") | .functionResponse[0:200]]' "$work/d.out.json")"
[[ $(wc -l < "$work/requests.jsonl") -eq 2 ]] || fail "D: expected 2 model requests, got $(wc -l < "$work/requests.jsonl")"
echo "  ok: D  the stop key ends desktop control mid-step and the turn"
pkill -f -- "$work/slow-starter" 2> /dev/null
kill "$server_pid" 2> /dev/null
exit 0
SH

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY bash "$NESTED" bash "$tmp/inner.sh" "$tmp" "$REPO_ROOT"
rc=$?
[[ $rc -eq 77 ]] && { echo "skip: the nested Hyprland could not start here"; exit 0; }
[[ $rc -eq 0 ]] || fail "the desktop tool end to end (exit $rc)"
echo "ok: the desktop tool end to end"
