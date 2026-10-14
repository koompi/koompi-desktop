#!/usr/bin/env bash
# The lock screen is the shell. A reload while the session is locked (logind's LockedHint)
# must not stop qs - that leaves Hyprland's "lockscreen app died" screen - but leave the
# restart for after the unlock, as a marker the shell's lock picks up. It happened twice on
# 2026-10-13, both from ./setup update on a locked seat.
# setup's reload_session and koompi update's path are both checked; loginctl, pgrep, hyprctl
# and setsid are stubs, so nothing reaches the live session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/rt"
cat > "$stub/loginctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list-sessions) printf '7 %s user seat0 tty1\n' "$(id -u)" ;;
    show-session)  printf 'yes\n' ;;
esac
EOF
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/stopped"\nexit 1\n' "$tmp" > "$stub/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/hyprctl"
printf '#!/usr/bin/env bash\n: > "%s/restarted"\n' "$tmp" > "$stub/setsid"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/qs"
chmod +x "$stub"/*

out="$(PATH="$stub:$PATH" HYPRLAND_INSTANCE_SIGNATURE=test XDG_RUNTIME_DIR="$tmp/rt" bash -c '
    source "$1/sdata/lib/common.sh"
    DRY_RUN=false
    stop_processes() { printf "%s\n" "$*" >> "$2/killed"; }
    reload_session' _ "$REPO_ROOT" "$tmp" 2>&1)"
status=$?

(( status == 0 )) || fail "reload_session failed on a locked session ($status): $out"
[[ -e "$tmp/killed" ]] && fail "reload_session stopped the shell under the lock: $(cat "$tmp/killed")"
[[ -e "$tmp/restarted" ]] && fail "reload_session started a second shell under the lock"
[[ -e "$tmp/rt/koompi/shell-restart-pending" ]] || fail "reload_session left no restart for after the unlock"
grep -q "restarts itself when you unlock" <<< "$out" || fail "reload_session did not say the restart waits for the unlock: $out"

# koompi update takes the same way out
grep -q 'session_locked && { defer_shell_restart; return 0; }' "$REPO_ROOT/dots/.local/share/koompi/libexec/update" \
    || fail "koompi update does not defer the shell restart on a locked session"
grep -q '^defer_shell_restart()' "$REPO_ROOT/dots/.local/share/koompi/libexec/update-lib.sh" \
    || fail "update-lib.sh has no defer_shell_restart"

(( failed )) || echo "ok   reload: a locked session keeps its shell, and the restart waits for the unlock"
exit $failed
