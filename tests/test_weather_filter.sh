#!/usr/bin/env bash
# J21: the weather card shows today's high and low and the condition in words. wttr's j1 JSON, from a shimmed
# curl (no network), goes through the real Weather service's jq filter; the fields are read back over IPC.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'maxtempC' "$SHELL_ROOT/services/Weather.qml" || fail "Weather.qml does not keep today's maxtempC"
echo "ok   source: the filter keeps today's high and low"

for tool in kwin_wayland qs dbus-run-session jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.local/state/quickshell/user" "$WORK/home/.config/koompi" "$WORK/bin" "$WORK/rt" "$WORK/shell"
chmod 700 "$WORK/rt"
echo greeted > "$WORK/home/.local/state/quickshell/user/first_run.txt"
printf '{"windows": {"workspaceHelp": false}}\n' > "$WORK/home/.config/koompi/config.json"
for entry in "$SHELL_ROOT"/*; do ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"; done

cat > "$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
{"current_condition":[{"temp_C":"28","temp_F":"82","FeelsLikeC":"31","FeelsLikeF":"88","humidity":"70","weatherCode":"116","weatherDesc":[{"value":"Partly cloudy"}],"winddir16Point":"N","windspeedKmph":"9","windspeedMiles":"5","precipMM":"0","precipInches":"0","visibility":"10","visibilityMiles":"6","pressure":"1010","pressureInches":"30","uvIndex":"5"}],
"nearest_area":[{"areaName":[{"value":"Phnom Penh"}]}],
"weather":[{"maxtempC":"34","mintempC":"25","maxtempF":"93","mintempF":"77","astronomy":[{"sunrise":"06:00 AM","sunset":"06:00 PM"}]}]}
JSON
SH
chmod +x "$WORK/bin/curl"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin/koompi-shelld"

cat > "$WORK/shell/wx_probe.qml" <<'QML'
import qs.services
import Quickshell
import Quickshell.Io

ShellRoot {
    Component.onCompleted: Weather.getData()
    IpcHandler {
        target: "probe"
        function weather(): string {
            return `${Weather.data.city}|${Weather.data.condition}|${Weather.data.high}|${Weather.data.low}`;
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
qs -p wx_probe.qml > "$WORK/qs.log" 2>&1 &
pid=\$!
for _ in \$(seq 1 80); do qs -p wx_probe.qml ipc show > /dev/null 2>&1 && break; sleep 0.5; done
for _ in \$(seq 1 20); do
    r=\$(qs -p wx_probe.qml ipc call probe weather 2> /dev/null)
    [[ \$r == Phnom* ]] && break
    sleep 0.5
done
echo "\$r" > "$WORK/reading"
kill \$pid
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" \
    XDG_CONFIG_HOME="$WORK/home/.config" XDG_STATE_HOME="$WORK/home/.local/state" XDG_CACHE_HOME="$WORK/home/.cache" XDG_DATA_HOME="$WORK/home/.local/share" \
    KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

got="$(cat "$WORK/reading" 2> /dev/null)"
[[ "$got" == "Phnom Penh|Partly cloudy|34°C|25°C" ]] || { tail -15 "$WORK/qs.log" >&2; fail "weather fields: got '$got'"; }
echo "ok   probe: place, condition in words, today's high and low from the fixture"
