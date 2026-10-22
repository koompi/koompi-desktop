#!/usr/bin/env bash
# Everything the assistant hands to a shell carries the conversation: the request
# body, the summariser's script, an attached screenshot. All three used to land in
# /tmp/quickshell/ai, which on a default umask is world-readable, and a 36 KB
# compact.sh holding a real conversation was found there at 0644 while this was
# being written. A screen grab and a clipboard decode are no less private, and
# they were still in /tmp/quickshell/media a leak later. Nothing the shell writes
# belongs under a prefix another uid can read, or squat before the shell boots.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { echo "$1" >&2; exit 1; }

[[ -d "$SHELL_ROOT" ]] || fail "missing $SHELL_ROOT"

# No path under the shell's own /tmp prefix, anywhere. A comment naming it is how
# the two fixes explain themselves, so only code counts.
offenders="$(grep -rn '/tmp/quickshell' "$SHELL_ROOT" 2>/dev/null \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*//' \
    | grep -v '^[^:]*:[0-9]*:[[:space:]]*#')"
if [[ -n "$offenders" ]]; then
    echo "the shell writes into shared /tmp:" >&2
    echo "$offenders" >&2
    exit 1
fi

# The two script paths derive from XDG_RUNTIME_DIR, which systemd creates at 0700.
grep -q 'Quickshell.env("XDG_RUNTIME_DIR")' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "Requester.qml no longer derives its script directory from XDG_RUNTIME_DIR"
grep -q 'requester.scriptDirPath' "$SHELL_ROOT/services/ai/Conversation.qml" \
    || fail "the compactor script no longer sits beside the request body"
grep -q 'Quickshell.env("XDG_RUNTIME_DIR")' "$SHELL_ROOT/modules/common/Directories.qml" \
    || fail "Directories.aiAttach no longer derives from XDG_RUNTIME_DIR"

# curl reads the script through a wrapper that narrows it first, because the file
# exists between setText and exec whatever the directory permits.
for file in services/ai/Requester.qml services/ai/Conversation.qml; do
    grep -q 'chmod 600' "$SHELL_ROOT/$file" \
        || fail "$file runs its script without chmodding it to 0600 first"
done

# The directories are created narrow rather than left to the login umask.
grep -q '"mkdir", "-p", "-m", "700"' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "the request script directory is no longer created at 0700"
# attach sits under the shared ai dir, so its parent is the one that has to be
# narrow: -m would mode the leaf and leave the parent at 755.
grep -q "umask 077; mkdir -p '\${aiAttach}' && chmod 700 '\${aiRuntime}'" \
    "$SHELL_ROOT/modules/common/Directories.qml" \
    || fail "the attachment directory's parent is no longer created and repaired at 0700"

# Screen grabs, clipboard decodes and downloaded images share one runtime root, so
# one binding decides whether any of them can be read by another uid.
grep -q 'runtimeMedia' "$SHELL_ROOT/modules/common/Directories.qml" \
    || fail "Directories no longer routes its media temp dirs through runtimeMedia"
for prop in tempImages cliphistDecode screenshotTemp; do
    grep -qE "property string $prop: \`\\\$\{Directories.runtimeMedia\}" \
        "$SHELL_ROOT/modules/common/Directories.qml" \
        || fail "Directories.$prop no longer derives from runtimeMedia"
done

# mkdir -p -m applies the mode to the leaf only, so the creators that can win the
# race to make the shared parent set a umask instead.
for file in modules/common/utils/TempScreenshotProcess.qml \
            modules/common/models/gCloud/GCloudVision.qml \
            modules/common/Directories.qml \
            scripts/ai/gemini-categorize-wallpaper.sh; do
    grep -q 'umask 077' "$SHELL_ROOT/$file" \
        || fail "$file creates a media directory without narrowing the umask first"
done

# The API key rides in the environment; a key written into the script file would
# survive on disk for anything that can read it.
literal="$(grep -rn 'Authorization: Bearer' "$SHELL_ROOT/services/ai/" | grep -v 'apiKeyEnvVarName' | grep -v 'tokenVar')"
if [[ -n "$literal" ]]; then
    echo "an API key is written into the request script rather than read from the environment:" >&2
    echo "$literal" >&2
    exit 1
fi

