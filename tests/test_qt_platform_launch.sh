#!/usr/bin/env bash
# Qt exports a menubar to the bar only on X11, so the session starts Qt apps on
# Wayland with an xcb fallback and koompi-launch pins the apps whose menus must
# reach the bar to xcb. Asserts env.lua's value, that koompi-launch gives exactly
# those apps QT_QPA_PLATFORM=xcb (by desktop-entry id, by --id, by binary name) and
# leaves every other launch with the platform it inherited, on the systemd-run path
# and on the no-user-manager path, and that koompi doctor calls the session's value
# healthy. systemd-run, logger and busctl are shadowed: nothing here reaches the
# running session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_LUA="$REPO_ROOT/dots/.config/hypr/hyprland/env.lua"
LAUNCH="$REPO_ROOT/dots/.local/bin/koompi-launch"
HEALTH="$REPO_ROOT/dots/.local/bin/koompi-health"

failed=0
fail() {
    failed=$((failed + 1))
    (( failed > 6 )) || printf 'FAIL: %s\n' "$1" >&2
}
passed_since() { # FAILED_BEFORE MESSAGE
    (( failed == $1 )) && echo "ok   $2"
}

[[ -x "$LAUNCH" ]] || { echo "FAIL: $LAUNCH is not executable" >&2; exit 1; }

# 1. the session default
before=$failed
[[ "$(grep -c '^hl\.env("QT_QPA_PLATFORM"' "$ENV_LUA")" == 1 ]] || fail "env.lua does not set QT_QPA_PLATFORM exactly once"
session="$(sed -n 's/^hl\.env("QT_QPA_PLATFORM", "\(.*\)")$/\1/p' "$ENV_LUA")"
[[ "$session" == 'wayland;xcb' ]] || fail "env.lua sets QT_QPA_PLATFORM to '$session', not 'wayland;xcb'"
passed_since "$before" "env.lua: QT_QPA_PLATFORM=$session"

