#!/usr/bin/env python3
"""A small GTK 3 window for the desktop-control tests (test_ai_desktop.sh, test_ai_desktop_tool.sh).

ai-desktop-fixture.py --app-id CLASS --title TITLE --log FILE

CLASS becomes the Wayland app id, so one script stands in for an app, a terminal,
a polkit agent, a browser or a shell surface. Every effect is one line in FILE:
CLICKED n, TEXT <name field>, PW <password field>, TOGGLED True|False, DELETED,
KEY <keyval> <ctrl|->.
"""
import argparse
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--app-id", dest="cls", required=True)  # GTK takes --class for itself
ap.add_argument("--title", required=True)
ap.add_argument("--log", required=True)
args = ap.parse_args()
GLib.set_prgname(args.cls)


def log(line):
    with open(args.log, "a") as f:
        f.write(line + "\n")


def named(widget, name):
    widget.get_accessible().set_name(name)
    return widget


w = Gtk.Window(title=args.title)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
count = Gtk.Label(label="Count: 0")
add = Gtk.Button(label="Add one")


def added(_):
    n = int(count.get_text().split(": ")[1]) + 1
    count.set_text(f"Count: {n}")
    log(f"CLICKED {n}")


add.connect("clicked", added)
name = named(Gtk.Entry(), "Name")
name.connect("changed", lambda e: log(f"TEXT {e.get_text()}"))
password = named(Gtk.Entry(), "Password")
password.set_visibility(False)
password.connect("changed", lambda e: log(f"PW {e.get_text()}"))
remember = Gtk.CheckButton(label="Remember me")
remember.connect("toggled", lambda c: log(f"TOGGLED {c.get_active()}"))
delete = Gtk.Button(label="Delete everything")
delete.connect("clicked", lambda _: log("DELETED"))
for widget in (count, add, name, password, remember, delete):
    box.add(widget)


def key(_, event):
    ctrl = "ctrl" if event.state & Gdk.ModifierType.CONTROL_MASK else "-"
    log(f"KEY {Gdk.keyval_name(event.keyval)} {ctrl}")
    return False


w.connect("key-press-event", key)
w.add(box)
w.connect("destroy", Gtk.main_quit)
w.show_all()
log("READY")
Gtk.main()
sys.exit(0)
