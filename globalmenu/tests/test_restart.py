"""Registrations across a daemon restart.

An application registers once, when it first sees somebody own the registrar
name, and never again. The shell restarts its daemon on every update and reload,
so the table has to survive that: through the mirror the owner keeps in
$XDG_RUNTIME_DIR, and, for a Qt menubar, through finding it again without one.
"""

import os
import time

from harness import (
    Daemon, check, click, fresh_log, gdbus, get_menus, labels, menu_windows,
    mirror_path, mirror_windows, registrar_owner, start_mock, stop_mock,
    unique_name_of, wait_until,
)


def test_restart_recovery(daemon):
    """If a daemon restart lost the table, every menu would stay missing until the
    user restarted the application itself, which is not an acceptable ask."""
    print("recovering registrations across a daemon restart")
    app = start_mock("mock_dbusmenu_app.py", os.devnull, 4243)
    try:
        before = get_menus()
        check("4243" in before, "the application is registered before the restart: %s" % before)

        # Kill the daemon the way a crash or a shell reload would, and bring up
        # a replacement against the same bus. The application is never touched.
        daemon.proc.kill()
        daemon.proc.wait(timeout=5)
        replacement = Daemon()
        try:
            wait_until(lambda: "4243" in get_menus())
            after = get_menus()
            check(
                "4243" in after,
                "the registration is recovered without restarting the app: %s" % after,
            )
            check(
                app.poll() is None,
                "the application really was left running the whole time",
            )
        finally:
            replacement.stop()
    finally:
        stop_mock(app)


def test_restart_without_mirror(log):
    """The mirror can be missing: never written, removed, or written by a daemon
    that did not hold the name. A Qt menubar is still on the application's own
    connection, so the new daemon finds it by the focused window's process."""
    print("a restart with no mirror to recover from")
    first = Daemon()
    app = start_mock("mock_dbusmenu_app.py", log, 4249, "org.koompi.test.QtNoMirror", "--path", "/MenuBar/1")
    second = None
    try:
        check(menu_windows() == ["4249"], "registered with the first daemon: %s" % get_menus())
        first.proc.kill()
        first.proc.wait(timeout=5)
        check(os.path.exists(mirror_path()), "the first daemon had mirrored it")
        if os.path.exists(mirror_path()):
            os.remove(mirror_path())

        second = Daemon()
        check(menu_windows() == [], "the new daemon had nothing to recover: %s" % get_menus())
        payload = second.focus(app.pid)
        check(labels(payload) == ["File", "Tools"], "the window's menu is found anyway: %s" % labels(payload))
        check("'/MenuBar/1'" in get_menus(), "and adopted as a registration: %s" % get_menus())
        check(click(second, payload, "New", log, "event 2 clicked"), "a click on the found menu reaches the application")
    finally:
        if second is not None:
            second.stop()
        first.stop()
        stop_mock(app)


def test_restart_while_the_old_daemon_runs(log):
    """The new daemon can start before the old one has gone: a hot reload starts
    the new generation's daemon first, and the old shell can outlive the restart's
    wait. The new one takes the name and the table, keeps both when the old one
    exits, and new registrations reach it and its mirror."""
    print("a restart while the previous daemon is still running")
    old = Daemon()
    app = start_mock("mock_dbusmenu_app.py", log, 4250, "org.koompi.test.QtOverlap", "--path", "/MenuBar/3")
    new = None
    late = None
    try:
        held = registrar_owner()
        new = Daemon()
        check(
            wait_until(lambda: registrar_owner() not in ("", held)),
            "the new daemon takes the name while the old one runs",
        )
        check(wait_until(lambda: menu_windows() == ["4250"]), "and serves its registration: %s" % get_menus())

        old.stop()
        check(old.proc.returncode == 0, "the old daemon exits on its own once its shell's pipe closes")
        time.sleep(0.3)
        check(registrar_owner() not in ("", held), "the name stays with the new daemon")
        check(menu_windows() == ["4250"], "which still serves the registration: %s" % get_menus())
        check(mirror_windows() == ["4250"], "and the mirror still lists it: %s" % mirror_windows())
        check(labels(new.focus(app.pid)) == ["File", "Tools"], "the new daemon resolves the window's menu")

        late = start_mock("mock_dbusmenu_app.py", os.devnull, 4251, "org.koompi.test.QtLate")
        check(
            wait_until(lambda: sorted(mirror_windows()) == ["4250", "4251"]),
            "a registration after the old daemon left lands in the new one's mirror: %s" % mirror_windows(),
        )
    finally:
        for proc in (late, app):
            if proc is not None:
                stop_mock(proc)
        if new is not None:
            new.stop()
        old.stop()