command -v python3 > /dev/null 2>&1 || { echo "skipping koompi-launch checks: python3 not installed (the user-manager socket is made with it)"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/share/applications" "$tmp/rt-manager/systemd" "$tmp/rt-none" "$tmp/home"
chmod 700 "$tmp/rt-manager" "$tmp/rt-none"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$tmp/rt-manager/systemd/private" \
    || { echo "FAIL: could not make a unix socket to stand in for the user manager" >&2; exit 1; }

cat > "$tmp/bin/systemd-run" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSD_LOG"
while [[ $1 != -- ]]; do shift; done
shift
exec "$@"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/logger"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/bin/busctl"
cat > "$tmp/bin/platform_probe" <<'SH'
#!/usr/bin/env bash
printf '%s' "${QT_QPA_PLATFORM-<unset>}" > "$OUT"
SH
chmod +x "$tmp/bin/systemd-run" "$tmp/bin/logger" "$tmp/bin/busctl" "$tmp/bin/platform_probe"
for name in okular dolphin konsole ark kdeconnect-app; do
    ln -s platform_probe "$tmp/bin/$name"
done
for id in org.kde.dolphin org.kde.okular org.kde.konsole org.kde.ark org.kde.kdeconnect.app; do
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s/bin/platform_probe %%U\n' "$id" "$tmp" > "$tmp/share/applications/$id.desktop"
done

# launched_platform RUNTIME_DIR PLATFORM|- ARG... : what the launched command saw
launched_platform() {
    local rt=$1 value=$2
    shift 2
    local -a qpa=(-u QT_QPA_PLATFORM)
    [[ $value == - ]] || qpa=("QT_QPA_PLATFORM=$value")
    rm -f "$tmp/out"
    echo launch >> "$tmp/launches"
    env "${qpa[@]}" OUT="$tmp/out" SYSD_LOG="$tmp/sysd.log" HOME="$tmp/home" XDG_RUNTIME_DIR="$rt" \
        XDG_DATA_HOME="$tmp/share" XDG_DATA_DIRS="$tmp/none" PATH="$tmp/bin:$PATH" \
        "$LAUNCH" "$@" 2> "$tmp/err" || { printf 'launch-failed: %s' "$(cat "$tmp/err")"; return; }
    cat "$tmp/out" 2> /dev/null || printf 'no-output'
}

inherited='wayland;xcb'

expect() { # LABEL WANT GOT
    [[ "$3" == "$2" ]] || fail "$1: the launched app saw QT_QPA_PLATFORM '$3', want '$2'"
}

check_launches() { # RUNTIME_DIR LABEL
    local rt=$1 label=$2 app
    for app in dolphin okular konsole ark; do
        expect "$label: bare command $app" xcb "$(launched_platform "$rt" "$inherited" "$app")"
        expect "$label: desktop entry org.kde.$app" xcb "$(launched_platform "$rt" "$inherited" "org.kde.$app.desktop")"
        expect "$label: --id org.kde.$app" xcb "$(launched_platform "$rt" "$inherited" --id "org.kde.$app" -- "$tmp/bin/platform_probe")"
        expect "$label: --id other, binary $app" xcb "$(launched_platform "$rt" "$inherited" --id some-launcher -- "$app")"
        expect "$label: $app with no platform in the session" xcb "$(launched_platform "$rt" - "$app")"
    done
    expect "$label: kdeconnect-app" "$inherited" "$(launched_platform "$rt" "$inherited" kdeconnect-app)"
    expect "$label: desktop entry org.kde.kdeconnect.app" "$inherited" "$(launched_platform "$rt" "$inherited" org.kde.kdeconnect.app.desktop)"
    expect "$label: --id org.kde.kdeconnect.app" "$inherited" "$(launched_platform "$rt" "$inherited" --id org.kde.kdeconnect.app -- "$tmp/bin/platform_probe")"
    expect "$label: --id okular-nightly is not okular" "$inherited" "$(launched_platform "$rt" "$inherited" --id okular-nightly -- "$tmp/bin/platform_probe")"
    expect "$label: kdeconnect-app with no platform in the session" '<unset>' "$(launched_platform "$rt" - kdeconnect-app)"
    expect "$label: the shell's own wayland pin is left alone" wayland "$(launched_platform "$rt" wayland kdeconnect-app)"
}

# 2. through the user manager: every launch has to have gone through the shim
before=$failed
: > "$tmp/sysd.log"
: > "$tmp/launches"
check_launches "$tmp/rt-manager" "systemd-run path"
[[ "$(grep -c -- '--scope .*--slice=app.slice' "$tmp/sysd.log")" == "$(wc -l < "$tmp/launches")" ]] \
    || fail "the systemd-run path was not taken for every launch: $(wc -l < "$tmp/sysd.log") of $(wc -l < "$tmp/launches")"
passed_since "$before" "koompi-launch via systemd-run: xcb for dolphin okular konsole ark, nothing else"

# 3. without one: the command runs directly, with the same environment
before=$failed
: > "$tmp/sysd.log"
check_launches "$tmp/rt-none" "no-manager path"
[[ ! -s "$tmp/sysd.log" ]] || fail "the no-manager path called systemd-run"
passed_since "$before" "koompi-launch without a user manager: the same"

# 4. koompi doctor takes the session's value as healthy, and a session still on xcb as a warning
health_line() {
    env -u HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORM="$1" HOME="$tmp/home" KOOMPI_LOG_DIR="$tmp/logs" PATH="$tmp/bin:$PATH" \
        "$HEALTH" 2>&1 < /dev/null | grep 'QT_QPA_PLATFORM'
}
before=$failed
line="$(health_line "$session")"
[[ "$line" == *'✓'* ]] || fail "koompi doctor does not call env.lua's QT_QPA_PLATFORM=$session healthy: '$line'"
line="$(health_line xcb)"
[[ "$line" == *'!'* ]] || fail "koompi doctor does not warn about a session still on xcb: '$line'"
passed_since "$before" "koompi doctor: the session's value healthy, xcb a warning"

(( failed <= 6 )) || echo "... and $((failed - 6)) more" >&2
(( failed == 0 )) || exit 1
echo "Qt platform: env.lua, koompi-launch and koompi doctor agree"
