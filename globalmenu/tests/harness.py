"""What every conformance test shares: the daemon under test, the stand-in
applications, the registrar on the private bus, and the check log."""

import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# GLOBAL_MENU_DAEMON names the binary under test; the default is the release
# build next to this directory.
DAEMON = os.environ.get(
    "GLOBAL_MENU_DAEMON",
    os.path.join(HERE, "..", "target", "release", "global-menu-daemon"),
)

# The window-id bit the daemon gives a menu it found rather than was told about
# (registrar::ADOPTED): one entry per process, ADOPTED | pid.
ADOPTED = 0x80000000

failures = []


def check(condition, message):
    if condition:
        print("  ok   %s" % message)
    else:
        print("  FAIL %s" % message)
        failures.append(message)


def find(items, label):
    for item in items:
        if item.get("label") == label:
            return item
        found = find(item.get("items", []), label)
        if found is not None:
            return found
    return None


def labels(payload):
    return [i["label"] for i in payload.get("items", [])]


def click(daemon, payload, label, log, logged):
    """Activates `label` from `payload` and waits for the application to log
    `logged`. A missing item is a failed check, not an exception that would
    stop every test after it."""
    item = find(payload.get("items", []), label)
    if item is None:
        return False
    daemon.send_item("activate", item["id"])
    return logged in wait_for(log, lambda c: logged in c)


class Daemon:
    def __init__(self):
        self.generation = 0
        self.proc = subprocess.Popen(
            [DAEMON, "--test"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.read()  # the initial empty payload

    def send(self, line):
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def send_item(self, verb, item_id, generation=None):
        """Drives an item the way the shell does: ids are only valid inside the
        payload they arrived in, so the generation goes back with them."""
        gen = self.generation if generation is None else generation
        self.send("%s %d %d" % (verb, item_id, gen))

    def focus(self, pid, address=None):
        """Resolves the menu as if a Wayland window of `pid` had focus, through
        the same order the compositor path uses (registrar first)."""
        self.send("focus %d %s" % (pid, address or "test:%d" % pid))
        return self.read()

    def read(self, timeout=10.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if line.strip():
                payload = json.loads(line)
                if "gen" in payload:
                    self.generation = payload["gen"]
                return payload
        raise AssertionError("daemon produced no payload")

    def stop(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass  # a restart test kills the daemon on purpose
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=5)


def start_mock(script, *args):
    proc = subprocess.Popen(
        [sys.executable, os.path.join(HERE, script)] + [str(a) for a in args],
        stdout=subprocess.PIPE,
        text=True,
    )
    ready = proc.stdout.readline()
    if "READY" not in ready:
        raise AssertionError("%s did not start: %r" % (script, ready))
    return proc


def stop_mock(proc):
    proc.terminate()
    proc.wait(timeout=5)


def fresh_log(tmp, name):
    path = os.path.join(tmp, name + ".log")
    open(path, "w").close()
    return path


def wait_for(path, predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with open(path) as fh:
            content = fh.read()
        if predicate(content):
            return content
        time.sleep(0.05)
    with open(path) as fh:
        return fh.read()


def wait_until(predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def gdbus(dest, method, *args):
    return subprocess.run(
        [
            "gdbus", "call", "--session",
            "--dest", dest,
            "--object-path", "/com/canonical/AppMenu/Registrar",
            "--method", "com.canonical.AppMenu.Registrar." + method,
        ] + [str(a) for a in args],
        capture_output=True,
        text=True,
    ).stdout.strip()


def bus_call(method, *args):
    return subprocess.run(
        [
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.DBus",
            "--object-path", "/org/freedesktop/DBus",
            "--method", "org.freedesktop.DBus." + method,
        ] + [str(a) for a in args],
        capture_output=True,
        text=True,
    ).stdout.strip()


def get_menus(dest="com.canonical.AppMenu.Registrar"):
    return gdbus(dest, "GetMenus")


def menu_windows(dest="com.canonical.AppMenu.Registrar"):
    """The window ids the registrar is serving, one per registration, so a
    duplicated entry shows up as a repeated id rather than being collapsed.

    gdbus prints the `uint32` annotation on the first row of the array only, so
    matching on it finds one entry however many there are - which is exactly the
    duplicate this is here to catch."""
    return re.findall(r"\((?:uint32 )?(\d+), '", get_menus(dest))


def registrar_owner():
    """Unique name of whoever currently owns the well-known name."""
    return bus_call("GetNameOwner", "com.canonical.AppMenu.Registrar")


def unique_name_of(pid):
    """The bus name of a daemon we started, so a test can address one daemon
    directly instead of whichever one happens to own the registrar name."""
    for name in re.findall(r"'(:[0-9.]+)'", bus_call("ListNames")):
        if re.search(r"\b%d\b" % pid, bus_call("GetConnectionUnixProcessID", name)):
            return name
    raise AssertionError("no bus name for pid %d" % pid)


def mirror_path():
    return os.path.join(os.environ["XDG_RUNTIME_DIR"], "koompi-global-menu.registry")


def mirror_windows():
    """Window ids in the on-disk mirror, which is what the next daemon recovers."""
    try:
        with open(mirror_path()) as fh:
            return [line.split("\t")[0] for line in fh.read().splitlines() if line]
    except FileNotFoundError:
        return []
