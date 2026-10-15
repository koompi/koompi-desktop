#!/usr/bin/env bash
# The global menu daemon (globalmenu/, Rust) against its conformance suite.
# globalmenu/tests/test_daemon.py is the contract the shell is written against:
# it drives the binary GLOBAL_MENU_DAEMON names against stand-in applications on
# a private session bus. The daemon is built here, always, so a stale target/
# binary cannot stand in for the source: the RegisterWindow timing fix
# (3fc78fc3) was lost from main for a day while this test skipped for want of
# a binary.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="$ROOT/globalmenu/tests/test_daemon.py"
BIN="$ROOT/globalmenu/target/release/global-menu-daemon"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'skip: %s\n' "$1"; }

[[ -f "$SUITE" ]] || fail "the conformance suite is missing"
[[ -e "$ROOT/dots/.config/quickshell/koompi/scripts/global-menu" ]] \
    && fail "the zig daemon is back in the shell tree; the Rust daemon is the only one"

command -v cargo > /dev/null || { skip "no cargo; the global menu daemon cannot be built"; exit 0; }
command -v python3 > /dev/null || { skip "no python3; cannot run the conformance suite"; exit 0; }
command -v dbus-run-session > /dev/null || { skip "no dbus-run-session; the suite needs a session bus"; exit 0; }
# The mock applications the suite drives speak D-Bus through Gio, so without
# python-gobject they die at import and the daemon is blamed for it.
python3 -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' 2> /dev/null \
    || fail "python-gobject is not installed; the conformance suite's mock apps need Gio"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf -- '--- cargo build\n'
( cd "$ROOT/globalmenu" && cargo build --release --quiet -p koompi-globalmenu-daemon ) \
    || fail "the daemon did not build"

printf -- '--- cargo test\n'
( cd "$ROOT/globalmenu" && cargo test --quiet ) || fail "globalmenu unit tests failed"

printf -- '--- conformance suite\n'
GLOBAL_MENU_DAEMON="$BIN" timeout 300 python3 "$SUITE" > "$tmp/suite.log" 2>&1
rc=$?
tail -3 "$tmp/suite.log"
[[ $rc -eq 0 ]] || { cat "$tmp/suite.log" >&2; fail "the daemon failed the conformance suite"; }

# The shell reads one payload before it sends anything, so a daemon that
# resolves nothing at startup still has to say so, or the bar sits on an empty
# menu with no retry scheduled until the user next changes focus. The
# conformance suite cannot see this: --test bypasses the focus guard that
# swallows the payload, so it only shows up against a live compositor.
printf -- '--- startup payload\n'
got=$("$ROOT/tests/with-nested-hyprland.sh" dbus-run-session --config-file="$ROOT/tests/private-bus.conf" -- sh -c "sleep 10 | timeout 10 '$BIN' 2> /dev/null | head -n 1")
status=$?
if [[ $status == 77 ]]; then
    skip "no Hyprland or kwin_wayland; cannot check the startup payload"
    exit 0
fi
[[ $got == '{"items":[],"gen":1}' ]] \
    || fail "the daemon opened with '$got', not the empty payload the shell waits for"

echo "ok"
