#!/usr/bin/env python3
"""End-to-end tests for the global-menu daemon.

The daemon is run in --test mode, which keeps everything except the compositor:
it still owns com.canonical.AppMenu.Registrar and still talks real D-Bus, but
the focused window is chosen over stdin instead of being read from Hyprland.

Two stand-in applications are started on the session bus, one exporting
org.gtk.Menus (GTK) and one exporting com.canonical.dbusmenu (Qt/KDE), and both
are driven the way the shell drives them: read the menu, click an item, assert
the application saw the click.

Restarts live in test_restart.py, menubars nobody registered in
test_unregistered.py, and what they share in harness.py.

Run: python3 tests/test_daemon.py   (after `cargo build --release`; tests/test_globalmenu.sh does both)
"""

import os
import subprocess
import sys
import tempfile
import time

import harness
import test_restart
import test_unregistered
from harness import DAEMON, Daemon, check, find, gdbus, start_mock, stop_mock, wait_for


def test_gtk(daemon, log):
    print("org.gtk.Menus (GTK applications)")
    app = start_mock("mock_gtk_app.py", log)
    try:
        daemon.send(
            "gtk org.koompi.test.GtkApp /org/koompi/test/GtkApp/menus/menubar "
            "/org/koompi/test/GtkApp /org/koompi/test/GtkApp/window/1"
        )
        payload = daemon.read()
        items = payload["items"]

        check([i["label"] for i in items] == ["File", "View"], "menubar is File, View")

        file_items = items[0]["items"]
        labels = [i["label"] for i in file_items]
        check(
            labels == ["New Window", "Open...", "", "Print", "Quit"],
            "sections are spliced in order with a separator: %s" % labels,
        )
        check(file_items[2]["sep"] is True, "the section boundary is a separator")
        check(find(items, "Print")["enabled"] is False, "a disabled action is greyed out")
        check(find(items, "Deep One" or "") is None, "unknown labels are not invented")
        check(find(items, "Deep Item") is not None, "a nested submenu is resolved")

        sidebar = find(items, "Show Sidebar")
        check(sidebar["toggle"] and sidebar["checked"], "boolean state renders as a check")
        grid = find(items, "Grid")
        list_item = find(items, "List")
        check(grid["toggle"] and grid["checked"], "the selected radio entry is checked")
        check(list_item["toggle"] and not list_item["checked"], "the other radio entry is not")

        check(all("_" not in i["label"] for i in items), "mnemonics are stripped")
        check(items[0].get("sub") is True, "a GTK submenu is marked as one")
        check(find(items, "Quit").get("sub") is None, "a GTK leaf is not")

        daemon.send_item("activate", find(items, "Quit")["id"])
        daemon.send_item("activate", find(items, "List")["id"])
        content = wait_for(log, lambda c: "quit" in c and "layout" in c)
        check("quit -\n" in content, "clicking Quit invoked app.quit")
        check("layout 'list'\n" in content, "clicking List invoked win.layout('list')")
    finally:
        stop_mock(app)


