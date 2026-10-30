#!/usr/bin/env python3
"""Sign in with ChatGPT so the sidebar AI can use the user's plan.

OpenAI's documented route for open-source, locally hosted apps: the first sign-in
registers this host as a client, later ones reuse the client id it issued. PKCE,
a loopback callback on 127.0.0.1, a rotating refresh token kept in a 0600 file.

    chatgpt_auth.py login    open the browser, wait for the callback, store tokens
    chatgpt_auth.py token    print a valid access token, refreshing it if needed
    chatgpt_auth.py status   JSON: signed_in, email, plan_usage, expires_at
    chatgpt_auth.py logout   forget the tokens, keep the registered client id

`token` exits 3 when the sign-in does not grant plan usage, 4 when the user has
to sign in again, 5 when OpenAI could not be reached (nothing is lost).
Stdlib only, like web.py. The KOOMPI_CHATGPT_* variables exist for tests.
"""
import base64
import contextlib
import fcntl
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ISSUER = os.environ.get("KOOMPI_CHATGPT_ISSUER", "https://auth.openai.com").rstrip("/")
BROWSER = os.environ.get("KOOMPI_CHATGPT_BROWSER", "xdg-open")
PREFERRED_PORT = int(os.environ.get("KOOMPI_CHATGPT_CALLBACK_PORT", "1455"))
LOGIN_TIMEOUT = int(os.environ.get("KOOMPI_CHATGPT_LOGIN_TIMEOUT", "300"))
HTTP_TIMEOUT = 30

RESOURCE = "https://api.openai.com/v1"
PLAN_SCOPE = "chatgpt.tokens.use.direct"
SCOPES = f"openid profile email offline_access resource.invoke {PLAN_SCOPE}"
REGISTER_CLIENT = "dynamic_agent_client"
AGENT_NAME = "KOOMPI"
HOST_ID_SALT = b"koompi-ai-chatgpt-host-id-v1"
REFRESH_MARGIN = 300
TOKEN_FIELDS = ("access_token", "refresh_token", "expires_at", "scopes", "email", "sub")
TERMINAL_ERRORS = {
    "invalid_grant", "refresh_token_expired", "refresh_token_reused",
    "refresh_token_invalidated", "invalid_refresh_token", "token_revoked",
}

EXIT_FAILED, EXIT_SCOPE, EXIT_SIGN_IN, EXIT_NETWORK = 1, 3, 4, 5


class Exit(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


# --- storage ---------------------------------------------------------------

def store_dir():
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "koompi", "ai", "chatgpt")


def credentials_path():
    return os.path.join(store_dir(), "credentials.json")