# A ChatGPT plan token is fetched by request.sh when it runs and handed to curl by
# bash's builtin printf: it reaches the server, and is in no file and no argv. The
# script is built by the shipped ResponsesApiStrategy hooks, the token comes from the
# real chatgpt_auth.py reading an isolated store, the server is on 127.0.0.1.
command -v bun >/dev/null || { echo "bun not installed; skipping the plan token case" >&2; exit 0; }
tmp="$(mktemp -d)"
server_pid=""
trap '[[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
store="$tmp/state/koompi/ai/chatgpt"
mkdir -p "$tmp/home" "$tmp/config" "$store" "$tmp/data" "$tmp/cache" "$tmp/runtime" "$tmp/scripts/ai"
chmod 700 "$tmp/runtime" "$store"
ln -s "$SHELL_ROOT/scripts/ai/chatgpt_auth.py" "$tmp/scripts/ai/chatgpt_auth.py"
token="plan-token-$RANDOM$RANDOM-secret"
printf '{"client_id": "oaiapp_x", "access_token": "%s", "expires_at": %s, "scopes": ["chatgpt.tokens.use.direct"], "refresh_token": "rt"}\n' \
    "$token" "$(( $(date +%s) + 3600 ))" > "$store/credentials.json"
chmod 600 "$store/credentials.json"

cat > "$tmp/server.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(sys.argv[1] + "/seen", "w") as f: f.write(self.headers.get("Authorization", ""))
        body = b'data: {"type":"response.completed","response":{}}\n\n'
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)
srv = HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1] + "/port", "w").write(str(srv.server_address[1]))
srv.serve_forever()
PY
python3 "$tmp/server.py" "$tmp" &
server_pid=$!
for _ in $(seq 50); do [[ -s "$tmp/port" ]] && break; sleep 0.1; done
[[ -s "$tmp/port" ]] || fail "the fake responses server did not start"

cat > "$tmp/build.mjs" <<'JS'
import { readFileSync, writeFileSync } from "node:fs";
const [qmlFile, scriptPath, endpoint, out] = process.argv.slice(2);
const qml = readFileSync(qmlFile, "utf8");
function lift(name) {
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found`);
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
}
const strip = s => s.replace(/function (\w+)\(([^)]*)\): \w+/g, (_, n, a) => `function ${n}(${a})`)
    .replace(/(\w+): (AiModel|string)(?!\w)/g, "$1");
const quote = s => s.replace(/'/g, "'\\''");
const CF = { StringUtils: { shellSingleQuoteEscape: quote }, FileUtils: { trimFileProtocol: s => s.replace(/^file:\/\//, "") } };
const make = new Function("CF", "Directories", "tokenVar", strip(
    `${lift("buildAuthorizationHeader")}\n${lift("finalizeScriptContent")}\nreturn { buildAuthorizationHeader, finalizeScriptContent };`));
const s = make(CF, { scriptPath }, "KOOMPI_CHATGPT_TOKEN");
const auth = s.buildAuthorizationHeader("API_KEY", { auth: "chatgpt", requires_key: true });
const body = JSON.stringify({ model: "gpt-5", input: [], stream: true, store: false });
// the shape Requester.makeRequest assembles
writeFileSync(out, s.finalizeScriptContent("#!/usr/bin/env bash\n"
    + `exec curl --no-buffer --max-time 20 "${endpoint}" -H 'Content-Type: application/json' ${auth} --data '${quote(body)}'\n`));
JS
request="$tmp/runtime/request.sh"
bun run "$tmp/build.mjs" "$SHELL_ROOT/services/ai/ResponsesApiStrategy.qml" "$tmp/scripts" \
    "http://127.0.0.1:$(cat "$tmp/port")/v1/responses" "$request" \
    || fail "could not build request.sh from ResponsesApiStrategy"

run_request() {
    env -i PATH="$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" \
        XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/runtime" \
        bash "$request"
}
out="$(run_request 2>&1)" || fail "request.sh with a plan sign-in failed: $out"
grep -q '"response.completed"' <<< "$out" || fail "request.sh did not reach the server: $out"
[[ "$(cat "$tmp/seen" 2>/dev/null)" == "Bearer $token" ]] || fail "the plan token did not reach the server as the bearer"
grep -q "$token" "$request" && fail "the plan token is written into request.sh"
grep -q 'chatgpt_auth.py' "$request" || fail "request.sh does not fetch the plan token at run time"
grep -q "printf 'Authorization: Bearer" "$request" || fail "the bearer is not handed to curl by printf"
grep -q 'export' "$request" && fail "request.sh exports the plan token into curl's environment"

rm -f "$store/credentials.json" "$tmp/seen"
out="$(run_request 2>/dev/null)" && fail "request.sh without a sign-in succeeded"
grep -q '"code":"chatgpt_auth_4"' <<< "$out" || fail "a missing sign-in is not reported as an error event: $out"
[[ ! -e "$tmp/seen" ]] || fail "a request went out without a sign-in"

echo "ok: request body, compactor, attachments, screen grabs and clipboard decodes stay in the user's runtime directory; a plan token is in no file"
