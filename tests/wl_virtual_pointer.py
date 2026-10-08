#!/usr/bin/env python3
"""wl_virtual_pointer.py WIDTH HEIGHT < fifo: a virtual pointer for a nested compositor.

Prints "ready", then moves to each "X Y" line (pixels of a WIDTH x HEIGHT output) and prints "moved X Y".
Ends on EOF or when the compositor goes. Nested under headless KWin, Hyprland has no pointer and
hl.dsp.cursor.move reaches no client; this gives it one over zwlr_virtual_pointer_v1.
"""
import os
import select
import socket
import struct
import sys


def pad(n):
    return (n + 3) & ~3


def string_arg(text):
    raw = text.encode() + b"\0"
    return struct.pack("<I", len(raw)) + raw + b"\0" * (pad(len(raw)) - len(raw))


class Wire:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buf = b""
        self.ids = 1

    def new_id(self):
        self.ids += 1
        return self.ids

    def request(self, obj, opcode, payload=b""):
        self.sock.sendall(struct.pack("<II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    def event(self):
        while True:
            if len(self.buf) >= 8:
                obj, head = struct.unpack_from("<II", self.buf)
                size, opcode = head >> 16, head & 0xFFFF
                if len(self.buf) >= size:
                    body = self.buf[8:size]
                    self.buf = self.buf[size:]
                    if obj == 1 and opcode == 0:
                        target, code = struct.unpack_from("<II", body)
                        raise RuntimeError(f"wl_display.error on object {target}, code {code}")
                    return obj, opcode, body
            data = self.sock.recv(65536)
            if not data:
                raise ConnectionError("the compositor closed the connection")
            self.buf += data

    def roundtrip(self):
        callback = self.new_id()
        self.request(1, 0, struct.pack("<I", callback))
        events = []
        while True:
            obj, opcode, body = self.event()
            if obj == callback and opcode == 0:
                return events
            events.append((obj, opcode, body))


def create_pointer(wire):
    registry = wire.new_id()
    wire.request(1, 1, struct.pack("<I", registry))
    advertised = {}
    for obj, opcode, body in wire.roundtrip():
        if obj == registry and opcode == 0:
            name, length = struct.unpack_from("<II", body)
            interface = body[8:8 + length - 1].decode()
            (version,) = struct.unpack_from("<I", body, 8 + pad(length))
            advertised[interface] = (name, version)

    def bind(interface):
        name, version = advertised[interface]
        obj = wire.new_id()
        wire.request(registry, 0, struct.pack("<I", name) + string_arg(interface) + struct.pack("<II", 1, obj))
        return obj

    seat = bind("wl_seat")
    manager = bind("zwlr_virtual_pointer_manager_v1")
    pointer = wire.new_id()
    wire.request(manager, 0, struct.pack("<II", seat, pointer))
    wire.roundtrip()
    return pointer


def main():
    width, height = int(sys.argv[1]), int(sys.argv[2])
    runtime = os.environ["XDG_RUNTIME_DIR"]
    if os.path.realpath(runtime) == os.path.realpath(f"/run/user/{os.getuid()}"):
        sys.exit("refusing to give the logged-in session a second pointer")
    wire = Wire(os.path.join(runtime, os.environ["WAYLAND_DISPLAY"]))
    pointer = create_pointer(wire)
    print("ready", flush=True)

    clock = 1000
    pending = b""
    while True:
        readable, _, _ = select.select([0, wire.sock], [], [])
        if wire.sock in readable:
            data = wire.sock.recv(65536)
            if not data:
                return
            wire.buf += data
        if 0 not in readable:
            continue
        chunk = os.read(0, 4096)
        if not chunk:
            return
        pending += chunk
        while b"\n" in pending:
            line, pending = pending.split(b"\n", 1)
            parts = line.split()
            if len(parts) != 2:
                continue
            x, y = int(parts[0]), int(parts[1])
            clock += 10
            wire.request(pointer, 1, struct.pack("<IIIII", clock, x, y, width, height))
            wire.request(pointer, 4)
            wire.roundtrip()
            print(f"moved {x} {y}", flush=True)


if __name__ == "__main__":
    main()