def test_stale_registration_dropped():
    """The mirrored table must not resurrect an application that has exited."""
    print("registrations of applications that exited")
    # The daemon first: the application registers as soon as it starts, so with
    # nobody owning the registrar name there is nothing for it to register with.
    daemon = Daemon()
    app = start_mock("mock_dbusmenu_app.py", os.devnull, 4244)
    try:
        check("4244" in get_menus(), "registered while the app was alive")
    finally:
        # In this order: with the daemon still up it would see the application
        # go and clean the mirror itself, which is not what is under test here.
        daemon.stop()
    stop_mock(app)

    revived = Daemon()
    try:
        wait_until(lambda: "4244" not in get_menus(), timeout=3.0)
        check(
            "4244" not in get_menus(),
            "a dead application is dropped rather than restored: %s" % get_menus(),
        )
    finally:
        revived.stop()


def test_reacquired_name_does_not_duplicate():
    """The name is asked for with ALLOW_REPLACEMENT, so a second daemon can take
    it and the bus hands it back when that one exits. Every acquisition restores
    the mirror, so restoring twice must not leave two entries for one window: the
    bar would show that application's menu twice, and forWindow would answer from
    whichever copy happened to come first."""
    print("the registrar name being taken away and handed back")
    first = Daemon()
    app = None
    try:
        app = start_mock("mock_dbusmenu_app.py", os.devnull, 4245)
        held = registrar_owner()
        check(menu_windows() == ["4245"], "one entry to begin with: %s" % menu_windows())

        # A restarted daemon takes the name with REPLACE. The first one stays
        # queued behind it rather than giving up, which is what makes the
        # hand-back happen at all.
        replacement = Daemon()
        check(
            wait_until(lambda: registrar_owner() not in ("", held)),
            "the replacement takes the name from the first daemon",
        )
        replacement.stop()
        check(
            wait_until(lambda: registrar_owner() == held),
            "the name comes back to the first daemon when the replacement exits",
        )

        wait_until(lambda: menu_windows() == ["4245"])
        check(
            menu_windows() == ["4245"],
            "the recovered registration is not duplicated: %s" % menu_windows(),
        )
        check(mirror_windows() == ["4245"], "nor duplicated in the mirror: %s" % mirror_windows())
    finally:
        if app is not None:
            stop_mock(app)
        first.stop()


def test_displaced_daemon_does_not_write_the_mirror():
    """A daemon that lost the name still holds a table, and still sees the bus
    signals that change it. If it keeps mirroring that table it overwrites the
    real owner's, and the next restart recovers the wrong set of menus."""
    print("a daemon that has lost the name writing the mirror")
    displaced = Daemon()
    apps = []
    owner = None
    try:
        apps.append(start_mock("mock_dbusmenu_app.py", os.devnull, 4246))
        held = registrar_owner()
        check(mirror_windows() == ["4246"], "the first daemon mirrored its table")

        owner = Daemon()
        check(
            wait_until(lambda: registrar_owner() not in ("", held)),
            "the second daemon takes the name",
        )
        # Registered while the second daemon owns the name, so only it knows.
        apps.append(start_mock("mock_dbusmenu_app.py", os.devnull, 4247, "org.koompi.test.QtApp2"))
        check(
            wait_until(lambda: sorted(mirror_windows()) == ["4246", "4247"]),
            "the owner mirrors both registrations: %s" % mirror_windows(),
        )

        # Make the displaced daemon change its own table, addressing it by unique
        # name so the request cannot reach the owner instead.
        stale = unique_name_of(displaced.proc.pid)
        gdbus(stale, "UnregisterWindow", 4246)
        check(
            wait_until(lambda: menu_windows(stale) == []),
            "the displaced daemon did drop it from its own table: %s" % menu_windows(stale),
        )

        check(
            sorted(mirror_windows()) == ["4246", "4247"],
            "the mirror still describes the owner's table, not the displaced one: %s"
            % mirror_windows(),
        )
        check(
            sorted(menu_windows()) == ["4246", "4247"],
            "and the owner still serves both: %s" % menu_windows(),
        )
        check(
            not os.path.exists(mirror_path() + ".new"),
            "the mirror is written through a temporary that gets renamed, not left behind",
        )
    finally:
        if owner is not None:
            owner.stop()
        displaced.stop()
        for app in apps:
            stop_mock(app)


def run(daemon, tmp):
    """`daemon` is the suite's shared one, which test_restart_recovery kills."""
    test_restart_recovery(daemon)
    test_stale_registration_dropped()
    test_reacquired_name_does_not_duplicate()
    test_displaced_daemon_does_not_write_the_mirror()
    test_restart_without_mirror(fresh_log(tmp, "no-mirror"))
    test_restart_while_the_old_daemon_runs(fresh_log(tmp, "overlap"))
