"""Qt menubars that were never registered.

Qt 6.10 and later call RegisterWindow only on X11. On Wayland a QMenuBar exports
itself at /MenuBar/<n> on the application's connection and hides the menubar in
its window, so the daemon has to find it there, by the focused window's process.
"""

import subprocess
import time

from harness import (
    ADOPTED, Daemon, check, click, fresh_log, gdbus, get_menus, labels,
    menu_windows, start_mock, stop_mock, wait_until,
)


def test_wayland_qt_menubar(log):
    print("a Qt application on Wayland, which never registers")
    daemon = Daemon()
    app = start_mock(
        "mock_dbusmenu_app.py", log, 0, "org.koompi.test.QtWayland",
        "--path", "/MenuBar/2", "--no-register",
        "--decoy", "/MenuBar/1=Older Window", "--decoy", "/MenuBar=Tray Menu",
    )
    try:
        check(menu_windows() == [], "nothing registered: %s" % get_menus())
        payload = daemon.focus(app.pid)
        check(
            labels(payload) == ["File", "Tools"],
            "the newest menubar is found, not the tray's or an older window's: %s" % labels(payload),
        )
        check(
            menu_windows() == [str(ADOPTED | app.pid)] and "'/MenuBar/2'" in get_menus(),
            "it is adopted as the process's registration: %s" % get_menus(),
        )
        check(click(daemon, payload, "New", log, "event 2 clicked"), "a click reaches the application")

        payload = daemon.focus(app.pid, "another-window-of-it")
        check(
            labels(payload) == ["File", "Tools"],
            "another window of the application shows the application's menu: %s" % labels(payload),
        )
    finally:
        stop_mock(app)
    check(
        wait_until(lambda: menu_windows() == []),
        "the adopted menu goes when the application does: %s" % get_menus(),
    )
    daemon.stop()


def test_no_menubar_no_menu(log):
    print("windows whose process exports no menubar")
    daemon = Daemon()
    other = start_mock(
        "mock_dbusmenu_app.py", log, 0, "org.koompi.test.QtElsewhere", "--path", "/MenuBar/1", "--no-register",
    )
    gtk = start_mock("mock_gtk_app.py", log)
    sleeper = subprocess.Popen(["sleep", "30"])
    try:
        check(
            daemon.focus(gtk.pid)["items"] == [],
            "a process with a bus connection but no menubar gets no menu, not another application's",
        )
        check(daemon.focus(sleeper.pid)["items"] == [], "a process with no bus connection gets no menu")
        check(menu_windows() == [], "nothing was adopted for either: %s" % get_menus())
    finally:
        sleeper.kill()
        sleeper.wait(timeout=5)
        stop_mock(gtk)
        stop_mock(other)
        daemon.stop()


def test_register_window_while_the_daemon_waits(log):
    """The probe and the menu fetch block the daemon's main thread on an
    application. RegisterWindow is answered elsewhere, and Qt's QMenuBar
    constructor waits for it, so it must not wait behind them."""
    print("RegisterWindow while the daemon waits on a slow application")
    daemon = Daemon()
    slow = start_mock(
        "mock_dbusmenu_app.py", log, 0, "org.koompi.test.QtSlow", 2.0, "--path", "/MenuBar/1", "--no-register",
    )
    try:
        daemon.send("focus %d" % slow.pid)
        time.sleep(0.5)  # inside the application's AboutToShow by now
        started = time.monotonic()
        gdbus("com.canonical.AppMenu.Registrar", "RegisterWindow", 4302, "/MenuBar/9")
        elapsed = time.monotonic() - started
        check(elapsed < 1.0, "RegisterWindow returned in %.3fs while the daemon was busy" % elapsed)
        check(labels(daemon.read()) == ["File", "Tools"], "and the slow application's menu still arrives")
    finally:
        stop_mock(slow)
        daemon.stop()


def run(tmp):
    test_wayland_qt_menubar(fresh_log(tmp, "wayland"))
    test_no_menubar_no_menu(fresh_log(tmp, "nomenu"))
    test_register_window_while_the_daemon_waits(fresh_log(tmp, "slow"))

