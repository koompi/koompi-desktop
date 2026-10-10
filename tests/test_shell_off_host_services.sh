#!/usr/bin/env bash
# A shell a test starts must not reach the host's system bus (PolkitService's PolkitAgent registers there, and a
# test shell that took the live shell's place would hold the founder's authentication prompts) and must not start
# the real easyeffects (it aborts in a test session and every abort toasts the live desktop). Proven by running
# test_keep_awake_own_inhibitor.sh, a full shell nested in headless KWin, outside run.sh: its DBUS_SYSTEM_BUS_ADDRESS
# is a stand-in bus that logs every client, and a recording easyeffects heads its PATH. Neither may be touched.
# The static half keeps every test and tool that starts the whole shell on the same two guards.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

guards() { # guards <file>: prints a line when the file starts the whole shell and misses a guard
    local file=$1 joined kwin
    joined="$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' -- "$file")"
    grep -qE '(qs|QS_BIN"?) -p "\$(SHELL_ROOT|WORK/shell/shell\.qml|root)"|qs -p %q|qs -c koompi' <<< "$joined" || return 0
    kwin="$(grep -E '(^|[^-[:alnum:]_/])kwin_wayland[[:space:]]+--' <<< "$joined")" || return 0
    grep -q 'DBUS_SYSTEM_BUS_ADDRESS=' <<< "$kwin" \
        || printf '%s: the nested session inherits the host system bus\n' "$(basename -- "$file")"
    grep -q '/easyeffects"' <<< "$joined" \
        || printf '%s: no stand-in easyeffects heads the PATH of the session\n' "$(basename -- "$file")"
}
files=("$ROOT"/tests/test_*.sh)
for tool in shellshot hyprshot measure_surfaces; do
    [[ -f "$ROOT/.work/tools/$tool.sh" ]] && files+=("$ROOT/.work/tools/$tool.sh")
done
offenders=""
for file in "${files[@]}"; do
    [[ "${file##*/}" == "${BASH_SOURCE[0]##*/}" ]] && continue
    offenders+="$(guards "$file")"$'\n'
done
offenders="$(grep -v '^$' <<< "$offenders" || true)"
[[ -z "$offenders" ]] || fail "a shell-starting test or tool lacks a guard:
$offenders"
echo "ok   static: every test and tool that starts the whole shell has its own system bus address and a stand-in easyeffects"

for tool in dbus-daemon dbus-monitor dbus-run-session kwin_wayland qs; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, the shell is not started"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'kill "${bus_pid:-0}" "${mon_pid:-0}" 2> /dev/null; rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/rec" "$WORK/home" "$WORK/rt"
chmod 700 "$WORK/rt"
cat > "$WORK/rec/easyeffects" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WORK/easyeffects.calls"
exit 0
SH
chmod +x "$WORK/rec/easyeffects"

exec 3< <(dbus-daemon --config-file="$ROOT/tests/private-bus.conf" --print-address=1 --nofork 2> /dev/null)
read -r addr <&3
[[ -n $addr ]] || fail "the stand-in system bus did not start"
bus_pid="$(pgrep -nf -- "dbus-daemon --config-file=$ROOT/tests/private-bus.conf --print-address=1" || true)"
dbus-monitor --address "$addr" > "$WORK/monitor.log" 2>&1 &
mon_pid=$!
sleep 1

out="$(env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORM=offscreen \
    HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" DBUS_SYSTEM_BUS_ADDRESS="$addr" PATH="$WORK/rec:$PATH" \
    bash "$ROOT/tests/test_keep_awake_own_inhibitor.sh" 2>&1 < /dev/null)"
rc=$?
(( rc == 0 )) || fail "test_keep_awake_own_inhibitor.sh exited $rc outside run.sh: $out"
grep -qE 'skipping|^[[:space:]]*skip:' <<< "$out" && { echo "skip: the shell test skipped itself, nothing was started"; exit 0; }
sleep 1

[[ ! -s "$WORK/easyeffects.calls" ]] || fail "a test shell ran the real easyeffects: $(cat "$WORK/easyeffects.calls")"
echo "ok   easyeffects: the shell's login never ran the binary on PATH"

clients="$(grep -oE '(sender|destination)=:[0-9]+\.[0-9]+' "$WORK/monitor.log" | sed -E 's/^[a-z]+=//' | sort -u | wc -l)"
(( clients <= 1 )) || fail "a test shell connected to the host system bus ($clients clients, the monitor is one):
$(grep -E 'sender=|NameAcquired' "$WORK/monitor.log" | head -n 12)"
echo "ok   bus: a nested test shell made no connection to the system bus it inherited"
