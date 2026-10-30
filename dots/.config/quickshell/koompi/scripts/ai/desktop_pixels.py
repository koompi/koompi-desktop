#!/usr/bin/env python3
"""The pixel half of desktop control (M7): a window's screenshot with numbered marks, and a click.

desktop.py imports this for its `see` op and for `act` on a mark that has no accessibility
element behind it. The model reads screens well and points badly (docs/design/ai-agent-plan.md,
"Vision on the local model"), so it never gives an x,y: it names a mark, and the mark's
element (AT-SPI) or its centre (pixels) is what is acted on.

- capture(): one toplevel through `grim -T <id>` (ext-foreign-toplevel + image-copy-capture),
  so the shot holds that window's own pixels and nothing drawn over it: no chat sidebar, no
  notification, no other window. A whole output is never captured.
- regions(): marks for an app that publishes no accessibility tree. The edges of the image,
  thickened so the glyphs of a word or the border of a button join up, then each connected
  blob is one mark. A grid's cells rarely centre on a control; a blob is a word, an icon or
  a button the model can read and name.
- render(): the marks drawn on a copy scaled to fit 1600x1000, password fields blacked out.
- Pointer: a click through the compositor's wlr virtual-pointer protocol, spoken directly on
  WAYLAND_DISPLAY (no ydotool: uinput would reach every compositor on the seat, not this one).

Needs python-pillow for images; the pointer needs only the stdlib.

    desktop_pixels.py marks IN.png OUT.jpg [BOXES.json]   # prints the marks as JSON (tests)
"""
import json
import os
import socket
import struct
import subprocess
import sys
import time

MAX_W, MAX_H = 1600, 1000
MAX_REGIONS = 60
WORK_W = 480  # the width regions are found at
# How strong an edge counts: text, icons and check boxes are, the faint 1 px lines a theme
# draws between controls are not (they would join every row of a form into one blob)
EDGE = int(os.environ.get("KOOMPI_AI_MARK_EDGE", "64"))
COLOURS = [(220, 38, 38), (37, 99, 235), (22, 163, 74), (217, 119, 6), (147, 51, 234), (8, 145, 178)]
REDACT = (40, 40, 40)


class PixelError(Exception):
    pass


def pil():
    try:
        from PIL import Image, ImageDraw, ImageFilter, ImageFont
    except ImportError:
        raise PixelError("python-pillow is not installed, so no screenshot can be marked")
    return Image, ImageDraw, ImageFilter, ImageFont


# ---- capture ----

def capture(toplevel_id, path):
    """The window with this ext-foreign-toplevel identifier (Hyprland's stableId) as a PNG."""
    if not toplevel_id:
        raise PixelError("this Hyprland names no toplevel id for the window, so it cannot be captured alone")
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise PixelError("refused: no Wayland display in this environment")
    try:
        r = subprocess.run(["grim", "-T", str(toplevel_id), path], capture_output=True, text=True, timeout=10)
    except FileNotFoundError:
        raise PixelError("grim is not installed, so no screenshot can be taken")
    except subprocess.TimeoutExpired:
        raise PixelError("the screenshot did not arrive within 10 s")
    if r.returncode != 0 or not os.path.exists(path):
        raise PixelError(f"grim could not capture the window: {(r.stderr or '').strip()[:160]}")


# ---- marks from pixels ----

