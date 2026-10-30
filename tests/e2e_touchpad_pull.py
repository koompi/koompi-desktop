"""Pull to refresh end to end, driven by Playwright (tests/test_touchpad_pull_e2e.sh runs it).

A real Chromium loads the real unpacked extension. Its background starts the real
libexec/touchpad-fingers through native messaging, and that reads a FIFO standing in for
the touchpad, so a scenario says when fingers touch and lift by writing kernel input events
into it. The pulls are smooth precise-pixel wheel scrolls the browser synthesizes in its own
input pipeline (Input.synthesizeScrollGesture), as a touchpad's are; Playwright's
mouse.wheel sends whole 120-unit notches, a mouse, which pull to refresh ignores on purpose.

    uv run --with playwright python tests/e2e_touchpad_pull.py <chromium> <shots dir>
"""

import http.server
import json
import os
import shutil
import struct
import sys
import tempfile
import threading
import time

from playwright.sync_api import sync_playwright

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXT = os.path.join(REPO, "dots/.local/share/koompi/browser/pull-to-refresh")
HELPER = os.path.join(REPO, "dots/.local/share/koompi/libexec/touchpad-fingers")

EV = struct.Struct("llHHi")
TOUCH, ONE, TWO = 0x14A, 0x145, 0x14D


def key(code, value):
    return EV.pack(0, 0, 1, code, value)


REPORT = EV.pack(0, 0, 0, 0, 0)
TWO_DOWN = key(TOUCH, 1) + key(TWO, 1) + REPORT
LIFT = key(TWO, 0) + key(TOUCH, 0) + REPORT

PAGE = b"""<!doctype html><html><head><title>pull</title></head>
<body style="height:4000px;margin:0;font:16px system-ui;background:#fff">
<p style="padding:90px 24px">A page to pull on</p>
<script>
const loads = Number(sessionStorage.getItem("loads") || 0) + 1;
sessionStorage.setItem("loads", loads);
window.loads = loads;
</script></body></html>"""


class Page(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, *args):
        pass


def extension_id(path):
    import hashlib
    return "".join(chr(ord("a") + int(c, 16)) for c in hashlib.sha256(path.encode()).hexdigest()[:32])


def main():
    chromium, shots = sys.argv[1], sys.argv[2]
    os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix="koompi-pull-e2e-")
    failures = []
    try:
        ext = os.path.join(work, "pull-to-refresh")
        shutil.copytree(EXT, ext)
        fifo = os.path.join(work, "touchpad")
        os.mkfifo(fifo)
        # the browser hands a native host no environment of ours, so a wrapper points it at the FIFO
        wrapper = os.path.join(work, "touchpad-fingers")
        with open(wrapper, "w") as f:
            f.write(f'#!/bin/sh\nexport KOOMPI_TOUCHPAD_DEVICE="{fifo}" PYTHONDONTWRITEBYTECODE=1\n'
                    f'exec python3 -I "{HELPER}" "$@"\n')
        os.chmod(wrapper, 0o755)
        profile = os.path.join(work, "profile")
        hosts = os.path.join(profile, "NativeMessagingHosts")
        os.makedirs(hosts)
        with open(os.path.join(hosts, "org.koompi.touchpad.json"), "w") as f:
            json.dump({"name": "org.koompi.touchpad", "description": "test", "path": wrapper,
                       "type": "stdio", "allowed_origins": [f"chrome-extension://{extension_id(ext)}/"]}, f)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Page)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_address[1]}/"

        # the helper opens the FIFO when the extension starts it; holding a writer open keeps it
        # from reading end-of-file in between scenarios
        writer = None

        def touchpad(data):
            nonlocal writer
            if writer is None:
                writer = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
            os.write(writer, data)

        with sync_playwright() as pw:
            ctx = pw.chromium.launch_persistent_context(
                profile, executable_path=chromium, headless=True,
                ignore_default_args=["--disable-extensions"],
                args=[f"--disable-extensions-except={ext}", f"--load-extension={ext}",
                      "--disable-features=DisableLoadExtensionCommandLineSwitch",
                      "--enable-features=ElasticOverscroll"],
                viewport={"width": 900, "height": 600})
            # the background starts the helper as it comes up, so the helper opening the FIFO is
            # the extension loaded, its background running and native messaging working at once
            deadline = time.time() + 20
            while writer is None and time.time() < deadline:
                try:
                    touchpad(b"")
                except OSError:
                    time.sleep(0.1)
            if writer is None:
                raise SystemExit("FAIL: the native host never opened the touchpad: the extension did not load, "
                                 "or the host manifest or the helper is wrong")

            page = ctx.pages[0] if ctx.pages else ctx.new_page()

            def fresh():
                page.goto(url)
                page.evaluate("sessionStorage.clear(); window.scrollTo(0, 0)")
                page.reload()
                page.wait_for_function("window.loads === 1")
                page.mouse.move(450, 300)

            cdp = ctx.new_cdp_session(page)

            def pull(px):
                """px > 0 pulls down at the top; < 0 pushes back up."""
                cdp.send("Input.synthesizeScrollGesture", {
                    "x": 450, "y": 300, "yDistance": px, "speed": 1200,
                    "gestureSourceType": "mouse", "preventFling": True})

            def loads():
                try:
                    return page.evaluate("window.loads")
                except Exception:
                    time.sleep(0.5)
                    return page.evaluate("window.loads")

            def check(name, want, got):
                status = "ok  " if want == got else "FAIL"
                print(f"{status} {name}: loads {got}, wanted {want}")
                if want != got:
                    failures.append(name)

            # 1. full pull, held still with the fingers down: no reload, the spinner turns
            fresh()
            touchpad(TWO_DOWN)
            pull(840)
            time.sleep(0.15)
            page.screenshot(path=os.path.join(shots, "1-full-pull-fingers-down.png"))
            time.sleep(2.5)
            page.screenshot(path=os.path.join(shots, "2-still-held-after-2.5s.png"))
            check("full pull held still for 2.5 s with the fingers down", 1, loads())
            # 2. then the fingers lift: it reloads
            with page.expect_navigation(timeout=5000):
                touchpad(LIFT)
            page.wait_for_function("window.loads !== undefined")
            check("the same pull, fingers lifted", 2, loads())

            # 3. a short pull, fingers lift: nothing
            fresh()
            touchpad(TWO_DOWN)
            pull(240)
            time.sleep(0.1)
            page.screenshot(path=os.path.join(shots, "3-short-pull.png"))
            touchpad(LIFT)
            time.sleep(1.5)
            check("short pull, fingers lifted", 1, loads())

            # 4. a full pull taken back up, fingers lift: nothing
            fresh()
            touchpad(TWO_DOWN)
            pull(840)
            pull(-420)
            touchpad(LIFT)
            time.sleep(1.5)
            check("full pull taken back, fingers lifted", 1, loads())

            # 5. a full pull that pauses with the fingers down, goes on, then lifts: reloads once
            fresh()
            touchpad(TWO_DOWN)
            pull(480)
            time.sleep(0.8)
            pull(360)
            time.sleep(0.3)
            with page.expect_navigation(timeout=5000):
                touchpad(LIFT)
            page.wait_for_function("window.loads !== undefined")
            check("pull, pause with fingers down, pull on, lift", 2, loads())

            ctx.close()
        if writer is not None:
            os.close(writer)
        server.shutdown()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
