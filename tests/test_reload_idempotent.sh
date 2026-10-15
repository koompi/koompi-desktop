#!/usr/bin/env bash
# Guards: a reload must not abort on a daemon that was not running, and it stops only
# this session's shell: a nested test shell runs with its own XDG_RUNTIME_DIR and must
# survive a deploy (one used to blank a worker's renders).
#
# pgrep, hyprctl, loginctl and setsid are shadowed; the session's own shell is never in the
# stub's answers.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
stub="$tmp/bin"
mkdir -p "$stub"
export KILLALL_LOG="$tmp/killall.log"
: > "$KILLALL_LOG"

# Stand-ins named `qs` whose command line carries `-c koompi`, so count_shells has
# something honest to read out of /proc. `; :` keeps bash from exec-optimising the
# sleep, which would replace the process name. One runs in this session's runtime
# dir, the other in a nested test's.
ln -s "$(command -v bash)" "$stub/qs"
export SESSION_RT="$tmp/session-rt" TEST_RT="$tmp/test-rt"
mkdir -p "$SESSION_RT" "$TEST_RT"
XDG_RUNTIME_DIR="$SESSION_RT" "$stub/qs" -c 'sleep 30; :' -c koompi &
export FAKE_QS_PID=$!
XDG_RUNTIME_DIR="$TEST_RT" "$stub/qs" -c 'sleep 30; :' -c koompi &
export TEST_QS_PID=$!
export RESTARTED="$tmp/restarted.pid"

cleanup() {
    kill "$FAKE_QS_PID" "$TEST_QS_PID" "$(cat "$RESTARTED" 2>/dev/null)" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$stub/pgrep" <<'EOF'
#!/usr/bin/env bash
name="${!#}"
case "$name" in
    # The case that used to abort the whole update: the daemon is not running,
    # because the shell that starts it has just been stopped.
    koompi-global-m)    exit 1 ;;
    quickshell)         exit 1 ;;
    qs)                 printf '%s\n' "$FAKE_QS_PID" "$TEST_QS_PID"; cat "$RESTARTED" 2>/dev/null; exit 0 ;;
esac
exit 1
EOF

printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/hyprctl"
# an unlocked session, whatever the machine running the test is doing (test_reload_while_locked.sh has the locked one)
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/loginctl"
# the restart starts a fresh stand-in in this session, as the real setsid qs -c koompi would
cat > "$stub/setsid" <<'EOF'
#!/usr/bin/env bash
XDG_RUNTIME_DIR="$SESSION_RT" "$(dirname -- "$0")/qs" -c 'sleep 30; :' -c koompi > /dev/null 2>&1 &
printf '%s\n' "$!" > "$RESTARTED"
EOF
chmod +x "$stub"/pgrep "$stub"/hyprctl "$stub"/setsid "$stub"/loginctl
PATH="$stub:$PATH"

# shellcheck source=sdata/lib/common.sh
source "$REPO_ROOT/sdata/lib/common.sh"

HYPRLAND_INSTANCE_SIGNATURE=test-session
XDG_RUNTIME_DIR="$SESSION_RT"
ASSUME_YES=false   # so a prompt would be a real prompt

out="$tmp/out"
# stdin is closed: if anything asks the user a question, read gets EOF, run()
# takes the default branch and dies, and the status below is non-zero.
reload_session > "$out" 2>&1 < /dev/null
status=$?

fail() { printf '%s\n--- output ---\n%s\n' "$1" "$(cat "$out")" >&2; exit 1; }

(( status == 0 )) ||
    fail "reload_session returned $status when one of the named processes was simply not running"

grep -q 'retry' "$out" && fail 'reload_session prompted the user'
grep -q 'aborted' "$out" && fail 'reload_session aborted'

kill -0 "$FAKE_QS_PID" 2>/dev/null && fail "this session's shell was not stopped"
kill -0 "$TEST_QS_PID" 2>/dev/null || fail "a shell with another XDG_RUNTIME_DIR (a nested test's) was stopped"

# And the outcome has to be reported from what is running, not asserted.
grep -q 'shell restarted' "$out" ||
    fail 'reload_session did not confirm the shell came back'

printf 'reload idempotency test passed\n'