def test_dbusmenu(daemon, log):
    print("com.canonical.dbusmenu (Qt/KDE applications)")
    app = start_mock("mock_dbusmenu_app.py", log, 4242)
    try:
        registered = subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", "com.canonical.AppMenu.Registrar",
                "--object-path", "/com/canonical/AppMenu/Registrar",
                "--method", "com.canonical.AppMenu.Registrar.GetMenuForWindow",
                "4242",
            ],
            capture_output=True,
            text=True,
        )
        check(
            "/MenuBar" in registered.stdout,
            "the daemon's registrar answers GetMenuForWindow: %s"
            % (registered.stdout or registered.stderr).strip(),
        )

        daemon.send("dbusmenu org.koompi.test.QtApp /MenuBar")
        payload = daemon.read()
        items = payload["items"]

        check([i["label"] for i in items] == ["File", "Tools"], "invisible entries are dropped")
        file_items = items[0]["items"]
        check(
            [i["label"] for i in file_items] == ["New", "", "Quit"],
            "the layout keeps separators in place",
        )
        check(file_items[1]["sep"] is True, "separator type is honoured")
        check(file_items[2]["enabled"] is False, "a disabled entry is greyed out")

        tools = items[1]
        check(tools.get("items", []) == [], "a lazily built submenu starts empty")
        # Without this the shell cannot tell an empty submenu from a leaf, and
        # clicking Tools would activate it instead of opening it.
        check(tools.get("sub") is True, "an empty submenu still says it is one")
        check(items[0].get("sub") is True, "a populated submenu says so too")
        check(find(items, "New").get("sub") is None, "a leaf is not marked as a submenu")

        daemon.send_item("open", tools["id"])
        patch = daemon.read()
        check(patch.get("patch") == tools["id"], "opening it produces a patch for that item")
        check(
            patch.get("gen") == payload.get("gen"),
            "a patch stays inside the payload's id space rather than opening a new one",
        )
        check(
            [i["label"] for i in patch["items"]] == ["Preferences"],
            "the patch carries the entries the app built on AboutToShow",
        )
        pref = patch["items"][0]
        check(pref["toggle"] and pref["checked"], "toggle state survives the patch")
        check(pref.get("sub") is None, "a patched leaf is not marked as a submenu")

        daemon.send_item("activate", pref["id"])
        content = wait_for(log, lambda c: "event 7 clicked" in c)
        check("event 7 clicked" in content, "clicking a patched entry sends Event(clicked)")

        daemon.send_item("activate", find(items, "New")["id"])
        content = wait_for(log, lambda c: "event 2 clicked" in c)
        check("event 2 clicked" in content, "clicking a top-level entry sends Event(clicked)")

        test_stale_generation(daemon, log, items)
    finally:
        stop_mock(app)


def test_stale_generation(daemon, log, items):
    """A click the user made just before focus moved must not land on the menu
    that replaced it. Ids are per-payload and reused, so "activate 2" against
    the old File menu would otherwise invoke whatever is now item 2."""
    print("commands queued against a menu that has been replaced")
    new_id = find(items, "New")["id"]
    stale_gen = daemon.generation

    # Re-publish. Same application, but the table is rebuilt from scratch, so
    # every id the shell was holding now belongs to the previous generation.
    daemon.send("dbusmenu org.koompi.test.QtApp /MenuBar")
    daemon.read()
    check(daemon.generation != stale_gen, "a replacement payload carries a new generation")

    with open(log) as fh:
        before = fh.read().count("event 2 clicked")

    # The stale click first, then a current one. Commands are processed in
    # order, so once the second has landed the first has had its chance.
    daemon.send_item("activate", new_id, generation=stale_gen)
    daemon.send_item("activate", new_id)
    wait_for(log, lambda c: c.count("event 2 clicked") > before)

    with open(log) as fh:
        after = fh.read().count("event 2 clicked")
    check(
        after == before + 1,
        "the stale click is dropped and only the current one reaches the app "
        "(%d click(s) landed, expected 1)" % (after - before),
    )

    # An unversioned command cannot be checked at all, so it is refused too.
    daemon.send("activate %d" % new_id)
    daemon.send_item("activate", new_id)
    wait_for(log, lambda c: c.count("event 2 clicked") > after)
    with open(log) as fh:
        final = fh.read().count("event 2 clicked")
    check(
        final == after + 1,
        "a command naming no generation is refused "
        "(%d click(s) landed, expected 1)" % (final - after),
    )


