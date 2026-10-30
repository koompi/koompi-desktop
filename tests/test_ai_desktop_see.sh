#!/usr/bin/env bash
# The desktop driver's `see` (M7) against fixture GTK windows in a nested Hyprland
# (tests/with-nested-hyprland.sh), with an accessibility bus of its own on a private bus.
#
#   see       one window alone (grim -T), scaled to fit 1600x1000, a JPEG with numbered marks
#   tree      an accessible app: each mark is the tree's [ref]; act presses it through AT-SPI;
#             the password field is blacked out and typing into it is refused
#   pixels    an app with no tree (NO_AT_BRIDGE=1): marks from its pixels; act on one clicks its
#             centre through the virtual pointer and the app sees the click; type on one is refused
#   refusals  no screenshot of a terminal, an authentication window, a browser or a shell surface,
#             and no file written for one; a stale mark; a window that changed size since the shot
#   files     the shots dir is the user's own (0700), only the last three screenshots are kept,
#             and no raw capture is left behind
#
# Never touches the real session: the nested compositor is named explicitly and the inherited
# HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY are unset. Prints skip: without Hyprland, KWin,
# grim, wtype, jq, Atspi or Pillow.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/ai/desktop.py"
NESTED="$REPO_ROOT/tests/with-nested-hyprland.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
for tool in Hyprland hyprctl kwin_wayland dbus-run-session grim wtype jq gdbus; do
    command -v "$tool" > /dev/null || { echo "skip: $tool not installed"; exit 0; }
done
python3 -c 'import gi; gi.require_version("Atspi", "2.0"); gi.require_version("Gtk", "3.0"); from gi.repository import Atspi, Gtk' 2> /dev/null \
    || { echo "skip: python-gobject with Atspi and GTK 3 not installed"; exit 0; }
python3 -c 'import PIL' 2> /dev/null || { echo "skip: python-pillow not installed"; exit 0; }
[[ -x /usr/lib/at-spi-bus-launcher && -x /usr/lib/at-spi2-registryd ]] || { echo "skip: at-spi2-core not installed"; exit 0; }
[[ -f $DRIVER ]] || fail "missing $DRIVER"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/drive.py" <<'PY'
import json, os, stat, subprocess, sys, time
from PIL import Image
driver, work, phase, repo = sys.argv[1:5]
shots = os.path.join(work, "shots")
failed = []

def check(name, cond, extra=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f" {extra}"), flush=True)
    if not cond:
        failed.append(name)

class Drv:
    def __init__(self):
        self.p = subprocess.Popen(["python3", "-I", driver, "--shots", shots], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True)
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

def logged(name):
    path = os.path.join(work, name)
    return open(path).read().splitlines() if os.path.exists(path) else []

def ref(r, pattern):
    for k, v in r.get("refs", {}).items():
        if pattern in v:
            return int(k)
    return None

def files():
    return sorted(os.listdir(shots)) if os.path.isdir(shots) else []

def clients():
    return json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout)

d = Drv()

# ---- refusals first: nothing captured of a window tree would refuse ----
if phase == "refusals":
    w = d("windows")
    check("windows answers", w["ok"], w.get("error", ""))
    for label in ('"Fake terminal"', '"Authentication Required"', '"Fake browser"', '"Shell surface"'):
        s = d("see", ref=ref(w, label))
        check(f"see of {label} is refused", not s["ok"] and "refused" in s.get("error", ""), json.dumps(s)[:300])
        w = d("windows")
    check("no screenshot was written for a refused window", files() == [], str(files()))
    d.close()
    sys.exit(1 if failed else 0)

# ---- an accessible app: marks are the tree's refs ----
w = d("windows")
s = d("see", ref=ref(w, 'window "Desktop fixture"'))
check("see answers for an accessible app", s["ok"], s.get("error", ""))
img = s.get("image", "")
check("the screenshot is a JPEG in the shots dir", img.startswith(shots + "/see-") and open(img, "rb").read(3) == b"\xff\xd8\xff", img)
fixture = next(c for c in clients() if c["title"] == "Desktop fixture")
with Image.open(img) as shot:
    size = shot.size
check("it fits 1600x1000", size[0] <= 1600 and size[1] <= 1000, str(size))
check("it is the window alone: its own aspect, nothing beside it",
      abs(size[0] / size[1] - fixture["size"][0] / fixture["size"][1]) < 0.01, f"{size} vs {fixture['size']}")