def ensure_dir():
    path = store_dir()
    os.makedirs(path, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def load():
    try:
        with open(credentials_path(), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(creds):
    directory = ensure_dir()
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".credentials-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            os.fchmod(f.fileno(), 0o600)
            json.dump(creds, f, indent=1)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, credentials_path())
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


@contextlib.contextmanager
def locked():
    # the refresh token is single use: two requests spending it at once sign the user out
    fd = os.open(os.path.join(ensure_dir(), "credentials.lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def without_tokens(creds):
    return {k: v for k, v in creds.items() if k not in TOKEN_FIELDS}


# --- http ------------------------------------------------------------------

def checked_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme == "https" or (parts.scheme == "http" and parts.hostname == "127.0.0.1"):
        return url
    raise Exit(EXIT_FAILED, f"refusing a non-TLS endpoint: {url}")


def request(url, form=None):
    """(status, parsed JSON or {}). Network failures raise Exit(EXIT_NETWORK)."""
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    req = urllib.request.Request(checked_url(url), data=data, headers={"Accept": "application/json"})
    if data is not None:
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    except (urllib.error.URLError, OSError) as e:
        raise Exit(EXIT_NETWORK, f"could not reach {urllib.parse.urlsplit(url).netloc}: {e}")
    try:
        body = json.loads(raw or b"{}")
    except ValueError:
        body = {}
    return status, body if isinstance(body, dict) else {}


def discover():
    endpoints = {
        "issuer": ISSUER,
        "authorization_endpoint": f"{ISSUER}/api/accounts/authorize",
        "token_endpoint": f"{ISSUER}/api/accounts/oauth/token",
    }
    status, doc = request(f"{ISSUER}/.well-known/openid-configuration")
    if status == 200:
        for key in endpoints:
            if isinstance(doc.get(key), str) and doc[key]:
                endpoints[key] = doc[key]
    return endpoints


def oauth_error(body):
    err = body.get("error")
    if isinstance(err, dict):
        return str(err.get("code") or err.get("type") or "unknown_error")
    return str(err or body.get("code") or "unknown_error")


# --- tokens ----------------------------------------------------------------

def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def jwt_claims(token):
    try:
        payload = token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    except (IndexError, ValueError):
        raise Exit(EXIT_FAILED, "the ID token is not a JWT")


def verified_claims(id_token, issuer, client_id, nonce):
    # The signature is not checked: that needs JWKS and RSA, which the stdlib lacks.
    # The token came straight from the token endpoint over TLS, in answer to our own
    # PKCE-bound exchange, so the claims are checked and the channel is the proof.
    claims = jwt_claims(id_token)
    audience = claims.get("aud")
    audiences = audience if isinstance(audience, list) else [audience]
    if str(claims.get("iss", "")).rstrip("/") != issuer.rstrip("/"):
        raise Exit(EXIT_FAILED, "the ID token names another issuer")
    if client_id not in audiences:
        raise Exit(EXIT_FAILED, "the ID token is for another client")
    if not isinstance(claims.get("exp"), (int, float)) or claims["exp"] < time.time() - 60:
        raise Exit(EXIT_FAILED, "the ID token has expired")
    if nonce is not None and claims.get("nonce") != nonce:
        raise Exit(EXIT_FAILED, "the ID token does not answer this sign-in")
    return claims


def apply_tokens(creds, tok, endpoints, nonce=None):
    """Access token, expiry, scopes and refresh token replace the old ones together."""
    if not tok.get("access_token"):
        raise Exit(EXIT_FAILED, "the token endpoint returned no access token")
    updated = dict(creds)
    if tok.get("id_token"):
        claims = verified_claims(tok["id_token"], endpoints["issuer"], creds["client_id"], nonce)
        updated["email"] = claims.get("email") or creds.get("email")
        updated["sub"] = claims.get("sub") or creds.get("sub")
    elif nonce is not None:
        raise Exit(EXIT_FAILED, "the sign-in returned no ID token")
    # RFC 6749: an omitted scope is the one asked for (login) or already granted (refresh)
    scope = tok.get("scope") or (SCOPES if nonce is not None else " ".join(creds.get("scopes", [])))
    updated.update({
        "access_token": tok["access_token"],
        "expires_at": int(time.time()) + int(tok.get("expires_in") or 3600),
        "scopes": scope.split(),
        "refresh_token": tok.get("refresh_token") or creds.get("refresh_token"),
    })
    return updated


def refresh(creds):
    endpoints = discover()
    status, tok = request(endpoints["token_endpoint"], {
        "grant_type": "refresh_token",
        "refresh_token": creds["refresh_token"],
        "client_id": creds["client_id"],
    })
    if status == 200:
        updated = apply_tokens(creds, tok, endpoints)
        save(updated)
        return updated
    code = oauth_error(tok)
    if code in TERMINAL_ERRORS or (status in (400, 401) and "error" in tok):
        save(without_tokens(creds))
        raise Exit(EXIT_SIGN_IN, f"the ChatGPT sign-in has ended ({code}); sign in again")
    raise Exit(EXIT_NETWORK, f"could not renew the ChatGPT sign-in (HTTP {status}, {code}); try again")


def fresh(creds):
    return bool(creds.get("access_token")) and creds.get("expires_at", 0) - time.time() > REFRESH_MARGIN


def require_plan_scope(creds):
    if PLAN_SCOPE not in creds.get("scopes", []):
        raise Exit(EXIT_SCOPE, f"this ChatGPT sign-in does not grant plan usage ({PLAN_SCOPE})")


def cmd_token():
    creds = load()
    if not creds.get("refresh_token") and not creds.get("access_token"):
        raise Exit(EXIT_SIGN_IN, "not signed in to ChatGPT; run: chatgpt_auth.py login")
    require_plan_scope(creds)
    if not fresh(creds):
        with locked():
            creds = load()  # another request may have refreshed while this one waited
            if not fresh(creds):
                if not creds.get("refresh_token") or not creds.get("client_id"):
                    raise Exit(EXIT_SIGN_IN, "the ChatGPT sign-in has ended; sign in again")
                creds = refresh(creds)
        require_plan_scope(creds)
    print(creds["access_token"])
    return 0


def cmd_status():
    creds = load()
    signed_in = bool(creds.get("refresh_token") or creds.get("access_token"))
    print(json.dumps({
        "signed_in": signed_in,
        "email": creds.get("email") if signed_in else None,
        "plan_usage": signed_in and PLAN_SCOPE in creds.get("scopes", []),
        "expires_at": creds.get("expires_at") if signed_in else None,
    }))
    return 0


def cmd_logout():
    with locked():
        creds = load()
        if creds:
            save(without_tokens(creds))
    print("Signed out of ChatGPT.")
    return 0


# --- login -----------------------------------------------------------------

def host_id():
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        with contextlib.suppress(OSError):
            with open(path, "rb") as f:
                machine = f.read().strip()
            if machine:
                return hashlib.sha256(HOST_ID_SALT + b":" + machine).hexdigest()
    raise Exit(EXIT_FAILED, "no /etc/machine-id to derive this host's id from")


class CallbackServer(http.server.HTTPServer):
    result = None


class CallbackHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if url.path != "/auth/callback":
            self.send_error(404)
            return
        self.server.result = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        ok = "code" in self.server.result
        page = "Signed in to ChatGPT. You can close this tab." if ok else "Sign-in did not finish. You can close this tab."
        body = f"<!doctype html><meta charset=utf-8><title>KOOMPI</title><p>{page}</p>".encode()
        self.send_response(200 if ok else 400)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def bind_callback(registered):
    # only the port may vary, and only once the client is registered on the first one
    try:
        return CallbackServer(("127.0.0.1", PREFERRED_PORT), CallbackHandler)
    except OSError:
        if not registered:
            raise Exit(EXIT_FAILED, f"port {PREFERRED_PORT} on 127.0.0.1 is busy; the first sign-in needs it")
        return CallbackServer(("127.0.0.1", 0), CallbackHandler)


def open_browser(url):
    print(f"Sign in to ChatGPT in your browser. If it did not open, visit:\n{url}", flush=True)
    with contextlib.suppress(OSError):
        subprocess.Popen([BROWSER, url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


def wait_for_callback(server):
    deadline = time.monotonic() + LOGIN_TIMEOUT
    server.timeout = 1
    while server.result is None and time.monotonic() < deadline:
        server.handle_request()
    if server.result is None:
        raise Exit(EXIT_FAILED, "no answer from the browser; sign-in timed out")
    return server.result


def cmd_login():
    saved = load()
    client_id = saved.get("client_id") or ""
    endpoints = discover()
    verifier, state, nonce = secrets.token_urlsafe(64), secrets.token_urlsafe(32), secrets.token_urlsafe(32)
    server = bind_callback(bool(client_id))
    redirect = f"http://127.0.0.1:{server.server_address[1]}/auth/callback"
    params = {
        "response_type": "code",
        "client_id": client_id or REGISTER_CLIENT,
        "redirect_uri": redirect,
        "scope": SCOPES,
        "state": state,
        "nonce": nonce,
        "code_challenge": b64url(hashlib.sha256(verifier.encode()).digest()),
        "code_challenge_method": "S256",
        "resource": RESOURCE,
    }
    if not client_id:
        params.update({"agent_name_hint": AGENT_NAME, "ext_agent_host_id": host_id()})
    with server:
        open_browser(f"{checked_url(endpoints['authorization_endpoint'])}?{urllib.parse.urlencode(params)}")
        answer = wait_for_callback(server)
    if not secrets.compare_digest(answer.get("state", ""), state):
        raise Exit(EXIT_FAILED, "the sign-in answer does not match this attempt (state); nothing was saved")
    if "code" not in answer:
        raise Exit(EXIT_FAILED, f"sign-in refused: {answer.get('error', 'no code')} {answer.get('error_description', '')}".strip())
    client_id = answer.get("client_id") or client_id
    if not client_id:
        raise Exit(EXIT_FAILED, "the first sign-in returned no client id")
    status, tok = request(endpoints["token_endpoint"], {
        "grant_type": "authorization_code",
        "code": answer["code"],
        "redirect_uri": redirect,
        "client_id": client_id,
        "code_verifier": verifier,
        "resource": RESOURCE,
    })
    if status != 200:
        raise Exit(EXIT_FAILED, f"the code exchange failed (HTTP {status}, {oauth_error(tok)})")
    with locked():
        creds = apply_tokens(dict(without_tokens(load()), client_id=client_id), tok, endpoints, nonce)
        save(creds)
    print(f"Signed in to ChatGPT as {creds.get('email') or creds.get('sub') or 'unknown'}.")
    if PLAN_SCOPE not in creds["scopes"]:
        print("This sign-in does not grant plan usage, so KOOMPI cannot use it.", file=sys.stderr)
    return 0


COMMANDS = {"login": cmd_login, "token": cmd_token, "status": cmd_status, "logout": cmd_logout}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        print(f"usage: chatgpt_auth.py {{{'|'.join(COMMANDS)}}}", file=sys.stderr)
        return 2
    try:
        return COMMANDS[sys.argv[1]]()
    except Exit as e:
        print(f"chatgpt_auth: {e}", file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main())
