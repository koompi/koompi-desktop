#!/usr/bin/env python3
"""Drive koompi-installer --demo through a pty at 80x25, TERM=linux, against
test/fake-engine.sh, and print the screens it reaches. Touches no disk.

    python3 test/drive.py zig-out/bin/koompi-installer [happy|fail|offline|stop]

Exits nonzero when a screen does not show what the flow expects.
"""
import atexit
import fcntl
import json
import os
import pty
import shutil
import select
import struct
import sys
import tempfile
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
COLS, ROWS = 80, 25


class Term:
    """Just enough of a VT to read the installer's frames: CUP home, ED,
    SGR (ignored), private modes (ignored), CR/LF, UTF-8 text."""

    def __init__(self):
        self.grid = [[" "] * COLS for _ in range(ROWS)]
        self.x = self.y = 0
        self.pending = b""

    def feed(self, data):
        data = self.pending + data
        self.pending = b""
        text = data.decode("utf-8", errors="replace")
        i = 0
        while i < len(text):
            c = text[i]
            if c == "\x1b":
                if i + 1 >= len(text):
                    self.pending = text[i:].encode()
                    return
                if text[i + 1] != "[":
                    i += 2
                    continue
                j = i + 2
                while j < len(text) and not ("@" <= text[j] <= "~"):
                    j += 1
                if j >= len(text):
                    self.pending = text[i:].encode()
                    return
                params, final = text[i + 2 : j], text[j]
                if final == "H":
                    parts = [p for p in params.split(";") if p]
                    self.y = int(parts[0]) - 1 if parts else 0
                    self.x = int(parts[1]) - 1 if len(parts) > 1 else 0
                elif final == "J" and params == "2":
                    self.grid = [[" "] * COLS for _ in range(ROWS)]
                i = j + 1
                continue
            if c == "\r":
                self.x = 0
            elif c == "\n":
                self.y = min(self.y + 1, ROWS - 1)
            elif c >= " ":
                if self.x < COLS and self.y < ROWS:
                    self.grid[self.y][self.x] = c
                self.x += 1
            i += 1

    def text(self):
        return "\n".join("".join(r).rstrip() for r in self.grid)