check("the reply starts with the untrusted mark", s["text"].startswith("[screen content: untrusted"))
check("the reply says the image follows", "The image follows this text" in s["text"], s["text"][:300])
check("each control is a mark with the tree's ref", s.get("marks", 0) + s.get("redacted", 0) == len(s.get("refs", {})) >= 5 and s.get("pixels") is False
      and ref(s, 'button "Add one"') is not None, json.dumps({k: s.get(k) for k in ("marks", "pixels", "refs")})[:400])
check("the password field is blacked out, not marked", s.get("redacted") == 1 and "blacked out" in s["text"], s["text"][:400])
# where AT-SPI puts the password field, scaled onto the screenshot: dark all over
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
def find(node, name, depth=0):
    if node is None or depth > 20:
        return None
    if node.get_name() == name and node.get_role_name() == "password text":
        return node
    for i in range(node.get_child_count()):
        hit = find(node.get_child_at_index(i), name, depth + 1)
        if hit:
            return hit
    return None
desk = Atspi.get_desktop(0)
field = next((f for f in (find(desk.get_child_at_index(i), "Password") for i in range(desk.get_child_count())) if f), None)
if field is None:
    check("the password field is found by AT-SPI", False)
else:
    e = field.get_component_iface().get_extents(Atspi.CoordType.WINDOW)
    k = size[0] / fixture["size"][0]
    with Image.open(img) as shot:
        rgb = shot.convert("RGB")
        inner = [rgb.getpixel((round((e.x + dx) * k), round((e.y + dy) * k)))
                 for dx in range(4, e.width - 4, 9) for dy in range(3, e.height - 3, 3)]
    # dark but for the outlines and numbers of the marks beside it, which are drawn over it
    dark = sum(1 for p in inner if max(p) < 70) / max(1, len(inner))
    check("the blacked-out box covers the password field", len(inner) > 10 and dark >= 0.8,
          f"{(e.x, e.y, e.width, e.height)} {dark:.2f} dark")
pw = d("type", ref=ref(s, '"Password"'), text="hunter2")
check("typing into the password field from see is refused", not pw["ok"] and "password" in pw.get("error", ""), json.dumps(pw)[:300])
a = d("act", ref=ref(s, 'button "Add one"'))
time.sleep(0.3)
check("act on a see ref presses the button through AT-SPI", a["ok"] and "CLICKED 1" in logged("app.log"),
      json.dumps(a)[:300] + str(logged("app.log")))

# ---- an app with no tree: marks from its pixels ----
w = d("windows")
p = d("see", ref=ref(w, 'window "Plain fixture"'))
check("see answers for an app with no tree", p["ok"], p.get("error", ""))
check("its marks are regions found in the pixels", p.get("pixels") is True and p.get("marks", 0) >= 3
      and all(v.startswith("region at ") for v in p["refs"].values()), json.dumps(p.get("refs"))[:400])
check("the reply says what a region mark is", "regions found in the pixels" in p["text"], p["text"][:300])
# the "Add one" button's label: the second row, its centre about 40 px down the window
centres = {int(k): tuple(int(n) for n in v.split(" at ")[1].split(",")) for k, v in p["refs"].items()}
add = min(centres, key=lambda k: abs(centres[k][1] - 40) + abs(centres[k][0] - 474) / 10)
check("a mark sits on the Add one button", 28 <= centres[add][1] <= 52, str(centres))
t = d("type", ref=add, text="x")
check("type on a mark from pixels is refused", not t["ok"] and "no accessibility tree" in t.get("error", ""), json.dumps(t)[:300])
p = d("see")  # the type refusal kept the refs; a new see anyway, as the model would
check("see with no ref looks at the window last worked in", p["ok"] and p.get("window") == "Plain fixture", json.dumps(p)[:300])
centres = {int(k): tuple(int(n) for n in v.split(" at ")[1].split(",")) for k, v in p["refs"].items()}
add = min(centres, key=lambda k: abs(centres[k][1] - 40) + abs(centres[k][0] - 474) / 10)
c = d("act", ref=add)
time.sleep(0.4)
check("act on a pixel mark clicks its centre and the app sees it", c["ok"] and "CLICKED 1" in logged("plain.log"),
      json.dumps(c)[:300] + str(logged("plain.log")))
