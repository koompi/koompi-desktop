#!/usr/bin/env bash
# ChatGPT sign-in (scripts/ai/chatgpt_auth.py) against a fake OAuth server on
# 127.0.0.1: registration on the first sign-in, PKCE, the loopback callback, the
# 0600 store, refresh near expiry under a lock, the scope and error exits, and a
# status that leaks nothing. A small python "browser" follows the redirect. Every
# directory the helper could touch is a fresh temp dir; nothing leaves the machine.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/ai/chatgpt_auth.py"

[[ -f "$AUTH" ]] || { echo "FAIL: missing $AUTH" >&2; exit 1; }
[[ -x "$AUTH" ]] || { echo "FAIL: $AUTH is not executable" >&2; exit 1; }

tmp="$(mktemp -d)"
server_pid=""
cleanup() {
    [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/home" "$tmp/config" "$tmp/state" "$tmp/data" "$tmp/cache" "$tmp/runtime"
chmod 700 "$tmp/runtime"

failed=0
fail() { echo "FAIL: $1" >&2; failed=1; }

cat > "$tmp/server.py" <<'PY'
import base64, hashlib, json, os, secrets, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

work = sys.argv[1]
lock = threading.Lock()
codes, state = {}, {"refreshes": 0, "valid_refresh": None, "n": 0}

def control():
    with open(os.path.join(work, "control.json")) as f:
        return json.load(f)

def log(kind, data):
    with lock, open(os.path.join(work, "log.jsonl"), "a") as f:
        f.write(json.dumps({"kind": kind, **data}) + "\n")

def b64(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def reply(self, status, body, headers=()):
        raw = json.dumps(body).encode()
        self.send_response(status)
        for k, v in headers: self.send_header(k, v)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        base = f"http://127.0.0.1:{self.server.server_address[1]}"
        url = urllib.parse.urlsplit(self.path)
        if url.path == "/.well-known/openid-configuration":
            return self.reply(200, {"issuer": base,
                "authorization_endpoint": base + "/api/accounts/authorize",
                "token_endpoint": base + "/api/accounts/oauth/token"})
        if url.path != "/api/accounts/authorize":
            return self.reply(404, {})
        q = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        log("authorize", q)
        issued = None
        if q.get("client_id") == "dynamic_agent_client":
            if not q.get("agent_name_hint") or not q.get("ext_agent_host_id"):
                return self.reply(400, {"error": "invalid_request"})
            issued = "oaiapp_test123"
        elif q.get("client_id") != "oaiapp_test123":
            return self.reply(400, {"error": "invalid_client"})
        code = secrets.token_urlsafe(8)
        codes[code] = {"challenge": q["code_challenge"], "nonce": q["nonce"],
                       "redirect": q["redirect_uri"], "client": issued or q["client_id"]}
        back = {"code": code, "state": q["state"]}
        if issued: back["client_id"] = issued
        self.reply(302, {}, [("Location", q["redirect_uri"] + "?" + urllib.parse.urlencode(back))])

    def tokens(self, client, nonce):
        c = control()
        with lock:
            state["n"] += 1
            n = state["n"]
            state["valid_refresh"] = f"rt-{n}"
        base = f"http://127.0.0.1:{self.server.server_address[1]}"
        claims = {"iss": base, "aud": client, "exp": int(time.time()) + 3600, "sub": "user-1",
                  "email": "founder@example.test"}
        if nonce: claims["nonce"] = nonce
        body = {"access_token": f"at-{n}", "refresh_token": f"rt-{n}", "token_type": "Bearer",
                "expires_in": c.get("expires_in", 3600), "scope": c["scope"],
                "id_token": f"{b64({'alg': 'RS256'})}.{b64(claims)}.sig"}
        return self.reply(200, body)

    def do_POST(self):
        if self.path != "/api/accounts/oauth/token":
            return self.reply(404, {})
        form = {k: v[0] for k, v in urllib.parse.parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode()).items()}
        log("token", {k: v for k, v in form.items() if k not in ("code_verifier",)})
        if form.get("grant_type") == "authorization_code":
            entry = codes.pop(form.get("code"), None)
            challenge = base64.urlsafe_b64encode(hashlib.sha256(form.get("code_verifier", "").encode()).digest()).rstrip(b"=").decode()
            if (not entry or challenge != entry["challenge"] or form.get("redirect_uri") != entry["redirect"]
                    or form.get("client_id") != entry["client"] or form.get("resource") != "https://api.openai.com/v1"):
                return self.reply(400, {"error": "invalid_grant"})
            return self.tokens(entry["client"], entry["nonce"])
        if form.get("grant_type") == "refresh_token":
            mode = control().get("refresh_mode", "ok")
            time.sleep(0.5)  # widen the window two racing refreshes would both fall into
            if mode == "down":
                return self.reply(503, {"error": "temporarily_unavailable"})
            if mode == "terminal":
                return self.reply(400, {"error": "invalid_grant"})
            with lock:
                if form.get("refresh_token") != state["valid_refresh"] or form.get("client_id") != "oaiapp_test123":
                    return self.reply(400, {"error": {"code": "refresh_token_reused", "message": "reused"}})
                state["refreshes"] += 1
            log("refreshed", {"count": state["refreshes"]})
            return self.tokens("oaiapp_test123", None)
        self.reply(400, {"error": "unsupported_grant_type"})

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(os.path.join(work, "port"), "w") as f: f.write(str(srv.server_address[1]))
srv.serve_forever()
PY

# The "browser": fetch the authorize URL and follow its redirect to the callback.
cat > "$tmp/browser.py" <<'PY'
#!/usr/bin/env python3
import os, re, sys, urllib.request
url = sys.argv[1]
if os.environ.get("TAMPER_STATE") == "1":
    url = re.sub(r"state=[^&]+", "state=forged", url)
with open(os.environ["BROWSER_LOG"], "a") as f: f.write(url + "\n")
try:
    urllib.request.urlopen(url, timeout=10).read()
except Exception as e:
    with open(os.environ["BROWSER_LOG"], "a") as f: f.write(f"error {e}\n")
PY

PLAN_SCOPES="openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
control() { printf '%s\n' "$1" > "$tmp/control.json"; }
control "{\"scope\": \"$PLAN_SCOPES\"}"

python3 "$tmp/server.py" "$tmp" &
server_pid=$!
for _ in $(seq 50); do [[ -s "$tmp/port" ]] && break; sleep 0.1; done
[[ -s "$tmp/port" ]] || { echo "FAIL: the fake OAuth server did not start" >&2; exit 1; }
issuer="http://127.0.0.1:$(cat "$tmp/port")"
callback_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"

# env -i: no DISPLAY, no WAYLAND_DISPLAY, no session bus, no real HOME.
auth() {
    env -i PATH="$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" \
        XDG_DATA_HOME="$tmp/data" XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/runtime" \
        KOOMPI_CHATGPT_ISSUER="$issuer" KOOMPI_CHATGPT_BROWSER="$tmp/browser.py" \
        KOOMPI_CHATGPT_CALLBACK_PORT="$callback_port" KOOMPI_CHATGPT_LOGIN_TIMEOUT=20 \
        BROWSER_LOG="$tmp/browser.log" TAMPER_STATE="${TAMPER_STATE:-0}" \
        "$AUTH" "$@"
}
chmod +x "$tmp/browser.py"
store="$tmp/state/koompi/ai/chatgpt"
creds="$store/credentials.json"
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("" if v is None else (" ".join(v) if isinstance(v, list) else v))' "$creds" "$1"; }
set_expiry() { python3 -c 'import json,sys,time; p=sys.argv[1]; d=json.load(open(p)); d["expires_at"]=int(time.time())+int(sys.argv[2]); json.dump(d,open(p,"w"))' "$creds" "$1"; }
authorize_log() { python3 -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1]) if "\"authorize\"" in l]; print(rows[int(sys.argv[2])].get(sys.argv[3], ""))' "$tmp/log.jsonl" "$1" "$2"; }
refreshes() { grep -c '"refreshed"' "$tmp/log.jsonl" || true; }

