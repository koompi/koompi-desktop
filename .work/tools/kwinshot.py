#!/usr/bin/env python3
# needs kwin started with KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402 require_version must run first
from PIL import Image  # noqa: E402 require_version must run first

MODES = {4: ("RGBX", "BGRX"), 5: ("RGBX", "BGRX"), 6: ("RGBA", "BGRA"), 17: ("RGBA", "RGBA")}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: kwinshot.py OUT.png", file=sys.stderr)
        return 2
    out = sys.argv[1]
    read_fd, write_fd = os.pipe()
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    fds = Gio.UnixFDList.new()
    idx = fds.append(write_fd)
    os.close(write_fd)
    reply, _ = bus.call_with_unix_fd_list_sync(
        "org.kde.KWin.ScreenShot2", "/org/kde/KWin/ScreenShot2", "org.kde.KWin.ScreenShot2",
        "CaptureWorkspace", GLib.Variant("(a{sv}h)", ({}, idx)), GLib.VariantType("(a{sv})"),
        Gio.DBusCallFlags.NONE, 10000, fds, None)
    del fds
    meta = reply.unpack()[0]
    data = b""
    with os.fdopen(read_fd, "rb") as pipe:
        while chunk := pipe.read(1 << 20):
            data += chunk
    width, height, stride, fmt = meta["width"], meta["height"], meta["stride"], meta["format"]
    if fmt not in MODES:
        print(f"kwinshot: unknown QImage format {fmt}", file=sys.stderr)
        return 1
    mode, raw = MODES[fmt]
    Image.frombuffer(mode, (width, height), data, "raw", raw, stride, 1).convert("RGB").save(out)
    print(f"kwinshot: {out} {width}x{height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