check("the reply names what was clicked", c.get("text", "").find(f"Clicked [{add}] region at") >= 0, c.get("text", "")[:300])
plain = next(x for x in clients() if x["title"] == "Plain fixture")
pos = json.loads(subprocess.run(["hyprctl", "-j", "cursorpos"], capture_output=True, text=True).stdout)
check("the pointer is on the mark's centre", abs(pos["x"] - plain["at"][0] - centres[add][0]) <= 2
      and abs(pos["y"] - plain["at"][1] - centres[add][1]) <= 2, f"{pos} {plain['at']} {centres[add]}")

# ---- stale marks ----
p = d("see")
old = max(int(k) for k in p["refs"])  # past the two windows the next listing numbers
d("windows")
st = d("act", ref=old)
check("a mark from before the last windows is stale", not st["ok"] and "not in the last" in st.get("error", ""), json.dumps(st)[:300])
p = d("see", ref=ref(d("windows"), 'window "Plain fixture"'))
mark = int(next(iter(p["refs"])))
before = logged("plain.log")
# a third window tiles beside the plain fixture, which has the focus: it narrows, and the marks
# taken before are of a window that no longer looks like that
three = subprocess.Popen(["python3", "-I", os.path.join(repo, "tests", "ai-desktop-fixture.py"),
                          "--app-id", "fixture.three", "--title", "Fixture three", "--log", os.path.join(work, "three.log")],
                         env=dict(os.environ, GDK_BACKEND="wayland"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(100):
    if any(x["title"] == "Fixture three" for x in clients()):
        break
    time.sleep(0.1)
time.sleep(0.5)
resized = next(x for x in clients() if x["title"] == "Plain fixture")["size"] != plain["size"]
check("a new window narrowed the plain fixture", resized, str(clients()))
r = d("act", ref=mark)
check("a mark of a window that changed size since the shot is refused", not r["ok"] and "changed size" in r.get("error", ""),
      json.dumps(r)[:300])
check("nothing reached the plain fixture while its marks were stale", logged("plain.log") == before, str(logged("plain.log")))
three.terminate()
three.wait(10)

# ---- files ----
for _ in range(4):
    d("see", ref=ref(d("windows"), 'window "Desktop fixture"'))
check("only the last three screenshots are kept", len([f for f in files() if f.startswith("see-")]) == 3, str(files()))
check("no raw capture is left behind", not any(f.startswith("raw-") for f in files()), str(files()))
check("the shots dir is the user's own", stat.S_IMODE(os.stat(shots).st_mode) == 0o700, oct(os.stat(shots).st_mode))
d.close()
sys.exit(1 if failed else 0)
PY

cat > "$tmp/inner.sh" <<'SH'
set -uo pipefail
work=$1 repo=$2
source "$repo/tests/ai-desktop-session.sh"
ai_desktop_guard || exit 1
ai_desktop_a11y_start || exit 1
# the windows see refuses, on their own: refused, nothing captured
pids=()
ai_desktop_fixture foot "Fake terminal" "$work/term.log" || exit 1
pids+=($!)
ai_desktop_fixture polkit-gnome-authentication-agent-1 "Authentication Required" "$work/auth.log" || exit 1
pids+=($!)
ai_desktop_fixture firefox "Fake browser" "$work/browser.log" || exit 1
pids+=($!)
ai_desktop_fixture org.quickshell "Shell surface" "$work/shell.log" || exit 1
pids+=($!)
python3 -I "$work/drive.py" "$repo/dots/.config/quickshell/koompi/scripts/ai/desktop.py" "$work" refusals "$repo" || exit 1
kill "${pids[@]}" 2> /dev/null
for _ in $(seq 1 50); do
    [[ $(hyprctl -j clients | jq 'length') -eq 0 ]] && break
    sleep 0.1
done
# two windows side by side, one accessible and one with no tree
ai_desktop_fixture desktop.fixture "Desktop fixture" "$work/app.log" || exit 1
NO_AT_BRIDGE=1 ai_desktop_fixture plain.fixture "Plain fixture" "$work/plain.log" || exit 1
sleep 1
python3 -I "$work/drive.py" "$repo/dots/.config/quickshell/koompi/scripts/ai/desktop.py" "$work" see "$repo"
SH

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY bash "$NESTED" bash "$tmp/inner.sh" "$tmp" "$REPO_ROOT"
rc=$?
[[ $rc -eq 77 ]] && { echo "skip: the nested Hyprland could not start here"; exit 0; }
[[ $rc -eq 0 ]] || fail "the desktop driver's see (exit $rc)"
echo "ok: see marks one window, by its tree or its pixels; a mark is acted on, and refused where a ref would be"
