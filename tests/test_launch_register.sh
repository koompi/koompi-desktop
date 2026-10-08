#!/usr/bin/env bash
# Launch feedback (audit 3.11, F10), the script's half: before it starts an app,
# koompi-launch tells the running shell what is opening, in the background, so a
# key bind gets the same "Opening X" a Search launch does. qs is a PATH shim that
# records its argv and answers as a real shell would; nothing here reaches the
# live shell. The pairing with hyprland/scripts/launch_first_available.sh is real:
# the program koompi-launch names must be the one that script then starts.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH="$REPO_ROOT/dots/.local/bin/koompi-launch"
FIRST="$REPO_ROOT/dots/.config/hypr/hyprland/scripts/launch_first_available.sh"
LAUNCHER_SEARCH="$REPO_ROOT/dots/.config/quickshell/koompi/services/LauncherSearch.qml"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

[[ -x "$LAUNCH" ]] || { echo "FAIL: $LAUNCH is not executable" >&2; exit 1; }
[[ -x "$FIRST" ]] || { echo "FAIL: $FIRST is not executable" >&2; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "skip: timeout not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/rt" "$tmp/home" "$tmp/share/applications"
chmod 700 "$tmp/rt"

# the shell as a script sees it: logs its argv, can hang, answers with QS_ANSWER and exits QS_RC
cat > "$tmp/bin/qs" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QSLOG"
[[ -z ${QS_HANG:-} ]] || { : > "$QSHUNG"; sleep "$QS_HANG"; }
printf '%s' "${QS_ANSWER-ok}"
exit "${QS_RC:-0}"
SH
cat > "$tmp/bin/logger" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOGGERLOG"
SH
# the apps: each leaves its name and pid, and stops; the shebang is absolute so one can start with no PATH
for app in app-one app-two app-three; do
    printf '#!%s\nprintf "%%s %%s\\n" "%s" "$$" >> "$APPLOG"\n' "$(command -v bash)" "$app" > "$tmp/bin/$app"
done
chmod +x "$tmp/bin"/*

export QSLOG="$tmp/qs.log" QSHUNG="$tmp/qs.hung" LOGGERLOG="$tmp/logger.log" APPLOG="$tmp/app.log"

# run koompi-launch the way a key bind does, in a runtime dir with no user manager
launch() {
    env PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/rt" XDG_DATA_HOME="$tmp/share" XDG_DATA_DIRS="$tmp/none" \
        QS_ANSWER="${QS_ANSWER-ok}" QS_RC="${QS_RC:-0}" QS_HANG="${QS_HANG:-}" "$LAUNCH" "$@" 2> /dev/null
}
reset() { rm -f "$QSLOG" "$QSHUNG" "$LOGGERLOG" "$APPLOG"; }
waits_for() { for _ in $(seq 1 60); do [[ -s $1 ]] && return 0; sleep 0.1; done; return 1; }
settles() { sleep 0.5; }

# 1. a plain command: its id, its program and the process that becomes the app
reset
launch --id fileManager app-one --new-window
waits_for "$QSLOG" || fail "no notice reached the shell"
waits_for "$APPLOG" || fail "the app did not start"
read -r _ app_pid < "$APPLOG"
want="-c koompi ipc --any-display call launch begin -- fileManager app-one $app_pid"
[[ "$(cat "$QSLOG" 2> /dev/null)" == "$want" ]] || fail "the notice is '$(cat "$QSLOG" 2> /dev/null)', want '$want' (the pid is the app's: exec keeps it)"
[[ "$(wc -l < "$QSLOG")" -eq 1 ]] || fail "more than one notice for one launch"

# 2. a desktop entry: the id is the entry's, the program is what its Exec runs
reset
printf '[Desktop Entry]\nType=Application\nName=One\nExec=%s/app-one %%U\n' "$tmp/bin" > "$tmp/share/applications/probe-one.desktop"
launch probe-one.desktop
waits_for "$QSLOG" || fail "an entry's launch sent no notice"
want="-c koompi ipc --any-display call launch begin -- probe-one app-one"
[[ "$(cat "$QSLOG")" == "$want"* ]] || fail "the entry's notice is '$(cat "$QSLOG")', want '$want <pid>'"

# 3. a wrapper that picks its program at run time: the notice names the one it picks
for candidates in "no-such-app-x|app-two -1|app-three" "no-such-app-x||app-three" "app-one|app-two"; do
    reset
    IFS='|' read -r -a args <<< "$candidates"
    launch --id terminal "$FIRST" "${args[@]}"
    waits_for "$QSLOG" || fail "the wrapper's launch sent no notice for '$candidates'"
    waits_for "$APPLOG" || fail "the wrapper started nothing for '$candidates'"
    read -r started _ < "$APPLOG"
    noticed="$(awk '{ print $(NF - 1) }' "$QSLOG")"
    [[ "$noticed" == "$started" ]] || fail "for '$candidates' the wrapper started '$started' and koompi-launch told the shell '$noticed'"
done
reset
launch --id terminal "$FIRST" no-such-app-x no-such-app-y
waits_for "$QSLOG" || fail "a wrapper with nothing to start sent no notice"
[[ "$(awk '{ print $(NF - 1) }' "$QSLOG")" == launch_first_available.sh ]] \
    || fail "a wrapper with nothing to start: the notice names '$(awk '{ print $(NF - 1) }' "$QSLOG")'"

# 4. quiet: --registered (a shell surface already told it), --terminal (the window is the terminal's)
reset
launch --registered --id fileManager app-one
launch --terminal "env" --id fileManager app-two
waits_for "$APPLOG" || fail "the quiet launches did not start their apps"
settles
[[ ! -e "$QSLOG" ]] || fail "a launch that must stay quiet told the shell: $(cat "$QSLOG")"

# 5. the shell's answers: ok, ignored, no shell running say nothing; anything else is logged
for case in "ok|0|" "ignored|0|" "|255|" "Target not found.|0|Target not found" "|1|qs exit 1" "boom|3|qs exit 3: boom" "nonsense|0|answered 'nonsense'"; do
    IFS='|' read -r answer rc want_log <<< "$case"
    reset
    QS_ANSWER="$answer" QS_RC="$rc" launch --id fileManager app-one
    waits_for "$QSLOG" || fail "answer '$answer' rc $rc: no notice"
    settles
    if [[ -z "$want_log" ]]; then
        ! grep -q 'launch notice' "$LOGGERLOG" 2> /dev/null || fail "answer '$answer' rc $rc must be silent, logged: $(cat "$LOGGERLOG")"
    else
        grep -qF -- "$want_log" "$LOGGERLOG" 2> /dev/null || fail "answer '$answer' rc $rc: want a log line with '$want_log', got '$(cat "$LOGGERLOG" 2> /dev/null)'"
    fi
done

# 6. a shell that hangs delays nothing, holds nothing open, and is cut off and said so
reset
start="$(date +%s%N)"
out="$(QS_HANG=6 timeout 4 env PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/rt" QSLOG="$QSLOG" QSHUNG="$QSHUNG" QS_HANG=6 "$LAUNCH" --id fileManager app-one 2>&1)"
rc=$?
elapsed=$((($(date +%s%N) - start) / 1000000))
(( rc == 0 )) || fail "a hanging shell stopped the launch, rc $rc after $elapsed ms (a capture of its output waited for it)"
(( elapsed < 2000 )) || fail "a hanging shell delayed the launch by $elapsed ms"
[[ -e "$QSHUNG" ]] || fail "the hang case never reached the shell shim"
waits_for "$APPLOG" || fail "the app did not start while the shell hung"
for _ in $(seq 1 50); do grep -q 'no answer' "$LOGGERLOG" 2> /dev/null && break; sleep 0.2; done
grep -q 'no answer from the shell in 3 s' "$LOGGERLOG" 2> /dev/null || fail "a shell that never answered was not logged: '$(cat "$LOGGERLOG" 2> /dev/null)'"

# 7. no qs at all: the launch is the same, and says nothing in the journal either
reset
mkdir -p "$tmp/only"
printf '#!%s\nprintf "%%s\\n" "$*" >> "$LOGGERLOG"\n' "$(command -v bash)" > "$tmp/only/logger"
chmod +x "$tmp/only/logger"
env -i PATH="$tmp/only" HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/rt" APPLOG="$APPLOG" LOGGERLOG="$LOGGERLOG" "$(command -v bash)" "$LAUNCH" --id fileManager "$tmp/bin/app-one" 2> "$tmp/err7" \
    || fail "without qs the launch failed: $(cat "$tmp/err7")"
waits_for "$APPLOG" || fail "without qs the app did not start"
settles
grep -v 'no user manager' "$tmp/err7" | grep -q . && fail "without qs the launch said something: $(cat "$tmp/err7")"
! grep -q 'launch notice' "$LOGGERLOG" 2> /dev/null || fail "without qs the launch logged a notice failure: $(cat "$LOGGERLOG")"

# 8. the shell's own surfaces tell it themselves, then stay quiet in the script
grep -q 'LaunchFeedback.begin(entry)' "$LAUNCHER_SEARCH" || fail "LauncherSearch.launch does not register the launch with LaunchFeedback"
grep -q '"koompi-launch", "--registered"' "$LAUNCHER_SEARCH" || fail "LauncherSearch.launch registers and then lets koompi-launch register again"

(( failed == 0 )) || exit 1
echo "ok   koompi-launch: one background notice per launch naming the id, the program and the pid, the wrapper's own pick, quiet for --registered and --terminal, logged unless ok, ignored or no shell, never waited for"