def test_patch_names_the_generation_it_was_asked_for(daemon, log):
    """A patch splices children into the payload the shell is holding, keyed by
    an id from that payload. If it ever came back stamped with a generation its
    children do not belong to, the shell's own `payload.gen !== generation`
    check would wave it through and hang one application's submenu off another
    application's item id.

    The application sits on AboutToShow for a second and a half, so the whole
    open request is in flight while a replacement payload is already queued
    behind it. That is the window the guard has to survive."""
    print("a patch issued while a replacement payload is queued")
    app = start_mock("mock_dbusmenu_app.py", log, 4248, "org.koompi.test.SlowApp", 1.5)
    try:
        daemon.send("dbusmenu org.koompi.test.SlowApp /MenuBar")
        payload = daemon.read()
        asked_gen = payload["gen"]
        tools = find(payload["items"], "Tools")

        daemon.send_item("open", tools["id"], generation=asked_gen)
        time.sleep(0.3)  # the daemon is inside AboutToShow by now
        daemon.send("dbusmenu org.koompi.test.SlowApp /MenuBar")

        patch = daemon.read()
        check(patch.get("patch") == tools["id"], "the patch answers the open: %r" % patch)
        check(
            patch.get("gen") == asked_gen,
            "the patch names the generation the open was issued under, not the "
            "one current when it was answered (%r, asked under %r)"
            % (patch.get("gen"), asked_gen),
        )

        replacement = daemon.read()
        check(
            replacement.get("patch") is None and replacement.get("gen") != asked_gen,
            "the queued replacement is only published afterwards, in a new id "
            "space: %r" % {k: v for k, v in replacement.items() if k != "items"},
        )

        # And an open against the payload that has just been replaced answers
        # nothing at all, so no children can arrive for a dead id space.
        daemon.send_item("open", tools["id"], generation=asked_gen)
        daemon.send("dbusmenu org.koompi.test.SlowApp /MenuBar")
        after = daemon.read()
        check(
            after.get("patch") is None,
            "an open naming the replaced generation produces no patch: %r" % after,
        )
    finally:
        stop_mock(app)


def test_no_menu(daemon):
    print("applications with no exported menu")
    daemon.send("dbusmenu org.koompi.test.Nothing /MenuBar")
    payload = daemon.read()
    check(payload["items"] == [], "an app that does not answer yields an empty menu, not a stall: %r" % payload)


def test_register_window_answers_promptly(daemon):
    print("RegisterWindow answers without stalling the application")
    # Qt's QDBusMenuBar makes this call synchronously from QMenuBar's
    # constructor, so every millisecond spent here is a millisecond the
    # window is not on screen. The registrar looks up the caller's pid on the
    # same connection it is answering on; if that lookup blocks the executor,
    # its reply is never read and the call sits on the 3 s method timeout.
    started = time.monotonic()
    gdbus("com.canonical.AppMenu.Registrar", "RegisterWindow", 4300, "/MenuBar/1")
    elapsed = time.monotonic() - started
    check(elapsed < 1.0, "RegisterWindow returned in %.3fs" % elapsed)
    gdbus("com.canonical.AppMenu.Registrar", "UnregisterWindow", 4300)


def main():
    if not os.path.exists(DAEMON):
        sys.exit("build the daemon first: cargo build --release")

    # Only one process per bus can own com.canonical.AppMenu.Registrar, and on a
    # live KOOMPI session that is the running daemon. Re-run ourselves on a
    # private bus so the tests never depend on, or disturb, the real session.
    if not os.environ.get("KOOMPI_GLOBAL_MENU_TEST_BUS"):
        # A private bus AND a private XDG_RUNTIME_DIR. The registrar mirrors its
        # table to $XDG_RUNTIME_DIR/koompi-global-menu.registry, so without this
        # the tests read the live daemon's mirror, find none of its unique names
        # on our bus, and write the emptied table back over it.
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(
                os.environ,
                KOOMPI_GLOBAL_MENU_TEST_BUS="1",
                XDG_RUNTIME_DIR=runtime,
            )
            sys.exit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__], env=env))

    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "activations.log")
        open(log, "w").close()
        daemon = Daemon()
        try:
            test_gtk(daemon, log)
            test_dbusmenu(daemon, log)
            test_patch_names_the_generation_it_was_asked_for(daemon, log)
            test_no_menu(daemon)
            test_register_window_answers_promptly(daemon)
            # Kills `daemon` and runs its own replacement, so nothing may use the
            # shared one after this.
            test_restart.run(daemon, tmp)
        finally:
            daemon.stop()
        test_unregistered.run(tmp)

    if harness.failures:
        print("\n%d check(s) failed" % len(harness.failures))
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