# --- first sign-in registers the client
out="$(auth login 2>&1)" || { echo "FAIL: login exited non-zero: $out" >&2; exit 1; }
grep -q "Signed in to ChatGPT as founder@example.test" <<< "$out" || fail "login did not report the account: $out"
grep -q "$issuer/api/accounts/authorize?" <<< "$out" || fail "login did not print the URL"
[[ "$(authorize_log 0 client_id)" == "dynamic_agent_client" ]] || fail "the first sign-in did not register with dynamic_agent_client"
[[ "$(authorize_log 0 agent_name_hint)" == "KOOMPI" ]] || fail "agent_name_hint is not KOOMPI"
host_id="$(authorize_log 0 ext_agent_host_id)"
[[ "$host_id" =~ ^[0-9a-f]{64}$ ]] || fail "ext_agent_host_id is not a hash: $host_id"
machine="$(tr -d '\n' < /etc/machine-id)"
[[ "$host_id" != *"$machine"* ]] || fail "ext_agent_host_id carries the raw machine id"
[[ "$host_id" != "$(printf '%s' "$machine" | sha256sum | cut -d' ' -f1)" ]] || fail "ext_agent_host_id is an unsalted hash of the machine id"
[[ "$(authorize_log 0 scope)" == "$PLAN_SCOPES" ]] || fail "scope is $(authorize_log 0 scope)"
[[ "$(authorize_log 0 resource)" == "https://api.openai.com/v1" ]] || fail "authorize carries no resource"
[[ "$(authorize_log 0 code_challenge_method)" == "S256" ]] || fail "PKCE is not S256"
[[ "$(authorize_log 0 redirect_uri)" == "http://127.0.0.1:$callback_port/auth/callback" ]] || fail "redirect is $(authorize_log 0 redirect_uri)"
grep -q '"grant_type": "authorization_code".*"resource": "https://api.openai.com/v1"' "$tmp/log.jsonl" || fail "the code exchange carries no resource"
[[ "$(field client_id)" == "oaiapp_test123" ]] || fail "the issued client id was not saved"
[[ "$(stat -c %a "$creds")" == "600" ]] || fail "credentials are $(stat -c %a "$creds"), not 600"
[[ "$(stat -c %a "$store")" == "700" ]] || fail "the store is $(stat -c %a "$store"), not 700"
[[ -z "$(find "$store" -name '.credentials-*')" ]] || fail "a temp file was left behind"

