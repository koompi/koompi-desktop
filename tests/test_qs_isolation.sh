#!/usr/bin/env bash
# no test starts qs, quickshell, qml or Hyprland on the founder's session: a start is nested in a headless KWin, or runs offscreen with a HOME and XDG_RUNTIME_DIR of its own and no WAYLAND_DISPLAY or DISPLAY
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
self="$(basename -- "${BASH_SOURCE[0]}")"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

START='(^|[^[:alnum:]_./-])((qs|quickshell)[[:space:]]+(-p|-c|--path|--config)[[:space:]]|qml6?[[:space:]]+[^ ]*\.qml|Hyprland[[:space:]]+-c[[:space:]])'
NESTED='dbus-run-session.*kwin_wayland[[:space:]]+--virtual'
TALK='^[0-9]+:[[:space:]]*(grep|echo|printf|sed|cat|\[\[)[[:space:]]'

own() { # $1: HOME or XDG_RUNTIME_DIR, $2: a line; the line sets it to something other than the caller's
    grep -qE "(^|[[:space:]])$1=\"?[^[:space:]\"]" <<< "$2" \
        && ! grep -qE "(^|[[:space:]])$1=\"?(\\$\{?$1([^[:alnum:]_]|$)|~|/run/user|/home/)" <<< "$2"
}

# a file whose kwin_wayland line holds the whole start is nested; any other start must be offscreen on its own line
scan() {
    local file joined line
    for file in "$@"; do
        joined="$(sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ta' -e '}' -- "$file" | grep -nvE '^[[:space:]]*#')" || continue
        line="$(grep -E "$NESTED" <<< "$joined")" && own HOME "$line" && own XDG_RUNTIME_DIR "$line" \
            && grep -q -- '-u WAYLAND_DISPLAY' <<< "$line" && continue
        while IFS= read -r line; do
            grep -qE '[[:space:]]ipc[[:space:]]' <<< "$line" && continue
            grep -q 'QT_QPA_PLATFORM=offscreen' <<< "$line" && grep -q -- '-u WAYLAND_DISPLAY' <<< "$line" \
                && own HOME "$line" && own XDG_RUNTIME_DIR "$line" && continue
            printf '%s:%s\n' "$(basename -- "$file")" "${line%%:*}"
        done < <(grep -E "$START" <<< "$joined" | grep -vE "$TALK")
    done
}

tmp="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "${tmp:?}"' EXIT

printf 'out="$(timeout 60 qs -p probe.qml 2>&1)"\n' > "$tmp/test_bad.sh"
printf 'out="$(env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen HOME="$WORK/home" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" qs -p probe.qml)"\n' > "$tmp/test_bad_rt.sh"
printf 'out="$(env -u DISPLAY QT_QPA_PLATFORM=offscreen HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" qs -p probe.qml)"\n' > "$tmp/test_bad_wayland.sh"
printf 'dbus-run-session -- kwin_wayland --virtual --exit-with-session "$WORK/inner.sh"\nqs -c koompi\n' > "$tmp/test_bad_unnested.sh"
printf 'qs -p probe.qml ipc call x y\n# qs -p probe.qml\ngrep -q "qs -c koompi" f\n' > "$tmp/test_ok_mention.sh"
printf 'out="$(env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen \\\n  HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" qs -p probe.qml)"\n' > "$tmp/test_ok_offscreen.sh"
printf 'env -u WAYLAND_DISPLAY HOME="$WORK/h" XDG_RUNTIME_DIR="$WORK/rt" dbus-run-session -- kwin_wayland --virtual --exit-with-session "$WORK/inner.sh"\nqs -p probe.qml\n' > "$tmp/test_ok_nested.sh"
found="$(scan "$tmp"/test_*.sh)"
for want in test_bad test_bad_rt test_bad_wayland; do
    grep -q "^$want.sh:" <<< "$found" || fail "the scan missed a bare start in $want.sh; it reported: $found"
done
! grep -qE '^test_ok' <<< "$found" || fail "the scan flagged an isolated or merely mentioning file: $found"

files=("$ROOT"/tests/test_*.sh "$ROOT"/tests/measure_*.sh "$ROOT"/tests/bench/*.sh)
for i in "${!files[@]}"; do
    [[ -f "${files[i]}" && "${files[i]##*/}" != "$self" ]] || unset 'files[i]'
done
offenders="$(scan "${files[@]}")"
[[ -z "$offenders" ]] || fail "these start quickshell or Hyprland on the live session; nest the start in a headless KWin on a private bus, or run it offscreen with its own HOME and XDG_RUNTIME_DIR and env -u WAYLAND_DISPLAY -u DISPLAY:
$offenders"
echo "ok   every qs, quickshell, qml and Hyprland start in tests/ is nested or offscreen with a HOME and runtime dir of its own"
