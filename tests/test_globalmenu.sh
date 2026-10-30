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

# A real Qt app on Wayland, following the nested Hyprland's focus. Qt 6.10 and later
# never register there, so this is the case only the daemon's own lookup serves; the
# mock apps above cannot say whether Qt still exports /MenuBar/<n> the way it did.
qt_app=""
for candidate in designer6 designer okular; do
    command -v "$candidate" > /dev/null && { qt_app=$candidate; break; }
done
if [[ -z $qt_app ]]; then
    skip "no Qt app with a menubar (designer6, okular) to show the Wayland lookup on"
    exit 0
fi
printf -- '--- a Qt app on Wayland (%s)\n' "$qt_app"
cat > "$tmp/qt-app.sh" <<'SH'
#!/usr/bin/env bash
# in the nested session: the daemon on its bus, the app started by Hyprland, the bar's payload read
set -uo pipefail
bin=$1 app=$2 out=$3
# the daemon's stdin stays open on fd 3, as the shell's pipe does, until the end
mkfifo "$out.in"
"$bin" < "$out.in" > "$out" 2> /dev/null &
daemon=$!
exec 3> "$out.in"
for _ in $(seq 1 20); do [[ -s $out ]] && break; sleep 0.1; done
hyprctl dispatch "hl.dsp.exec_cmd(\"env QT_QPA_PLATFORM=wayland $app\")" > /dev/null
pid=""
for _ in $(seq 1 120); do
    pid=$(hyprctl clients -j | jq -r '.[0].pid // empty')
    grep -q '"label":"File"' "$out" && break
    sleep 0.25
done
# close what was started before the session ends: an app outliving its compositor can crash
[[ -n $pid ]] && kill "$pid" 2> /dev/null
exec 3>&-
for _ in $(seq 1 20); do [[ -n $pid ]] && kill -0 "$pid" 2> /dev/null || break; sleep 0.25; done
[[ -n $pid ]] && kill -9 "$pid" 2> /dev/null
wait "$daemon"
grep '"items":\[{' "$out" | tail -n 1 | jq -c '[.items[].label]'
SH
got=$("$ROOT/tests/with-nested-hyprland.sh" bash "$tmp/qt-app.sh" "$BIN" "$qt_app" "$tmp/qt-app.out")
[[ $got == '["File",'* ]] \
    || fail "$qt_app on Wayland never reached the bar: the daemon published '$got'"
printf '%s menu: %s\n' "$qt_app" "$got"

echo "ok"
