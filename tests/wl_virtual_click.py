#!/usr/bin/env python3
"""wl_virtual_click.py WIDTH HEIGHT X Y: move a virtual pointer to X Y of a WIDTH x HEIGHT output and click once.

Same virtual pointer as wl_virtual_pointer.py, plus a left button press and release.
"""
import os
import struct
import sys
import time

from wl_virtual_pointer import Wire, create_pointer

BTN_LEFT = 0x110


def main():
    width, height, x, y = (int(v) for v in sys.argv[1:5])
    runtime = os.environ["XDG_RUNTIME_DIR"]
    if os.path.realpath(runtime) == os.path.realpath(f"/run/user/{os.getuid()}"):
        sys.exit("refusing to give the logged-in session a second pointer")
    wire = Wire(os.path.join(runtime, os.environ["WAYLAND_DISPLAY"]))
    pointer = create_pointer(wire)
    # the second move lands once the surface under the pointer has its enter
    for clock, dx in ((1010, 0), (1015, 1)):
        wire.request(pointer, 1, struct.pack("<IIIII", clock, x + dx, y, width, height))
        wire.request(pointer, 4)
        wire.roundtrip()
        time.sleep(0.4)
    for clock, state in ((1020, 1), (1030, 0)):
        wire.request(pointer, 2, struct.pack("<III", clock, BTN_LEFT, state))
        wire.request(pointer, 4)
        wire.roundtrip()


if __name__ == "__main__":
    main()