def regions(img):
    """Boxes (x, y, w, h) in img's pixels, in reading order, for an app with no tree."""
    Image, ImageDraw, ImageFilter, _ = pil()
    from PIL import ImageChops
    w, h = img.size
    f = min(1.0, WORK_W / max(1, w))
    sw, sh = max(1, round(w * f)), max(1, round(h * f))
    small = img.convert("L").resize((sw, sh), Image.BILINEAR)
    edges = small.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > EDGE else 0)
    # the window's own border and rounded corners would join every control into one blob
    ImageDraw.Draw(edges).rectangle([0, 0, sw - 1, sh - 1], outline=0, width=3)
    # a word's glyphs join into one blob: wide sideways, barely up and down, so stacked
    # rows stay apart (the margin above is blank, so offset's wrap-around brings in nothing)
    grown = edges
    for dx, dy in ((-2, 0), (-1, 0), (1, 0), (2, 0), (0, -1), (0, 1)):
        grown = ImageChops.lighter(grown, ImageChops.offset(edges, dx, dy))
    data = bytearray(grown.tobytes())
    boxes = []
    for start in range(sw * sh):
        if data[start] != 255:
            continue
        data[start] = 1
        stack = [start]
        x0, y0, x1, y1 = sw, sh, 0, 0
        while stack:
            p = stack.pop()
            y, x = divmod(p, sw)
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            if x > 0 and data[p - 1] == 255:
                data[p - 1] = 1
                stack.append(p - 1)
            if x < sw - 1 and data[p + 1] == 255:
                data[p + 1] = 1
                stack.append(p + 1)
            if y > 0 and data[p - sw] == 255:
                data[p - sw] = 1
                stack.append(p - sw)
            if y < sh - 1 and data[p + sw] == 255:
                data[p + sw] = 1
                stack.append(p + sw)
        bw, bh = x1 - x0 + 1, y1 - y0 + 1
        if bw * bh < 30 or bw < 4 or bh < 6:
            continue  # specks, and rules (a 3 px focus line is 5 high once grown)
        if bw * bh > 0.25 * sw * sh or (bw > 0.97 * sw and bh > 0.5 * sh):
            continue  # panels and the window's own frame
        boxes.append((x0, y0, bw, bh))
    # a control-sized box swallows what is inside it: a button's label is the button
    kept = []
    for b in sorted(boxes, key=lambda b: -b[2] * b[3]):
        inside = any(k[0] <= b[0] and k[1] <= b[1] and b[0] + b[2] <= k[0] + k[2] and b[1] + b[3] <= k[1] + k[3]
                     and k[2] * k[3] <= 0.06 * sw * sh for k in kept)
        if not inside:
            kept.append(b)
    # back to img's pixels, the 1-2 px the thickening added taken off again
    out = []
    for x, y, bw, bh in kept:
        out.append((round((x + 1) / f), round((y + 1) / f), max(4, round((bw - 2) / f)), max(4, round((bh - 2) / f))))
    band = max(8, round(12 / f))
    out.sort(key=lambda b: (b[1] // band, b[0]))
    return out[:MAX_REGIONS], len(out) > MAX_REGIONS


# ---- rendering ----

def fit(w, h):
    s = min(1.0, MAX_W / max(1, w), MAX_H / max(1, h))
    return s, max(1, round(w * s)), max(1, round(h * s))


def font(size):
    _, _, _, ImageFont = pil()
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow before 10.1: the fixed bitmap font
        return ImageFont.load_default()


def render(src, out, marks, redact=()):
    """Draw `marks` ([{n, x, y, w, h}] in src's pixels) on a copy scaled to fit; black out `redact`.
    Returns (scale, width, height) of what was written."""
    Image, ImageDraw, _, _ = pil()
    img = src.convert("RGB")
    draw = ImageDraw.Draw(img)
    for x, y, w, h in redact:
        draw.rectangle([x, y, x + w - 1, y + h - 1], fill=REDACT)
    s, ow, oh = fit(*img.size)
    if s < 1.0:
        img = img.resize((ow, oh), Image.LANCZOS)
    draw = ImageDraw.Draw(img)
    label_font = font(14)
    boxes = []
    for m in marks:
        x0, y0 = round(m["x"] * s), round(m["y"] * s)
        boxes.append((x0, y0, max(x0 + 2, round((m["x"] + m["w"]) * s) - 1), max(y0 + 2, round((m["y"] + m["h"]) * s) - 1)))
    for m, (x0, y0, x1, y1) in zip(marks, boxes):  # 2 px out, so the outline does not touch the text
        draw.rectangle([max(0, x0 - 2), max(0, y0 - 2), min(ow - 1, x1 + 2), min(oh - 1, y1 + 2)],
                       outline=COLOURS[(m["n"] - 1) % len(COLOURS)], width=2)
    placed = []
    for m, box in zip(marks, boxes):
        colour = COLOURS[(m["n"] - 1) % len(COLOURS)]
        text = str(m["n"])
        l, t, r, b = draw.textbbox((0, 0), text, font=label_font)
        lw, lh = r - l + 6, b - t + 4
        lx, ly = label_spot(box, lw, lh, ow, oh, boxes, placed)
        placed.append((lx, ly, lx + lw - 1, ly + lh - 1))
        draw.rectangle(placed[-1], fill=colour)
        draw.text((lx + 3 - l, ly + 2 - t), text, font=label_font, fill=(255, 255, 255))
    img.save(out, "JPEG", quality=85)
    return s, ow, oh


def label_spot(box, lw, lh, ow, oh, boxes, placed):
    """Where a mark's number goes: left of its box, above it, or inside its corner, whichever
    stays in the image and covers the fewest other numbers and boxes (a number over text
    hides what the model needs to read)."""
    x0, y0, x1, y1 = box

    def hits(r):
        a = sum(4 for p in placed if r[0] <= p[2] and p[0] <= r[2] and r[1] <= p[3] and p[1] <= r[3])
        return a + sum(1 for q in boxes if q is not box and r[0] <= q[2] and q[0] <= r[2] and r[1] <= q[3] and q[1] <= r[3])

    best = None
    for n, (lx, ly) in enumerate(((x0 - lw, y0), (x0, y0 - lh), (x1 + 1, y0), (x0, y1 + 1), (x0, y0))):
        lx, ly = min(max(0, lx), max(0, ow - lw)), min(max(0, ly), max(0, oh - lh))
        r = (lx, ly, lx + lw - 1, ly + lh - 1)
        inside = r[0] < x1 and x0 < r[2] and r[1] < y1 and y0 < r[3]
        score = (hits(r), 2 if inside else 0, n)
        if best is None or score < best[0]:
            best = (score, (lx, ly))
    return best[1]


# ---- the pointer ----

BTN_LEFT = 0x110


class VirtualPointer:
    """zwlr_virtual_pointer_v1 on this environment's WAYLAND_DISPLAY, over the wire protocol."""

    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY", "")
        if not name:
            raise PixelError("refused: no Wayland display in this environment")
        path = name if name.startswith("/") else os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(3)
        try:
            self.sock.connect(path)
        except OSError as e:
            raise PixelError(f"the compositor's display {name} did not answer: {e}")
        self.buf = b""
        self.next_id = 1  # the display is 1; a client's next new id must be the lowest unused (2)
        self.globals = {}
        self.registry_id = self.new_id()
        self.send(1, 1, struct.pack("<I", self.registry_id))  # wl_display.get_registry
        self.roundtrip()
        seat = self.bind("wl_seat", 1)
        manager = self.bind("zwlr_virtual_pointer_manager_v1", 1)
        if not seat or not manager:
            raise PixelError("the compositor offers no virtual pointer, so nothing can be clicked by pixels")
        self.ptr = self.new_id()
        self.send(manager, 0, struct.pack("<II", seat, self.ptr))  # create_virtual_pointer(seat, id)
        self.roundtrip()

    def new_id(self):
        self.next_id += 1
        return self.next_id

    def send(self, obj, opcode, payload=b""):
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    @staticmethod
    def string(s):
        raw = s.encode() + b"\0"
        return struct.pack("<I", len(raw)) + raw + b"\0" * (-len(raw) % 4)

    def bind(self, interface, version):
        if interface not in self.globals:
            return 0
        oid = self.new_id()
        self.send(self.registry_id, 0, struct.pack("<I", self.globals[interface])
                  + self.string(interface) + struct.pack("<II", version, oid))
        return oid

    def roundtrip(self):
        registry = self.registry_id
        done = self.new_id()
        self.send(1, 0, struct.pack("<I", done))  # wl_display.sync
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            while len(self.buf) >= 8:
                obj, word = struct.unpack_from("<II", self.buf)
                size, opcode = word >> 16, word & 0xFFFF
                if len(self.buf) < size:
                    break
                body, self.buf = self.buf[8:size], self.buf[size:]
                if obj == 1 and opcode == 0:  # wl_display.error
                    _, code, length = struct.unpack_from("<III", body)
                    raise PixelError(f"the compositor refused the pointer: {body[12:12 + length - 1].decode(errors='replace')}")
                if obj == registry and opcode == 0:  # wl_registry.global
                    gname, length = struct.unpack_from("<II", body)
                    iface = body[8:8 + length - 1].decode(errors="replace")
                    self.globals.setdefault(iface, gname)
                if obj == done:
                    return
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                raise PixelError("the compositor closed the connection")
            self.buf += chunk
        raise PixelError("the compositor did not answer in time")

    @staticmethod
    def now():
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    def move(self, x, y, width, height):
        self.send(self.ptr, 1, struct.pack("<IIIII", self.now(), max(0, int(x)), max(0, int(y)), int(width), int(height)))
        self.send(self.ptr, 4)  # frame
        self.roundtrip()

    def click(self):
        for state in (1, 0):
            self.send(self.ptr, 2, struct.pack("<III", self.now(), BTN_LEFT, state))
            self.send(self.ptr, 4)
            self.roundtrip()
            time.sleep(0.05)

    def close(self):
        try:
            self.send(self.ptr, 8)  # destroy
            self.roundtrip()
        except (PixelError, OSError):
            pass
        self.sock.close()


def main(argv):
    if len(argv) < 3 or argv[0] != "marks":
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    Image = pil()[0]
    src = Image.open(argv[1])
    redact = []
    if len(argv) > 3:
        given = json.load(open(argv[3]))
        boxes = [tuple(b["box"]) for b in given.get("marks", [])]
        redact = [tuple(b) for b in given.get("redact", [])]
        more = False
    else:
        boxes, more = regions(src)
    marks = [{"n": i + 1, "x": b[0], "y": b[1], "w": b[2], "h": b[3]} for i, b in enumerate(boxes)]
    s, w, h = render(src, argv[2], marks, redact)
    print(json.dumps({"scale": s, "width": w, "height": h, "more": more, "marks": marks}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
