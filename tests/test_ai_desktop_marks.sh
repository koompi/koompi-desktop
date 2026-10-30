#!/usr/bin/env bash
# The pixel half of desktop control (M7), with no compositor: scripts/ai/desktop_pixels.py on
# fixture images drawn here, and the driver's geometry against a made-up Hyprland.
#
#   regions   an app with no tree: each word, button and check box drawn gets one mark, the
#             window's frame and the rules between rows get none, in reading order
#   render    the copy fits 1600x1000, each mark's number is drawn in its colour beside its box,
#             a password field is blacked out, and the same input gives the same bytes
#   pointer   no Wayland display: no capture and no pointer, refused
#   layout    the span a virtual pointer's absolute motion covers: outputs side by side, scaled,
#             rotated, left of 0
#   covering  a click is refused under a floating, fullscreen or pinned window and under the
#             shell's top and overlay layers; not under a window on a hidden workspace
#
# Never starts a compositor and never reads the real session: HYPRLAND_INSTANCE_SIGNATURE and
# WAYLAND_DISPLAY are unset for every Python run.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_ROOT/dots/.config/quickshell/koompi/scripts/ai"
[[ -f $SCRIPTS/desktop_pixels.py && -f $SCRIPTS/desktop.py ]] || { echo "missing the desktop driver" >&2; exit 1; }
python3 -c 'import PIL' 2> /dev/null || { echo "skip: python-pillow not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/marks.py" <<'PY'
import hashlib, importlib.util, json, os, subprocess, sys
scripts, work = sys.argv[1], sys.argv[2]
sys.path.insert(0, scripts)
import desktop_pixels as px
from PIL import Image, ImageDraw
failed = []

def check(name, cond, extra=""):
    print(("PASS  " if cond else "FAIL  ") + name + ("" if cond else f" {extra}"), flush=True)
    if not cond:
        failed.append(name)

def centre(b):
    return b[0] + b[2] / 2, b[1] + b[3] / 2

def holds(b, p):
    return b[0] <= p[0] <= b[0] + b[2] and b[1] <= p[1] <= b[1] + b[3]

# ---- a window with no tree: a frame, words, two buttons, a check box, rules between rows ----
W, H = 900, 620
img = Image.new("RGB", (W, H), (246, 246, 246))
d = ImageDraw.Draw(img)
d.rounded_rectangle([0, 0, W - 1, H - 1], radius=12, outline=(90, 90, 90), width=2)  # the window's frame
f = px.font(22)
drawn = {}
def word(key, xy, text):
    d.text(xy, text, font=f, fill=(20, 20, 20))
    drawn[key] = d.textbbox(xy, text, font=f)
word("count", (60, 50), "Count: 0")
d.rounded_rectangle([60, 120, 300, 170], radius=6, outline=(60, 60, 60), width=2, fill=(230, 230, 230))
word("add", (110, 132), "Add one")
drawn["add-button"] = (60, 120, 300, 170)
d.line([40, 200, W - 40, 200], fill=(225, 225, 225), width=1)  # a faint rule a theme draws between rows
d.rectangle([60, 240, 84, 264], outline=(30, 30, 30), width=2)  # a check box
word("remember", (100, 238), "Remember me")
d.line([40, 300, W - 40, 300], fill=(225, 225, 225), width=1)
d.rounded_rectangle([60, 340, 360, 390], radius=6, outline=(160, 30, 30), width=2, fill=(250, 220, 220))
word("delete", (90, 352), "Delete everything")
drawn["delete-button"] = (60, 340, 360, 390)
word("status", (560, 540), "Ready")
img.save(os.path.join(work, "plain.png"))

boxes, more = px.regions(img)
check("an app with no tree gets marks from its pixels", 4 <= len(boxes) <= 8 and not more, f"{boxes}")
for key in ("count", "remember", "status"):
    c = centre((drawn[key][0], drawn[key][1], drawn[key][2] - drawn[key][0], drawn[key][3] - drawn[key][1]))
    check(f"the word {key!r} has a mark over it", sum(1 for b in boxes if holds(b, c)) == 1, f"{c} {boxes}")
for key in ("add-button", "delete-button"):
    x0, y0, x1, y1 = drawn[key]
    over = [b for b in boxes if holds(b, ((x0 + x1) / 2, (y0 + y1) / 2))]
    check(f"the {key} is one mark, its label inside it", len(over) == 1, f"{over}")
check("the window's frame is not a mark", not any(b[2] > 0.9 * W for b in boxes), f"{boxes}")
check("a faint rule between rows is not a mark", not any(b[3] < 6 for b in boxes), f"{boxes}")
check("the marks are in reading order", [b[1] // 40 for b in boxes] == sorted(b[1] // 40 for b in boxes), f"{boxes}")
check("the same pixels give the same marks", px.regions(img) == (boxes, more))

# ---- render: fit, numbers, redaction, determinism ----
big = img.resize((W * 3, H * 3))  # a 2700x1860 window on a 3x output
marks = [{"n": i + 1, "x": b[0] * 3, "y": b[1] * 3, "w": b[2] * 3, "h": b[3] * 3} for i, b in enumerate(boxes)]
red = [(60 * 3, 450 * 3, 300 * 3, 40 * 3)]
ImageDraw.Draw(big).text((70 * 3, 455 * 3), "hunter2", font=px.font(60), fill=(0, 0, 0))  # a password field's dots, say
out = os.path.join(work, "see.jpg")
s, ow, oh = px.render(big, out, marks, red)
shot = Image.open(out).convert("RGB")
check("the copy fits 1600x1000 and keeps the aspect", shot.size == (ow, oh) and ow <= 1600 and oh <= 1000
      and abs(ow / oh - big.size[0] / big.size[1]) < 0.01, f"{shot.size}")
check("it is a JPEG", open(out, "rb").read(3) == b"\xff\xd8\xff")
rx, ry, rw, rh = [round(v * s) for v in red[0]]
inner = [shot.getpixel((x, y)) for x in range(rx + 4, rx + rw - 4, 7) for y in range(ry + 4, ry + rh - 4, 5)]
check("a password field is blacked out, nothing of it left", all(max(abs(a - b) for a, b in zip(p, px.REDACT)) <= 12 for p in inner),
      f"{[p for p in inner if max(abs(a - b) for a, b in zip(p, px.REDACT)) > 12][:4]}")

def near(colour, p, tol=40):
    return max(abs(a - b) for a, b in zip(colour, p)) <= tol

for m in marks[:3]:
    colour = px.COLOURS[(m["n"] - 1) % len(px.COLOURS)]
    x0, y0, x1, y1 = m["x"] * s, m["y"] * s, (m["x"] + m["w"]) * s, (m["y"] + m["h"]) * s
    around = [(x, y) for x in range(max(0, int(x0) - 40), min(ow, int(x1) + 40))
              for y in range(max(0, int(y0) - 30), min(oh, int(y1) + 30))
              if not (x0 + 3 < x < x1 - 3 and y0 + 3 < y < y1 - 3)]
    hits = sum(1 for p in around if near(colour, shot.getpixel(p)))
    check(f"mark {m['n']} is drawn in its colour around its box", hits > 60, f"{hits} pixels")
first = hashlib.sha256(open(out, "rb").read()).hexdigest()
px.render(big, out, marks, red)
check("the same input gives the same image", hashlib.sha256(open(out, "rb").read()).hexdigest() == first)

# the command line the docs name
cli = subprocess.run([sys.executable, "-I", os.path.join(scripts, "desktop_pixels.py"), "marks",
                      os.path.join(work, "plain.png"), os.path.join(work, "cli.jpg")], capture_output=True, text=True)
got = json.loads(cli.stdout or "{}")
check("desktop_pixels.py marks prints the marks it drew", cli.returncode == 0 and len(got.get("marks", [])) == len(boxes)
      and got.get("width") == W, cli.stderr or cli.stdout)

# ---- no display, no capture and no pointer ----
for what, call in (("capture", lambda: px.capture("18000002", os.path.join(work, "x.png"))), ("pointer", px.VirtualPointer)):
    try:
        call()
        check(f"no Wayland display: {what} refused", False, "it ran")
    except px.PixelError as e:
        check(f"no Wayland display: {what} refused", "refused" in str(e), str(e))
check("nothing was captured", not os.path.exists(os.path.join(work, "x.png")))

# ---- the driver's geometry, against a made-up Hyprland ----
spec = importlib.util.spec_from_file_location("desktop", os.path.join(scripts, "desktop.py"))
desktop = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop)

class FakeHypr:
    problem = ""
    def __init__(self, data):
        self.data = data
    def json(self, what):
        return self.data[what]

drv = desktop.Driver()
check("the driver made here has no Hyprland to reach", bool(drv.hypr.problem), drv.hypr.problem)

def layout(monitors):
    drv.hypr = FakeHypr({"monitors": monitors})
    return drv.layout_box()

check("one output: its logical size", layout([{"x": 0, "y": 0, "width": 2880, "height": 1800, "scale": 1.5}]) == (0, 0, 1920, 1200))
check("two outputs side by side", layout([{"x": 0, "y": 0, "width": 1920, "height": 1080, "scale": 1},
                                          {"x": 1920, "y": 0, "width": 2560, "height": 1440, "scale": 1}]) == (0, 0, 4480, 1440))
check("a rotated output left of 0", layout([{"x": -1080, "y": 0, "width": 1920, "height": 1080, "scale": 1, "transform": 1},
                                            {"x": 0, "y": 0, "width": 1920, "height": 1080, "scale": 1}]) == (-1080, 0, 3000, 1920))

app = {"address": "0xa", "class": "fixture.plain", "title": "Plain", "at": [0, 0], "size": [900, 620],
       "workspace": {"id": 1}, "floating": False}
def cover(others, layers=None, x=200, y=150):
    drv.hypr = FakeHypr({"monitors": [{"activeWorkspace": {"id": 1}, "specialWorkspace": {"id": 0}}],
                         "clients": [app] + others, "layers": layers or {}})
    return drv.covering(app, x, y)

popup = {"address": "0xb", "class": "other", "title": "Popup", "at": [100, 100], "size": [300, 200],
         "workspace": {"id": 1}, "floating": True}
check("nothing over the point: the click may go", cover([]) == "")
check("a floating window over a tiled one covers it", "Popup" in cover([popup]))
check("a window beside the point does not", cover([popup], x=600, y=500) == "")
check("a window on a hidden workspace does not", cover([dict(popup, workspace={"id": 4})]) == "")
check("a fullscreen window covers it", "Full" in cover([dict(popup, title="Full", floating=False, fullscreen=2,
                                                            at=[0, 0], size=[1920, 1080])]))
check("a tiled window beside a floating one does not cover it",
      (app.update(floating=True), cover([dict(popup, floating=False)]), app.update(floating=False))[1] == "")
bar = {"DP-1": {"levels": {"2": [{"namespace": "quickshell:bar", "x": 0, "y": 0, "w": 1920, "h": 40}],
                           "3": [{"namespace": "quickshell:notifications", "x": 1500, "y": 40, "w": 400, "h": 120}]}}}
check("the shell's bar covers the top of the window", "quickshell:bar" in cover([], bar, y=20))
check("a notification covers its corner", "notifications" in cover([], bar, x=1600, y=100))
check("the background layer does not", cover([], {"DP-1": {"levels": {"0": [{"namespace": "wallpaper", "x": 0, "y": 0,
                                                                              "w": 1920, "h": 1080}]}}}) == "")

sys.exit(1 if failed else 0)
PY

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY python3 -I "$tmp/marks.py" "$SCRIPTS" "$tmp" \
    || { echo "FAIL: desktop marks" >&2; exit 1; }
echo "ok: marks from the pixels of an app with no tree, drawn to fit, password fields blacked out; clicks only where nothing covers"
