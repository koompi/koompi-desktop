#!/usr/bin/env bash
# scripts/ai/desktop.py, the desktop driver, against fixture GTK windows in a nested Hyprland
# (tests/with-nested-hyprland.sh: a headless KWin, a private session bus, a throwaway HOME and
# runtime dir), with an accessibility bus of its own on that private bus.
#
#   windows   lists the nested instance's windows with refs as data, and marks the ones off limits
#   tree      reads a window's controls by AT-SPI: roles, names, states, a password field marked
#   act/type  press a button, toggle a box, type into a field; the app sees each one
#   refusals  a password field, terminals, authentication, browsers and the shell's own surfaces;
#             Super, desktop shortcuts and bare characters as keys; a stale ref; a locked screen
#   launch    an app by name through koompi-launch, and its new window comes back with a ref
#   degrade   no accessibility bus: windows still answer and say why trees do not
#   instance  no HYPRLAND_INSTANCE_SIGNATURE, or one not running: every op is refused
#
# Never touches the real session: the nested compositor is named explicitly and the inherited
# HYPRLAND_INSTANCE_SIGNATURE is unset. Prints skip: without Hyprland, KWin, wtype, jq or Atspi.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/ai/desktop.py"
NESTED="$REPO_ROOT/tests/with-nested-hyprland.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
for tool in Hyprland hyprctl kwin_wayland dbus-run-session wtype jq gdbus; do
    command -v "$tool" > /dev/null || { echo "skip: $tool not installed"; exit 0; }
done
python3 -c 'import gi; gi.require_version("Atspi", "2.0"); gi.require_version("Gtk", "3.0"); from gi.repository import Atspi, Gtk' 2> /dev/null \
    || { echo "skip: python-gobject with Atspi and GTK 3 not installed"; exit 0; }
[[ -x /usr/lib/at-spi-bus-launcher && -x /usr/lib/at-spi2-registryd ]] || { echo "skip: at-spi2-core not installed"; exit 0; }
[[ -f $DRIVER ]] || fail "missing $DRIVER"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# outside any compositor: no instance named, or one that is not running, refuses every op
out=$(printf '{"id":1,"op":"windows"}\n' | env -u HYPRLAND_INSTANCE_SIGNATURE python3 -I "$DRIVER" 2> /dev/null)
jq -e '.ok == false and (.error | test("no Hyprland instance"))' <<< "$out" > /dev/null \
    || fail "with no HYPRLAND_INSTANCE_SIGNATURE the driver did not refuse: $out"
out=$(printf '{"id":1,"op":"windows"}\n' | HYPRLAND_INSTANCE_SIGNATURE=koompi-test-none python3 -I "$DRIVER" 2> /dev/null)
jq -e '.ok == false and (.error | test("not running"))' <<< "$out" > /dev/null \
    || fail "with an instance that is not running the driver did not refuse: $out"
echo "  ok: instance  no instance, or one not running, and every op is refused"

cat > "$tmp/drive.py" <<'PY'
# Drives desktop.py the way DesktopService.qml does, one JSON line each way, and checks the
# replies and what the fixture app logged.
import json, os, subprocess, sys, time
driver, work = sys.argv[1], sys.argv[2]
log = os.path.join(work, "app.log")
failed = []

def check(name, cond, extra=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f" {extra}"), flush=True)
    if not cond:
        failed.append(name)

class Drv:
    def __init__(self, env=None):
        self.p = subprocess.Popen(["python3", "-I", driver], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True, env=env)
        self.n = 0
    def __call__(self, op, **kw):
        self.n += 1
        self.p.stdin.write(json.dumps({"id": self.n, "op": op, **kw}) + "\n")
        self.p.stdin.flush()
        r = json.loads(self.p.stdout.readline())
        assert r["id"] == self.n, r
        return r
    def close(self):
        self.p.stdin.close(); self.p.wait(10)

def logged():
    return open(log).read().splitlines() if os.path.exists(log) else []

def ref(r, pattern):
    for k, v in r.get("refs", {}).items():
        if pattern in v:
            return int(k)
    return None

