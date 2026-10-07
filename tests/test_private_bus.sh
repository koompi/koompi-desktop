#!/usr/bin/env bash
# A test's private bus must not auto-start the host's services. With the stock
# session config it activates xdg-desktop-portal: the Hyprland backend segfaults
# off-session, so the live crash watcher toasts every run, and the document
# portal remounts $XDG_RUNTIME_DIR/doc out from under the live one.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/tests/private-bus.conf"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$CONF" ]] || fail "missing $CONF"

offenders="$(grep -nE --exclude="$(basename -- "${BASH_SOURCE[0]}")" '(^|[^-[:alnum:]])dbus-run-session[[:space:]]' "$ROOT"/tests/*.sh \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#|command -v|for tool in' \
    | grep -v -- '--config-file="$ROOT/tests/private-bus.conf"\|--config-file="$REPO_ROOT/tests/private-bus.conf"' || true)"
[[ -z "$offenders" ]] || fail "a private bus without tests/private-bus.conf:
$offenders"
echo "ok   static: every dbus-run-session in tests/ uses tests/private-bus.conf"

for tool in dbus-run-session dbus-send; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, activation not checked"; exit 0; }
done

# listing activatable names starts nothing, so this is safe on any machine
names="$(timeout 20 dbus-run-session --config-file="$CONF" -- \
    dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.ListActivatableNames 2>&1)" || fail "the private bus did not answer: $names"
activatable="$(grep -oE 'string "[^"]+"' <<< "$names" | grep -v '"org.freedesktop.DBus"' || true)"
[[ -z "$activatable" ]] || fail "the private bus can auto-start host services:
$activatable"
echo "ok   bus: tests/private-bus.conf activates nothing but the bus itself"
