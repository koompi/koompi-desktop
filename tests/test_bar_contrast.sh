#!/usr/bin/env bash
# J22 (audit B3): every text and glyph colour the bar draws reaches 4.5:1 (WCAG AA)
# against the bar composited over the worst wallpaper pixel: white under the dark
# bar, black under the light one. The colours are read out of the bar's own QML
# (every colOn*, colSubtext and colBar* a `color:` line names, plus m3error), then
# the real Appearance singleton is loaded in dark and in light and each one is
# measured. The light palette is the Material baseline tones the matugen scheme
# produces: the bar's tokens must hold on it, not on one wallpaper's scheme.
# bar.showBackground false is the user's explicit choice and is exempt.
# Headless qs in a virtual KWin, on a private bus with its own HOME and runtime dir.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in qs kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

files=("$SHELL_ROOT"/modules/koompi/bar/{ActiveWindow,BarContent,BarPanelButton,BatteryIndicator,ClockWidget,HyprlandXkbIndicator,ModeIndicators,NotificationUnreadCount,UpdateBadge}.qml
       "$SHELL_ROOT"/modules/koompi/verticalBar/{VerticalBarContent,VerticalClockWidget,BatteryIndicator}.qml)
tokens="$(grep -hE '^[[:space:]]*(property color )?(icon)?[cC]olor:|^[[:space:]]*property color colText:' "${files[@]}" \
    | grep -oE 'Appearance\.colors\.(colOn[A-Za-z0-9]*|colSubtext|colBar(Subtext|TextInactive))' | sed 's/Appearance\.colors\.//' | sort -u | tr '\n' ' ')"
[[ -n "$tokens" ]] || { fail "found no bar text colours in the bar QML; the scan broke"; exit 1; }
echo "bar text colours: $tokens"

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/xdg/data" "$WORK/home" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$WORK/shell/contrast_probe.qml" <<'QML'
import Quickshell
import QtQuick
import qs
import qs.modules.common

ShellRoot {
    id: probe
    property var tokens: Quickshell.env("PROBE_TOKENS").trim().split(/\s+/)
    property int ticks: 0

    function lin(c) { return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
    function lum(c) { return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b); }
    function ratio(a, b) {
        const x = lum(a), y = lum(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }
    function over(bar, wall) {
        return Qt.rgba(bar.a * bar.r + (1 - bar.a) * wall, bar.a * bar.g + (1 - bar.a) * wall, bar.a * bar.b + (1 - bar.a) * wall, 1);
    }
    function report(mode, name, fg, bg) {
        const r = probe.ratio(fg, bg);
        console.log((r >= 4.5 ? "PASS " : "FAIL ") + mode + " " + name + " " + r.toFixed(2) + ":1 on " + bg.toString());
    }
    function measure(mode) {
        const c = Appearance.colors;
        const bg = probe.over(c.colBarBackground, Appearance.m3colors.darkmode ? 1 : 0);
        for (const name of probe.tokens) probe.report(mode, name, c[name], bg);
        probe.report(mode, "m3error", Appearance.m3colors.m3error, bg);
        probe.report(mode, "m3onSecondaryContainer on colSecondaryContainer", Appearance.m3colors.m3onSecondaryContainer, c.colSecondaryContainer);
    }
    function light() {
        const m = Appearance.m3colors;
        m.darkmode = false;
        m.m3background = "#fcf8f8"; m.m3onBackground = "#1c1b1c";
        m.m3surfaceContainerLow = "#f6f3f3"; m.m3onSurfaceVariant = "#4a454a";
        m.m3outline = "#7b757a"; m.m3outlineVariant = "#cbc5ca";
        m.m3secondaryContainer = "#e8dee8"; m.m3onSecondaryContainer = "#211a22";
        m.m3error = "#ba1a1a";
    }

    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            probe.ticks++;
            if (probe.ticks === 3) probe.measure("dark");
            if (probe.ticks === 4) probe.light();
            if (probe.ticks === 6) { probe.measure("light"); console.log("PROBE DONE"); Qt.quit(); }
        }
    }
}
QML

printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/koompi-shelld"
chmod +x "$WORK/koompi-shelld"
cat > "$WORK/inner.sh" <<SH
#!/usr/bin/env bash
cd "$WORK/shell"
unset HYPRLAND_INSTANCE_SIGNATURE
timeout 40 qs -p "$WORK/shell/contrast_probe.qml" > "$WORK/qs.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
    PROBE_TOKENS="$tokens" KOOMPI_SHELLD="$WORK/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" XDG_DATA_HOME="$WORK/xdg/data" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 90 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 800 --height 600 --no-lockscreen --no-global-shortcuts \
        --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log")"
grep -E '^ DEBUG qml: (PASS|FAIL|PROBE)' <<< "$out" | sed 's/^ DEBUG qml: //'
if ! grep -q "PROBE DONE" <<< "$out" || grep -q '^ DEBUG qml: FAIL' <<< "$out"; then
    grep -E "ERROR|TypeError|ReferenceError" <<< "$out" | head -30 >&2
    fail "a bar colour is under 4.5:1 on the worst wallpaper, or the probe did not finish"
fi
(( failed )) || echo "ok   contrast: every bar text colour reaches 4.5:1 in dark and light"
exit $failed