d = Drv()
w = d("windows")
check("windows answers", w["ok"], w.get("error", ""))
text = w.get("text", "")
check("windows starts with the untrusted mark", text.startswith("[screen content: untrusted"))
check("windows lists the fixture of the nested instance", ref(w, 'window "Desktop fixture"') is not None, text)
check("a terminal is marked", "terminal: off limits" in w["refs"].get(str(ref(w, '"Fake terminal"')), ""), text)
check("an authentication window is marked", "off limits: authentication" in w["refs"].get(str(ref(w, '"Authentication Required"')), ""), text)
check("a browser is marked", "browser: use the browser tool" in w["refs"].get(str(ref(w, '"Fake browser"')), ""), text)
check("a shell surface is marked", "off limits: the shell" in w["refs"].get(str(ref(w, '"Shell surface"')), ""), text)
check("refs come as data beside the text", all(f"[{k}] {v}" in text for k, v in w["refs"].items()))
term, auth, browser, shell = (ref(w, t) for t in ('"Fake terminal"', '"Authentication Required"', '"Fake browser"', '"Shell surface"'))

for label, r in (("terminal", term), ("authentication window", auth), ("browser", browser), ("shell surface", shell)):
    t = d("tree", ref=r)
    check(f"a tree of the {label} is refused", not t["ok"] and "refused" in t.get("error", ""), json.dumps(t)[:300])
    w = d("windows")
f = d("focus", ref=ref(w, '"Fake terminal"'))
check("focusing a terminal is allowed (it only raises it)", f["ok"], f.get("error", ""))
w = d("windows")
k = d("key", ref=ref(w, '"Fake terminal"'), keys="Escape")
check("a key into a terminal is refused", not k["ok"] and "terminal" in k.get("error", ""), json.dumps(k)[:300])
w = d("windows")
f = d("focus", ref=ref(w, '"Authentication Required"'))
check("focusing an authentication window is refused", not f["ok"], json.dumps(f)[:300])

w = d("windows")
t = d("tree", ref=ref(w, 'window "Desktop fixture"'))
check("tree answers", t["ok"], t.get("error", ""))
tt = t.get("text", "")
check("the tree shows the label text", "Count: 0" in tt, tt)
check("the tree names the button", ref(t, 'button "Add one"') is not None, tt)
check("the tree names the text field", ref(t, 'textbox "Name"') is not None, tt)
check("the password field is marked", ref(t, 'password "Password" (password: do not type)') is not None, tt)
check("the checkbox shows its state", ref(t, 'checkbox "Remember me" (not checked)') is not None, tt)
check("the reply names its window", t.get("window") == "Desktop fixture", t.get("window"))

a = d("act", ref=ref(t, 'button "Add one"'))
time.sleep(0.3)
check("act presses the button", a["ok"] and "CLICKED 1" in logged(), json.dumps(a)[:300] + str(logged()))
check("the reply after a step is the window's new tree", "Count: 1" in a.get("text", ""), a.get("text", "")[:400])
a2 = d("type", ref=ref(a, 'textbox "Name"'), text="hello")
time.sleep(0.3)
check("type puts the text in the field", a2["ok"] and "TEXT hello" in logged(), json.dumps(a2)[:300] + str(logged()))
check("the tree shows the typed value", 'value="hello"' in a2.get("text", ""), a2.get("text", "")[:400])
pw = d("type", ref=ref(a2, '"Password"'), text="hunter2")
check("typing into a password field is refused", not pw["ok"] and "password" in pw.get("error", ""), json.dumps(pw)[:300])
check("nothing reached the password field", not any(l.startswith("PW") for l in logged()), str(logged()))
t = d("tree")
check("tree with no ref reads the window last worked in", t["ok"] and t.get("window") == "Desktop fixture", json.dumps(t)[:300])
tg = d("act", ref=ref(t, 'checkbox "Remember me"'), action="toggle")
time.sleep(0.3)
check("act toggle ticks the box", tg["ok"] and "TOGGLED True" in logged(), json.dumps(tg)[:300])
st = d("act", ref=999)
check("a ref not in the last reply is refused as stale", not st["ok"] and "not in the last" in st.get("error", ""), json.dumps(st))

