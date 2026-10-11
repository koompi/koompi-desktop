#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

failures=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }
finish() {
    (( failures == 0 )) || exit 1
    exit 0
}

grep -q 'ConflictKiller.load()' "$SHELL_ROOT/shell.qml" || bad "shell.qml no longer starts ConflictKiller, so nothing below would run in the shell"
if grep -rq 'autoKillTrays' "$SHELL_ROOT"; then
    bad "autoKillTrays is still in the shell: kded6 is no longer killed, so nothing may read or declare it"
else
    ok "static: no autoKillTrays key"
fi

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    finish
fi
for tool in kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; finish; }
done

WORK="$(mktemp -d)" || { echo "FAIL: no temporary directory" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/out" "$WORK/config/koompi" "$WORK/state" "$WORK/cache" "$WORK/data" "$WORK/rt" "$WORK/home"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$WORK/bin/pidof" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CASE_DIR/pidof.log"
for name in "$@"; do
    case " $FAKE_RUNNING " in *" $name "*) echo 4242; exit 0 ;; esac
done
exit 1
SH
for name in killall qs; do
    cat > "$WORK/bin/$name" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CASE_DIR/$(basename -- "$0").log"
SH
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/koompi-shelld"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/conflict_probe.qml" <<'QML'
import qs.services
import Quickshell
import QtQuick

ShellRoot {
    Component.onCompleted: ConflictKiller.load()
    Timer {
        interval: 60000
        running: true
        onTriggered: Qt.quit()
    }
}
QML

cat > "$WORK/cases.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
cd "$WORK/shell" || exit 1
export PATH="$WORK/bin:$PATH"

wait_for() {
    local file=$1 tries=$2 n
    for ((n = 0; n < tries; n++)); do [[ -s "$file" ]] && return 0; sleep 0.1; done
    return 1
}

dialog() {
    local name=$1 quits_alone=$3 n
    export CASE_DIR="$WORK/out/$name" FAKE_RUNNING="$2"
    mkdir -p "$CASE_DIR"
    WAYLAND_DEBUG=client "$REAL_QS" -p "$WORK/shell/killDialog.qml" > "$CASE_DIR/out.log" 2>&1 &
    local pid=$!
    if (( quits_alone )); then
        for ((n = 0; n < 200; n++)); do kill -0 "$pid" 2> /dev/null || break; sleep 0.1; done
    else
        for ((n = 0; n < 150; n++)); do
            grep -q 'get_toplevel' "$CASE_DIR/out.log" && break
            kill -0 "$pid" 2> /dev/null || break
            sleep 0.1
        done
        sleep 1
    fi
    if kill -0 "$pid" 2> /dev/null; then echo running > "$CASE_DIR/state"; else echo quit > "$CASE_DIR/state"; fi
    kill "$pid" 2> /dev/null
    wait "$pid" 2> /dev/null
    return 0
}

probe() {
    export CASE_DIR="$WORK/out/$1" FAKE_RUNNING="$2"
    mkdir -p "$CASE_DIR"
    printf '%s\n' "$3" > "$WORK/config/koompi/config.json"
    "$REAL_QS" -p "$WORK/shell/conflict_probe.qml" > "$CASE_DIR/out.log" 2>&1 &
    local pid=$!
    # the pidof check runs once Config is ready; settle 2 s after it
    wait_for "$CASE_DIR/pidof.log" 200
    sleep 2
    kill "$pid" 2> /dev/null
    wait "$pid" 2> /dev/null
    return 0
}

echo '{}' > "$WORK/config/koompi/config.json"
dialog dialog-idle "" 1
dialog dialog-open "mako" 0
probe no-kded6 "kded6" '{"conflictKiller": {"autoKillTrays": true}}'
probe mako-asks "mako" '{}'
probe mako-auto "dunst" '{"conflictKiller": {"autoKillNotificationDaemons": true}}'
SH
chmod +x "$WORK/cases.sh"

run_kwin() {
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY HOME="$WORK/home" WORK="$WORK" REAL_QS="$(command -v qs)" \
        QT_QPA_PLATFORM=wayland KOOMPI_SHELLD="$WORK/bin/koompi-shelld" KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
        XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
        XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$WORK/rt" \
        timeout 240 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/cases.sh" > "$WORK/kwin.log" 2>&1
}
run_kwin
[[ -s "$WORK/out/dialog-idle/state" ]] || { cat -- "$WORK/kwin.log" >&2; bad "the headless KWin session ran none of the cases"; finish; }

plain() { sed 's/\x1b\[[0-9;]*m//g' "$WORK/out/$1/out.log" 2> /dev/null; }
toplevels() { plain "$1" | grep -c 'get_toplevel'; }
logged() { cat -- "$WORK/out/$1/$2.log" 2> /dev/null; }
state() { cat -- "$WORK/out/$1/state"; }
evidence() {
    printf -- '--- %s: what the process printed ---\n' "$1" >&2
    plain "$1" | grep -vE '^\[[0-9:. ]+\]' | tail -n 20 >&2
}

if [[ "$(state dialog-idle)" == quit && "$(toplevels dialog-idle)" == 0 ]]; then
    ok "dialog: with nothing running it quits by itself and never opens a window"
else
    evidence dialog-idle
    bad "dialog: with nothing running it was $(state dialog-idle) with $(toplevels dialog-idle) window(s); it must quit by itself with none"
fi
if [[ "$(state dialog-open)" == running && "$(toplevels dialog-open)" -ge 1 ]]; then
    ok "dialog: with mako running it opens a window and waits for an answer"
else
    evidence dialog-open
    bad "dialog: with mako running it was $(state dialog-open) with $(toplevels dialog-open) window(s); it must wait with one"
fi
logged dialog-idle pidof | grep -qxF 'mako dunst' || bad "dialog: it did not ask pidof about mako and dunst, so no row was checked"

if [[ -z "$(logged no-kded6 killall)" && -z "$(logged no-kded6 qs)" ]]; then
    ok "start: a running kded6, even with the old autoKillTrays set: nothing killed, no dialog"
else
    evidence no-kded6
    bad "start: with kded6 running the shell killed or opened something: killall '$(logged no-kded6 killall)', qs '$(logged no-kded6 qs)'"
fi
if grep -qxF 'mako dunst' "$WORK/out/no-kded6/pidof.log" && ! grep -qw kded6 "$WORK/out/no-kded6/pidof.log"; then
    ok "start: the shell checks mako and dunst and no longer asks pidof about kded6"
else
    bad "start: the shell's pidof checks were: $(logged no-kded6 pidof | paste -sd';')"
fi
if [[ "$(logged mako-asks qs)" == "-p $WORK/shell/killDialog.qml" && -z "$(logged mako-asks killall)" ]]; then
    ok "start: a running mako opens the dialog once"
else
    evidence mako-asks
    bad "start: mako running did not open the dialog exactly once: qs '$(logged mako-asks qs)', killall '$(logged mako-asks killall)'"
fi
if [[ "$(logged mako-auto killall)" == "mako dunst" && -z "$(logged mako-auto qs)" ]]; then
    ok "start: a running dunst with autoKillNotificationDaemons set is killed without a dialog"
else
    evidence mako-auto
    bad "start: dunst with autoKillNotificationDaemons did not kill mako and dunst without the dialog: qs '$(logged mako-auto qs)', killall '$(logged mako-auto killall)'"
fi

finish
