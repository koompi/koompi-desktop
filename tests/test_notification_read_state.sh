#!/usr/bin/env bash
# J02: opening the right panel times the toasts out at once, but a notification
# only counts as read once the panel has stayed open for a second, so an
# accidental open and close leaves the unread badge alone. Static: the header
# shows the date and no longer carries the reload button. Live: the whole shell
# runs in a headless KWin on a private bus, a real notification arrives through
# notify-send, and the count is read back over the notifications IPC target.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
CONTENT="$SHELL_ROOT/modules/koompi/sidebarRight/SidebarRightContent.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'DateTime.fullDate' "$CONTENT" || fail "the panel header does not show DateTime.fullDate"
grep -qE 'DateTime\.uptime|"restart_alt"|hyprctl' "$CONTENT" \
    && fail "the panel header still shows uptime or carries a reload button"
echo "ok   source: header shows the date, no uptime, no reload button"

for tool in kwin_wayland qs dbus-run-session notify-send; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/bin"
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
set -uo pipefail
unset HYPRLAND_INSTANCE_SIGNATURE
qs -p "$SHELL_ROOT" > "$WORK/qs.log" 2>&1 &
qs_pid=\$!
trap 'kill "\$qs_pid"; wait "\$qs_pid"' EXIT
for _ in \$(seq 1 80); do qs -p "$SHELL_ROOT" ipc show > /dev/null 2>&1 && break; sleep 0.5; done
sleep 4
unread() { qs -p "$SHELL_ROOT" ipc call notifications unreadCount 2> /dev/null; }
call() { qs -p "$SHELL_ROOT" ipc call "\$@" > /dev/null 2>&1; }
note() { printf '%s %s\n' "\$1" "\$(unread)" >> "$WORK/readings"; }

notify-send -a probe "unread one" "arrived with the panel closed"
for _ in \$(seq 1 50); do [[ \$(unread) == 1 ]] && break; sleep 0.2; done
note arrived

call sidebarRight open; call sidebarRight close
sleep 1.5
note quick_open_close

call sidebarRight open
sleep 1.5
note open_for_1500ms
call sidebarRight close
sleep 0.3
note after_close
SH
chmod +x "$WORK/inner.sh"

PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    XDG_DATA_HOME="$WORK/xdg/data" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 150 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

expect() {
    local got
    got="$(awk -v k="$1" '$1 == k { print $2 }' "$WORK/readings" 2> /dev/null)"
    [[ "$got" == "$2" ]] || {
        cat "$WORK/readings" >&2
        fail "$3: unread is '${got:-missing}', wanted $2"
    }
}
expect arrived 1 "a notification sent with the panel closed was not counted unread"
expect quick_open_close 1 "an open and close inside 300 ms cleared the unread count"
expect open_for_1500ms 0 "a panel held open for 1.5 s did not mark the notification read"
expect after_close 0 "closing the panel brought the unread count back"
echo "ok   probe: quick open and close keeps the unread count, 1.5 s open zeroes it"