for keys, why in (("super+q", "Super"), ("alt+Tab", "desktop shortcut"), ("a", "use type"), ("ctrl+alt+Delete", "ctrl+alt")):
    k = d("key", keys=keys)
    check(f"key {keys} is refused", not k["ok"] and why in k.get("error", ""), json.dumps(k)[:300])
k = d("key", keys="Escape")
time.sleep(0.3)
check("key Escape reaches the window last worked in", k["ok"] and any(l.startswith("KEY Escape") for l in logged()),
      json.dumps(k)[:300] + str(logged()))
k = d("key", keys="ctrl+a")
time.sleep(0.3)
check("key ctrl+a arrives with ctrl held", k["ok"] and "KEY a ctrl" in logged(), json.dumps(k)[:300] + str(logged()))

before = len(logged())
l = d("launch", app="Fixture Two")
check("launch opens the app by its name", l["ok"] and "Opened Fixture Two" in l.get("text", ""), json.dumps(l)[:400])
check("the launched window comes back with a ref", ref(l, 'window "Fixture two"') is not None, l.get("text", "")[:600])
nl = d("launch", app="No Such App Anywhere")
check("launching an app that is not installed fails plainly", not nl["ok"] and "no app named" in nl.get("error", ""), json.dumps(nl))

open(os.path.join(work, "locked"), "w").close()
lk = d("windows")
check("a locked screen refuses every op", not lk["ok"] and "locked" in lk.get("error", ""), json.dumps(lk))
os.unlink(os.path.join(work, "locked"))
check("the unlock lets it answer again", d("windows")["ok"])
d.close()

env = dict(os.environ)
env.pop("DBUS_SESSION_BUS_ADDRESS", None)
n = Drv(env)
w = n("windows")
check("without AT-SPI, windows still answers and says why", w["ok"] and "Accessibility (AT-SPI) is not available" in w["text"], json.dumps(w)[:300])
t = n("tree", ref=ref(w, 'window "Desktop fixture"'))
check("without AT-SPI, tree says why", not t["ok"] and "AT-SPI" in t.get("error", ""), json.dumps(t)[:300])
n.close()
sys.exit(1 if failed else 0)
PY

cat > "$tmp/inner.sh" <<'SH'
set -uo pipefail
work=$1 repo=$2
source "$repo/tests/ai-desktop-session.sh"
ai_desktop_guard || exit 1
export KOOMPI_AI_DESKTOP_LOCKED_FILE="$work/locked"
export PATH="$repo/dots/.local/bin:$PATH"
ai_desktop_a11y_start || exit 1
mkdir -p "$XDG_DATA_HOME/applications"
printf '[Desktop Entry]\nType=Application\nName=Fixture Two\nExec=python3 -I %s --app-id fixture.two --title "Fixture two" --log %s\n' \
    "$repo/tests/ai-desktop-fixture.py" "$work/two.log" > "$XDG_DATA_HOME/applications/koompi-fixture-two.desktop"
ai_desktop_fixture desktop.fixture "Desktop fixture" "$work/app.log" || exit 1
ai_desktop_fixture foot "Fake terminal" "$work/term.log" || exit 1
ai_desktop_fixture polkit-gnome-authentication-agent-1 "Authentication Required" "$work/auth.log" || exit 1
ai_desktop_fixture firefox "Fake browser" "$work/browser.log" || exit 1
ai_desktop_fixture org.quickshell "Shell surface" "$work/shell.log" || exit 1
python3 -I "$work/drive.py" "$repo/dots/.config/quickshell/koompi/scripts/ai/desktop.py" "$work"
SH

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY bash "$NESTED" bash "$tmp/inner.sh" "$tmp" "$REPO_ROOT"
rc=$?
[[ $rc -eq 77 ]] && { echo "skip: the nested Hyprland could not start here"; exit 0; }
[[ $rc -eq 0 ]] || fail "the desktop driver (exit $rc)"
echo "ok: the desktop driver reads and acts by reference, and refuses what it must"