# --- token prints the token and nothing else
out="$(auth token 2>"$tmp/err")" || fail "token exited non-zero"
[[ "$out" == "at-1" ]] || fail "token printed '$out'"
[[ ! -s "$tmp/err" ]] || fail "token wrote to stderr: $(cat "$tmp/err")"

# --- status: shape, and no secret
out="$(auth status)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d=={"signed_in":True,"email":"founder@example.test","plan_usage":True,"expires_at":d["expires_at"]} and isinstance(d["expires_at"],int), d' "$out" \
    || fail "status is $out"
grep -qE 'at-|rt-|token' <<< "$out" && fail "status leaks a token: $out"

# --- a later sign-in reuses the client id, fresh state, and any free port when 1455's is taken
python3 -c 'import socket,time,sys; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(); open(sys.argv[2],"w").close(); time.sleep(30)' "$callback_port" "$tmp/held" &
holder=$!
for _ in $(seq 50); do [[ -e "$tmp/held" ]] && break; sleep 0.1; done
[[ -e "$tmp/held" ]] || fail "could not hold the preferred callback port"
auth login >/dev/null 2>&1 || fail "the second sign-in failed"
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
[[ "$(authorize_log 1 client_id)" == "oaiapp_test123" ]] || fail "the second sign-in did not reuse the issued client id"
[[ -z "$(authorize_log 1 agent_name_hint)" ]] || fail "the second sign-in registered again"
[[ "$(authorize_log 1 state)" != "$(authorize_log 0 state)" ]] || fail "state was reused"
[[ "$(authorize_log 1 nonce)" != "$(authorize_log 0 nonce)" ]] || fail "nonce was reused"
[[ "$(authorize_log 1 code_challenge)" != "$(authorize_log 0 code_challenge)" ]] || fail "the PKCE verifier was reused"
[[ "$(authorize_log 1 redirect_uri)" =~ ^http://127\.0\.0\.1:[0-9]+/auth/callback$ && "$(authorize_log 1 redirect_uri)" != *":$callback_port/"* ]] \
    || fail "with the port taken the redirect is $(authorize_log 1 redirect_uri)"

# --- refresh near expiry rotates the refresh token
set_expiry 60
before="$(field refresh_token)"
out="$(auth token)" || fail "token did not refresh"
[[ "$out" == "at-3" ]] || fail "after refresh token printed '$out'"
[[ "$(refreshes)" == "1" ]] || fail "expected one refresh, saw $(refreshes)"
[[ "$(field refresh_token)" != "$before" ]] || fail "the refresh token did not rotate"
[[ "$(stat -c %a "$creds")" == "600" ]] || fail "after refresh credentials are $(stat -c %a "$creds")"
out="$(auth token)"
[[ "$(refreshes)" == "1" ]] || fail "a fresh token was refreshed again"

# --- two requests at once refresh once
set_expiry 30
auth token > "$tmp/t1" 2>"$tmp/e1" & p1=$!
auth token > "$tmp/t2" 2>"$tmp/e2" & p2=$!
r1=0; r2=0
wait "$p1" || r1=$?
wait "$p2" || r2=$?
[[ "$r1" == 0 && "$r2" == 0 ]] || fail "concurrent token calls exited $r1/$r2: $(cat "$tmp/e1" "$tmp/e2")"
[[ "$(cat "$tmp/t1")" == "at-4" && "$(cat "$tmp/t2")" == "at-4" ]] || fail "concurrent tokens: $(cat "$tmp/t1") / $(cat "$tmp/t2")"
[[ "$(refreshes)" == "2" ]] || fail "two concurrent requests refreshed $(( $(refreshes) - 1 )) times"

# --- network trouble keeps everything
set_expiry 30
control "{\"scope\": \"$PLAN_SCOPES\", \"refresh_mode\": \"down\"}"
rc=0; out="$(auth token 2>/dev/null)" || rc=$?
[[ "$rc" == 5 && -z "$out" ]] || fail "a 503 on refresh exited $rc, printed '$out'"
[[ -n "$(field refresh_token)" && "$(field client_id)" == "oaiapp_test123" ]] || fail "a network error dropped the sign-in"

# --- a terminal refresh error clears the tokens, keeps the client id
control "{\"scope\": \"$PLAN_SCOPES\", \"refresh_mode\": \"terminal\"}"
rc=0; auth token >/dev/null 2>"$tmp/err" || rc=$?
[[ "$rc" == 4 ]] || fail "invalid_grant on refresh exited $rc"
grep -q "sign in again" "$tmp/err" || fail "no sign-in advice: $(cat "$tmp/err")"
[[ -z "$(field refresh_token)" && -z "$(field access_token)" ]] || fail "a terminal error left tokens behind"
[[ "$(field client_id)" == "oaiapp_test123" ]] || fail "a terminal error dropped the client id"
rc=0; auth token >/dev/null 2>&1 || rc=$?
[[ "$rc" == 4 ]] || fail "token when signed out exited $rc"

# --- a sign-in without the plan scope is refused
control '{"scope": "openid profile email offline_access"}'
auth login >/dev/null 2>&1 || fail "login without the plan scope failed outright"
rc=0; out="$(auth token 2>"$tmp/err")" || rc=$?
[[ "$rc" == 3 && -z "$out" ]] || fail "missing plan scope exited $rc, printed '$out'"
grep -q "chatgpt.tokens.use.direct" "$tmp/err" || fail "the scope refusal does not say why"
python3 -c 'import json,sys; assert json.loads(sys.argv[1])["plan_usage"] is False' "$(auth status)" || fail "status claims plan usage without the scope"

# --- a forged state is refused and nothing is saved
control "{\"scope\": \"$PLAN_SCOPES\"}"
before="$(cat "$creds")"
rc=0; TAMPER_STATE=1 auth login >/dev/null 2>"$tmp/err" || rc=$?
[[ "$rc" == 1 ]] || fail "a forged state exited $rc"
grep -q "state" "$tmp/err" || fail "the state refusal does not say why: $(cat "$tmp/err")"
[[ "$(cat "$creds")" == "$before" ]] || fail "a forged state changed the store"

# --- logout forgets the tokens and keeps the client id
auth login >/dev/null 2>&1 || fail "sign-in before logout failed"
auth logout >/dev/null || fail "logout failed"
[[ -z "$(field refresh_token)" && -z "$(field access_token)" && -z "$(field email)" ]] || fail "logout left account data"
[[ "$(field client_id)" == "oaiapp_test123" ]] || fail "logout dropped the client id"
python3 -c 'import json,sys; assert json.loads(sys.argv[1])["signed_in"] is False' "$(auth status)" || fail "status after logout"

(( failed == 0 )) || exit 1
echo "ok: chatgpt sign-in, token refresh under a lock, scope and error exits, private store"
