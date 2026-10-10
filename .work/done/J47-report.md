# J47 report: bar app identity vs focused window

Commit (rebased onto dev 14ccc506e): 05c5a2986 fix(hyprland): a flood of events no longer holds the focused window back

## Stale sequence
NOT reproduced. The reported symptom (identity lags, unstuck by a new window) was filed 2026-07-29/30 against the polled-hyprctl HyprlandData.qml; the koompi-shelld port (9e34ee134, 2026-08-10) replaced that.
Nested runs, real koompi-shelld, rebased tree (J13 in), bar crop per step vs hyprctl activewindow, all matched:
- r4: 29-step random walk (open/close/focus L/R/up, 3 workspaces, 4 app names incl. long and dotted)
- r5: two outputs (HEADLESS), focus between outputs, empty output, close, open
- r6: search, sidebarRight, launchpad, cheatsheet open/close over a focused window, then focus
- r7: pointer focus (follow_mouse), bar, star button, scratchpad send/toggle
- r1/r8: daemon state vs hyprctl + raw socket2 events: address always equal; only title mismatch inside ~100 ms of an app title change.
Evidence: /home/userx/.tmp/J47/r{1..8} (sheet.png per run, run.log).

## Root cause found (latent, not proven to be the founder's case)
shell-services/hyprland/src/service.rs:163 reset the 30 ms refresh deadline on every event, so events arriving closer than 30 ms apart (a window or two spamming titles) postponed the activewindow query until they stopped. Now `deadline.get_or_insert_with`: first event of a burst sets it.
Test: shell-services/hyprland/tests/event_burst.rs (stub compositor, focus moves at 400 ms, title event every 10 ms). Fails before (3 s timeout, "the focused window never arrived"), passes after. `cargo test -p koompi-hyprland`: 31+1+2+1 passed.

## Screens
Bar crops looked at (sheets r4,r5,r6,r7): names/titles correct, unfocused output dims, Desktop on empty workspace. Pre-J13 run r3 showed name "…" for class x1 (elided name); gone after rebase (r4 shows "X1").
No before/after of a stale bar exists, because no stale case was found.

## Suite
Full suite on rebased tree: 137 passed, 4 skipped (test_bar_keys, test_globalmenu, test_hypridle_logged, test_search_bench_parity), 1 failed test_hypr_modes.sh; it passed on rerun alone (known flake per BACKLOG, Rust-only diff here). No QML file changed, so LaunchFeedback tests not rerun.

## Not done
- No QML change; ActiveWindow.qml untouched.
- hyprshot.sh stubs koompi-shelld with `exit 1`, so the nested bar is always "Desktop" unless the shell is restarted with KOOMPI_SHELLD (my drive*.sh in /home/userx/.tmp/J47 do that). A test around the real bar would need that harness change (not my file).
- Untested: late class change by a client, long-run reconnect (shelld keeps old state on "unavailable"; ShellServices.qml only clears on daemon exit).
