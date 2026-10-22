#!/usr/bin/env bash
# Sourced inside tests/with-nested-hyprland.sh by the desktop-control tests: an accessibility
# bus on the test's private session bus and fixture windows in the nested Hyprland.
# Every function refuses to run against the real session: the runtime dir must be the one
# with-nested-hyprland.sh made (/tmp/nh.*), the session bus a private one under /tmp, and a
# nested instance must be named whose socket is in that runtime dir.

ai_desktop_guard() {
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || { echo "ai-desktop: no nested Hyprland named" >&2; return 1; }
    [[ ${XDG_RUNTIME_DIR:-} == /tmp/nh.* ]] \
        || { echo "ai-desktop: refusing a runtime dir that is not the nested session's: ${XDG_RUNTIME_DIR:-}" >&2; return 1; }
    [[ ${DBUS_SESSION_BUS_ADDRESS:-} == unix:path=/tmp/* || ${DBUS_SESSION_BUS_ADDRESS:-} == unix:abstract=/tmp/* ]] \
        || { echo "ai-desktop: refusing a session bus that is not a private one: ${DBUS_SESSION_BUS_ADDRESS:-}" >&2; return 1; }
    [[ -S $XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock ]] \
        || { echo "ai-desktop: the nested Hyprland's socket is not under $XDG_RUNTIME_DIR" >&2; return 1; }
}

# The private bus has no service directories, so nothing activates the registry: start both by hand.
ai_desktop_a11y_start() {
    ai_desktop_guard || return 1
    /usr/lib/at-spi-bus-launcher --launch-immediately > /dev/null 2>&1 &
    local _
    for _ in $(seq 1 50); do
        gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus \
            --method org.a11y.Bus.GetAddress > /dev/null 2>&1 && break
        sleep 0.1
    done
    /usr/lib/at-spi2-registryd > /dev/null 2>&1 &
    sleep 0.5
}

# ai_desktop_fixture CLASS TITLE LOG: a fixture window, waited for by its title
ai_desktop_fixture() {
    ai_desktop_guard || return 1
    local cls=$1 title=$2 log=$3 _
    GDK_BACKEND=wayland python3 -I "$(dirname -- "${BASH_SOURCE[0]}")/ai-desktop-fixture.py" \
        --app-id "$cls" --title "$title" --log "$log" > "$log.stderr" 2>&1 &
    for _ in $(seq 1 100); do
        hyprctl -j clients 2> /dev/null | jq -e --arg t "$title" 'any(.title == $t)' > /dev/null && return 0
        sleep 0.1
    done
    echo "ai-desktop: the fixture \"$title\" never mapped: $(tail -5 "$log.stderr" 2> /dev/null)" >&2
    return 1
}
