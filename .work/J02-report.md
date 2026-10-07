# J02 report: right panel header, read state

Branch `worktree-agent-aba0d1bad7e7722ef`, two commits on `dev` (9635a8657):

- `6855cde10` sidebar: lead the right panel with today's date, drop the reload button
- `6533e4863` notifications: count as read after the panel has stayed open a second

Note: the worktree was cut from `main` (3f3ab9438), not `dev`, and had no `docs/design/`.
I re-pointed the branch at `dev` with `git checkout -B <branch> dev` (tree was clean) before editing.

## What changed

- `modules/koompi/sidebarRight/SidebarRightContent.qml` (`SystemButtonRow`, ~442-475): uptime text replaced by `DateTime.fullDate`; the `restart_alt` button (hyprctl reload + `Quickshell.reload`) removed; pin, settings, power kept; distro icon kept. The text is width-capped against `systemButtonsRow.x` and `elide: Text.ElideRight`, so a long locale cannot run under the button group. File 532 -> 522 lines (still on the length allowlist, only shrank).
- `services/DateTime.qml:26`: new `fullDate` = `Qt.locale().toString(clock.date, "dddd d MMMM")`. The stale uptime comment ("both consumers: right sidebar and clock popup") rewritten to one line, since only the clock popup reads uptime now.
- `GlobalStates.qml:39-53`: opening the panel still calls `Notifications.timeoutAll()` at once; `markAllRead` moved into a 1000 ms `seenTimer` (`restart()` on open, `stop()` on close).
- `services/Notifications.qml:340`: read-only `unreadCount(): int` on the existing `notifications` IpcHandler.
- `docs/navigation.md`: the "This matters more for the right sidebar" paragraph rewritten to the dwell rule; the Today role line now says the header carries the date, pin, settings and power.
- `docs/manual/05-the-strip-along-the-top.md:53`: also said "opening that panel marks everything read"; rewritten to the dwell rule (not in the job file, but it described the changed behaviour).

## Test

`tests/test_notification_read_state.sh` (81 lines). Static: header uses `DateTime.fullDate`, contains no `DateTime.uptime` / `restart_alt` / `hyprctl`. Live: runs the whole shell (`qs -p`) in a headless `kwin_wayland --virtual` on a private `dbus-run-session` bus with private XDG dirs; `notify-send` delivers a real notification to the shell's own server; `sidebarRight open` + `close` back to back, wait 1.5 s, read `notifications unreadCount`; then open, wait 1.5 s, read, close, read. Skips with a `skip:` line if `kwin_wayland`, `qs`, `dbus-run-session` or `notify-send` is missing (static checks still run first). The inner script kills its `qs` on exit so the temp dir removes cleanly.

Fails without the fix (old `GlobalStates.qml` restored, getter kept, so the failure is the behaviour and not the missing getter):

    ok   source: header shows the date, no uptime, no reload button
    arrived 1
    quick_open_close 0
    open_for_1500ms 0
    after_close 0
    FAIL: an open and close inside 300 ms cleared the unread count: unread is '0', wanted 1

On pure `dev` (all four source files reverted) it fails at the first line: `FAIL: the panel header does not show DateTime.fullDate`.

Passes on the branch:

    ok   source: header shows the date, no uptime, no reload button
    ok   probe: quick open and close keeps the unread count, 1.5 s open zeroes it

The quick open/close is two sequential `qs ipc call` processes; the reading is taken 1.5 s after the close, so a timer that was not stopped would also fail the test.

## Suite

`NO_COLOR=1 ./tests/run.sh` on the committed tree: `102 passed, 3 skipped, 0 failed`.
Skipped: `test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh`.
`test_update_guards.sh` passed here (the baseline had it failing); one more test than baseline is mine; the third skip is not from this change (a run of the suite before I had edited anything also showed 101 passed, 3 skipped, 0 failed).

## Screenshots looked at (shellshot, 1920x1200, `qs.log` clean of TypeError / ReferenceError / Binding loop / Cannot assign)

- `/tmp/j02-shots-before/before.png`: header `Up 0m`, pin, restart, settings, power.
- `/tmp/j02-shots-after/after.png` and `crop2.png`: header `Wednesday 7 October` beside the distro icon, then pin, settings, power; no reload button; rest of the panel unchanged.
- `/tmp/j02-shots-badge/strip.png` (crops of four shots): 1) notification toast plus bell badge in the bar; 2) after open and close at once: toast gone, bell badge still there; 3) after open for 1.5 s: panel open, bell badge gone; 4) closed again: no badge.
- `/tmp/j02-shots-long/crop3.png`: a scratch copy with a 36-character date: text elides to `Wednesday 30 Septe...` and stops at the button group. My first version (width from `parent.width`) overflowed under the buttons with no ellipsis because `Row.implicitWidth` is built from child widths (a circular binding); fixed by capping against `systemButtonsRow.x` instead.

## Could not do / for the lead

- `tests/file-length-allow.txt` still lists `SidebarRightContent.qml` at 532; it is now 522. Not my file to edit; the ratchet row can be lowered.
- `translations/*.json` still hold the now-unused `Up %1` and `Reload Hyprland & Quickshell` keys (contract: not edited).
- Only the Latin locale was rendered (no `km_*` / other locale installed here); the long-string scratch copy stands in for a long locale. `fullDate` uses a fixed `dddd d MMMM` pattern, so day and month names follow the locale but their order does not.
- Not run on the live desktop, by contract.