class Run:
    def __init__(self, binary, args, env):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execve(binary, [binary] + args, env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        self.term = Term()
        self.code = None

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    return
                if not data:
                    return
                self.term.feed(data)

    def wait_for(self, needle, secs=15):
        end = time.time() + secs
        while time.time() < end:
            self.pump(0.1)
            if needle in self.term.text():
                return True
        raise SystemExit(f"FAIL: never saw {needle!r}; screen:\n{self.term.text()}")

    def keys(self, s, settle=0.3):
        os.write(self.fd, s.encode() if isinstance(s, str) else s)
        self.pump(settle)

    def snap(self, title):
        print(f"===== {title} " + "=" * max(0, 60 - len(title)))
        print(self.term.text())

    def finish(self, secs=10):
        end = time.time() + secs
        while time.time() < end:
            self.pump(0.1)
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.code = os.waitstatus_to_exitcode(status)
                return self.code
        raise SystemExit("FAIL: installer did not exit")


ENTER, ESC, UP, DOWN, TAB, CTRL_C, CTRL_U = "\r", "\x1b", "\x1b[A", "\x1b[B", "\t", "\x03", "\x15"


def start(binary, extra_env=None, args=None):
    runtime = tempfile.mkdtemp(prefix="koompi-drive-")
    atexit.register(shutil.rmtree, runtime, True)
    env = {
        "TERM": "linux",
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": os.environ.get("HOME", "/tmp"),
        "XDG_RUNTIME_DIR": runtime,
        "KOOMPI_FAKE_DELAY": "0.6",
    }
    env.update(extra_env or {})
    args = ["--demo", "--engine", os.path.join(HERE, "fake-engine.sh")] + (args or [])
    return Run(binary, args, env), env


def to_review(r, online_needed=True):
    r.wait_for("Install KOOMPI on this computer")
    r.snap("welcome")
    r.keys(ENTER)
    r.wait_for("Connected.", 20)
    r.snap("network")
    r.keys(ENTER)
    r.wait_for("Keyboard layout")
    r.snap("keyboard")
    r.keys(ENTER)
    r.wait_for("Search:")
    r.keys("phnom")
    r.snap("time zone, searched")
    r.keys(ENTER)
    r.wait_for("Install on which disk?")
    r.snap("disk")
    r.keys(DOWN + DOWN)
    r.keys(ENTER)
    r.wait_for("Pick a disk of 20 GB or more.")
    r.snap("disk, too small refused")
    r.keys(UP + UP)
    r.keys(ENTER)
    r.wait_for("Encrypt the disk?")
    r.keys(DOWN + DOWN + "luks" + DOWN + "luks")
    r.snap("encryption")
    r.keys(ENTER)
    r.wait_for("Your account")
    r.keys("Sok Dara")
    r.keys(TAB + CTRL_U + "dara" + TAB + 'se"c\\ret' + TAB + "nope" + TAB)
    r.keys(ENTER)
    r.wait_for("The two passwords differ")
    r.snap("account, mismatch shown")
    r.keys(CTRL_U + 'se"c\\ret' + ENTER + ENTER)
    r.wait_for("Ready to install")


def happy(binary):
    copy = tempfile.mktemp(prefix="koompi-answers-")
    r, env = start(binary, {"KOOMPI_FAKE_COPY": copy})
    to_review(r)
    r.keys("eras" + ENTER)
    r.wait_for("Type the word erase to start.")
    r.snap("review, wrong word")
    r.keys("e" + ENTER)
    r.wait_for("Step 2 of 4", 20)
    r.pump(0.5)
    r.snap("install, running")
    r.wait_for("KOOMPI is installed", 30)
    r.snap("done")
    r.keys(DOWN + ENTER)
    code = r.finish()
    print(f"exit code: {code}")
    answers = json.load(open(copy))
    os.unlink(copy)
    leftover = os.path.join(env["XDG_RUNTIME_DIR"], "koompi-demo", "answers.json")
    print("answers (passwords hidden):",
          json.dumps({k: ("<hidden>" if "password" in k else v) for k, v in answers.items()}))
    assert answers["password"] == 'se"c\\ret', answers["password"]
    assert answers["encryption_password"] == "luks"
    assert answers["disk"] == "/dev/nvme0n1" and answers["username"] == "dara"
    assert answers["timezone"] == "Asia/Phnom_Penh" and answers["encrypt"] is True
    assert not os.path.exists(leftover), "answers file left behind"
    assert code == 0


def fail(binary):
    r, _ = start(binary, {"KOOMPI_FAKE_FAIL": "2"})
    to_review(r)
    r.keys("erase" + ENTER)
    r.wait_for("The install did not finish", 30)
    r.snap("install failed")
    r.keys(DOWN + ENTER)  # open a shell, then leave it
    r.wait_for("Type exit to return to the installer.")
    r.keys("exit\r", settle=1.0)
    r.wait_for("The install did not finish")
    r.keys(UP + ENTER)  # try again
    r.wait_for("Step 1 of 4", 10)
    r.wait_for("The install did not finish", 30)
    r.keys(ESC)
    r.wait_for("Ready to install")
    r.keys(CTRL_C)
    r.wait_for("Quit the installer?")
    r.snap("quit confirm")
    r.keys("y")
    code = r.finish()
    print(f"exit code: {code}")
    assert code == 1


def stop(binary):
    r, _ = start(binary, {"KOOMPI_FAKE_DELAY": "3"})
    to_review(r)
    r.keys("erase" + ENTER)
    r.wait_for("Step 1 of 4", 10)
    r.keys(CTRL_C)
    r.wait_for("Stop the install?")
    r.snap("stop confirm")
    r.keys("y")
    r.wait_for("Stopped by you.", 10)
    r.snap("stopped")
    r.keys(CTRL_C + "y")
    print(f"exit code: {r.finish()}")


def offline(binary):
    r, _ = start(binary, args=["--check-url", "http://127.0.0.1:9/"])
    r.wait_for("Install KOOMPI on this computer")
    r.keys(ENTER)
    r.wait_for("Not connected.", 20)
    r.snap("network, offline")
    r.keys(DOWN + ENTER)  # check again
    r.wait_for("Not connected.", 20)
    r.keys(CTRL_C + "y")
    code = r.finish()
    print(f"exit code: {code}")
    assert code == 1


if __name__ == "__main__":
    binary = os.path.abspath(sys.argv[1])
    for name in sys.argv[2:] or ["happy", "fail", "offline", "stop"]:
        globals()[name](binary)
        print(f"ok: {name}")
