#!/usr/bin/env bash
# The bar's network glyph shows a joined network as joined. NetworkManager's internet
# check is a plain-HTTP fetch, so a network that blocks port 80 reports connectivity
# "limited" while HTTPS works; the glyph read that as not connected and drew a crossed
# wifi on a working link. This has come back more than once, so it is checked here
# against the real Network.qml and the real bar NetworkIndicator, fed by a stand-in
# koompi-shelld that speaks PROTOCOL.md. Each scenario is one whole `state`.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

for tool in kwin_wayland qs dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

WORK="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap '(( failed )) && echo "kept $WORK" >&2 || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/run" "$WORK/home" "$WORK/xdg/config/koompi" "$WORK/xdg/state/quickshell/user" "$WORK/xdg/cache" "$WORK/xdg/data"
chmod 700 "$WORK/run"
for entry in "$SHELL_ROOT"/*; do
    [[ "$(basename -- "$entry")" == shell.qml ]] || ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
echo greeted > "$WORK/xdg/state/quickshell/user/first_run.txt"
echo '{"windows": {"workspaceHelp": false}}' > "$WORK/xdg/config/koompi/config.json"

# name|connectivity|wifi enabled|wifi status|device state|ethernet|connected|strength
# unscanned: joined before the scan list arrived, so only network_strength says how well.
# `connected` is what the daemon derives (model.rs), which excludes limited on purpose;
# the glyph must not lean on it.
cat > "$WORK/scenarios" <<'EOF'
full|full|true|connected|activated|false|true|82
limited|limited|true|connected_limited|activated|false|false|82
portal|portal|true|connected_portal|activated|false|false|40
weak_limited|limited|true|connected_limited|activated|false|false|10
unscanned|limited|true|connected_limited|activated|false|false|82
connecting|none|true|connecting|config|false|false|0
disconnected|none|true|disconnected|disconnected|false|false|0
disabled|none|false|disabled|unavailable|false|false|0
cable_limited|limited|false|disabled|unavailable|true|true|0
EOF

cat > "$WORK/bin/koompi-shelld" <<SH
#!/usr/bin/env bash
echo '{"type":"hello","protocol":1}'
read -r _ # the subscribe; the shell asks for network once something reads it
while IFS='|' read -r name conn enabled status dstate eth connected strength; do
    case "\$status" in connected_*) status=limited ;; esac
    active=false; [[ \$strength -gt 0 ]] && active=true
    ap='{"path":"/ap/1","active":'\$active',"strength":'\$strength',"frequency":2437,"ssid":"Office","ssid_hex":"4f6666696365","hw_address":"00:11:22:33:44:55","security":{"label":"WPA2","wants_psk":true,"enterprise":false},"band_ghz":2}'
    rows="[\$ap]"; [[ \$status == disabled || \$name == unscanned ]] && rows='[]'
    name_field='"Office"'; [[ \$active == true ]] || name_field='""'
    [[ \$eth == true ]] && name_field='"Wired"'
    printf '{"type":"state","service":"network","state":{"scenario":"%s","available":true,"connectivity":"%s","ethernet":%s,"connected":%s,"network_name":%s,"network_strength":%s,"captive_portal":%s,"wifi":{"present":true,"enabled":%s,"status":"%s","device_state":"%s","scanning":false,"connecting":%s,"networks":%s,"networks_by_ssid":%s}}}\n' \
        "\$name" "\$conn" "\$eth" "\$connected" "\$name_field" "\$strength" "\$([[ \$conn == portal ]] && echo true || echo false)" \
        "\$enabled" "\$status" "\$dstate" "\$([[ \$status == connecting ]] && echo true || echo false)" "\$rows" "\$rows"
    sleep 0.7
done < "$WORK/scenarios"
sleep 30
SH
chmod +x "$WORK/bin/koompi-shelld"
# the real easyeffects aborts in a test session, and each abort toasts the live desktop
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/easyeffects"
chmod +x "$WORK/bin/easyeffects"

cat > "$WORK/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.services
import qs.modules.koompi.bar

ShellRoot {
    PanelWindow {
        implicitWidth: 40
        implicitHeight: 40
        NetworkIndicator {
            id: glyph
        }
    }
    // read once the glyph's fill animation has settled
    Timer {
        id: settle
        interval: 350
        onTriggered: {
            const s = ShellServices.network;
            if (s?.scenario)
                console.log("GLYPH " + s.scenario + " " + glyph.text + " fill=" + glyph.fill);
        }
    }
    Connections {
        target: ShellServices
        function onNetworkChanged() {
            settle.restart();
        }
    }
}
QML

cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
cd "$WORK/shell"
qs -p "$WORK/shell/shell.qml" > "$WORK/qs.log" 2>&1 &
for _ in \$(seq 1 120); do grep -q 'GLYPH cable_limited' "$WORK/qs.log" && break; sleep 0.25; done
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PATH="$WORK/bin:$PATH" HOME="$WORK/home" QT_NO_XDG_DESKTOP_PORTAL=1 KOOMPI_SHELLD="$WORK/bin/koompi-shelld" QT_QPA_PLATFORM=wayland \
    XDG_RUNTIME_DIR="$WORK/run" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$WORK/no-system-bus" XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" \
    XDG_CACHE_HOME="$WORK/xdg/cache" XDG_DATA_HOME="$WORK/xdg/data" \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual \
        --width 1280 --height 800 --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1

out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
# scenario|glyph|fill
while IFS='|' read -r name glyph fill; do
    line="$(grep -m1 "GLYPH $name " <<< "$out")"
    [[ -n "$line" ]] || { fail "$name: the shell never drew this state"; continue; }
    [[ "$line" == *" $glyph fill=$fill" ]] \
        || fail "$name: wanted $glyph fill=$fill, drew ${line#*GLYPH "$name" }"
done <<'EOF'
full|network_wifi|1
limited|network_wifi|1
portal|network_wifi_2_bar|1
weak_limited|signal_wifi_0_bar|1
unscanned|network_wifi|1
connecting|signal_wifi_statusbar_not_connected|0
disconnected|signal_wifi_off|0
disabled|wifi_off|0
cable_limited|lan|1
EOF
grep -q 'TypeError\|ReferenceError' <<< "$out" && fail "the probe logged: $(grep -m1 'TypeError\|ReferenceError' <<< "$out")"
(( failed )) && exit 1
echo "ok   network glyph: a joined network draws its bars whatever the internet check said; off, joining and cable draw their own"
