# J13 report (hand-back message; the harness refused the worker's file)

J13 launch feedback is done, with the leak fix and the several-launches report. Branch `worktree-agent-a7271d96bc79bf83f`, base 686e9aa20, 22 commits, tip `b389e9a0e`, tree clean. I did not write `.work/J13-report.md`: the harness refuses report .md files from a subagent and I did not retry. This message is the report. Evidence and screenshots are in `/home/userx/.tmp/J13-handoff/`.

**Commits, oldest first**
- `ad3bc6e03` launch feedback: a service that knows which launches have shown no window yet
- `93f239da9` koompi-launch: tell the shell what is opening, in one background call
- `161159e8d` launch feedback: a window counts by when it first showed up, so a late notice does not lose it
- `febba0988` bar: the app identity says Opening while an app starts, and an empty desktop reads Desktop alone
- `161e5b019` tests: a key bind's launch end to end in a nested Hyprland, with the bar's pixels read
- `8c91f8710` tests: the media panel's remembered app launches with --registered
- `a041ca21c` launch feedback: an entry is found by id or by the program its Exec runs, never by a fuzzy lookup; the pulse starts bright
- `d71cf8a9d` bar: the identity's name is a whole number of pixels wide, so a fractional scale no longer cuts it short
- `ab8eb23be` tests: the nested launch tests end everything they start, and fail when anything outlives the session
- `2fbdf8334` launch feedback: a window ends one launch for as long as it exists, not for one sweep
- `17bbd7ea4` comments: one short line where a why survives
- `4f66abc64` bar: the pulse dims the icon and the name, never the Opening line, and never below what keeps the text legible
- `d4a495902` tests: several launches at once, the way session restore starts them
- `946320b8c` **launch feedback: read the window list and the focus from one push** (the defect found late, below)
- `d15165ef7` tests: the register test's failure messages no longer cat a log that was never written
- `da3d4c419` tests: the nested launch test starts a dialog again when the loaded compositor never maps it
- `6b46e8aaf`, `4a5fec49a`, `5ac3ba55f` tests: the identity probe's relaunch and closed-window scenarios, each from a clean state, with timing fixed
- `f8e139c86` tests: the nested launch test waits for the bar before it looks at the empty desktop
- `9d9e9afaf` tests: the nested launch test closes an earlier launch's window while the next launch waits
- `b389e9a0e` tests: one comment above the nested test's scenario helpers, not two

Docs went in with the commits that changed behaviour (`docs/navigation.md`, manual 05 and 11).

**Cause of the nested "Desktop" in J09's renders**
- It is the harness, not the shell. `hyprshot`/`shellshot` start the shell with a stub `koompi-shelld` that runs `exit 1`.
- `ShellServices.hyprland` then stays null, `HyprlandData` has no windows or active window, and the bar reads "Desktop" whatever is focused.
- With the real daemon, asked for its hyprland service only, the same session reads "Dolphin / Home".
- Evidence: `evidence/nested-desktop-cause-stub-daemon.png`, `evidence/nested-desktop-cause-real-daemon.png`, `evidence/hyprshot-real.sh` and its diff.
- The shell needs no fix. My nested tests run the real daemon. I did not touch `hyprshot.sh`.

**The two screenshots**, from the final tree
- `shots/launch-0.3s.png`: the desktop is empty apart from the clock widget. The bar's left end shows the star launcher, then the Okular icon and "Slow Probe" in bold over "Opening…". The name and icon are a little dim from the pulse.
- `shots/launch-3s.png`: the kdialog box is up in the middle and focused. The identity is now "Kdialog" over "slow-…", the real window's name with its title cut at the name's width. No icon, no Opening.
- `shots/empty-desktop.png`: "Desktop" alone, no second line.
- `shots/launch-again-0.3s.png`: a third launch while the earlier dialog is still open and focused. The bar says "Slow Probe / Opening…", not the dialog's identity.
- Also in `shots/`: Reduce Motion, light palette and 1.25-scale crops, and the pid-matched variant.
- Contrast on the dark palette, measured from the Reduce Motion render held at 0.7: name 7.52:1, Opening line 5.90:1.
- Light palette at 0.7: name 5.3:1, computed from the measured full-opacity colours, not rendered. The light Opening line is 3.1:1, the pre-existing subtext colour; the real title line in that bar is 2.97:1. I left that alone.

**Tests: failing before, passing after** (outputs in `evidence/final-tree/`, `evidence/final-nested/`, `evidence/final-probe/`)

| Test | On dev (686e9aa20) | Shell before `946320b8c`, final tests | Final tree |
|---|---|---|---|
| `test_launch_match.sh` | `FAIL: missing dots/.config/quickshell/koompi/services/launch-match.js` | not applicable | ok |
| `test_launch_register.sh` | `FAIL: no notice reached the shell`, plus about thirty more FAIL lines | not applicable | ok |
| `test_launch_identity.sh` | the probe config does not load: `Script qs:@/qs/services/launch-match.js unavailable` | 3 of 3 runs fail: `FAIL relaunch: focus that was there before the launch does not end it: 'ProbeWindowClass'` and `FAIL closed: hearing that the first window has closed does not end it: 'Desktop'` | `PROBE DONE 0`, 55 PASS |
| `test_launch_feedback_nested.sh` | `FAIL: before any launch the shell says 'Target not found.' is opening`; the bar reads "Desktop Works…" at the empty desktop and at 0.3 s | 3 of 3 runs fail: `FAIL: slowagain: the shell stopped saying it is opening at 637 ms, before the window mapped at 1650 ms` (also 708 ms and 632 ms) | ok in 2 of 2 runs and in the suite |

- The identity probe's mutants on the committed shell: 20 of 21 killed.
- The one survivor reads the sibling property inside a handler on the snapshot itself. That is equivalent, because the sibling is already updated there.
- Re-running the original pre-fix shape (handler on `windowListChanged`, focus read off `activeWindow`) is killed by both new scenarios.
- All 26 mutants of `launch-match.js` are killed.

**Full suite on the final tree**
```
128 passed, 4 skipped, 1 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
failed: test_search_window_focus.sh
```
- The failure is the nested start-up wedge J09 and J15 documented: `qt.qpa.wayland: There are no outputs - creating placeholder screen`. It passes 2 of 2 standalone on the final tree under heavy.sh.
- The suite one test revision earlier gave `129 passed, 4 skipped, 0 failed`, with that test passing.
- The suite ran on `5ac3ba55f`. The tip differs only by a deleted duplicate comment.

**Defect found late and fixed: `946320b8c`**
- Symptom: in an eight-launch back-to-back run, launches 2, 3, 4, 7 and 8 never showed Opening.
- Cause: inside `HyprlandData.onWindowListChanged`, `HyprlandData.activeWindow` still held the previous push. Qt re-evaluates the bindings of one push one after another, and the handler runs between them.
- Effect: the shell judged each push by a new window list and an old focus. Focus moves were stamped late, at the next launch's start.
- Two ways a launch then ended with no window: an app started again just after its window closed, and an app started while its own window sat focused with the notice 100 ms late.
- Fix: read windows and focus from `HyprlandData.state` in `LaunchFeedback.qml`, and run on the snapshot changing.
- Proof the cause is the read order: an offscreen replay with the real `LaunchFeedback` and a copy of the two bindings (`evidence/push-order/`) fails both cases before the fix and passes both after.
- Eight back-to-back launches on the final tree: every one shows Opening from 379 to 393 ms and ends 210 to 240 ms after its own window maps (`evidence/final-tree/variant-stress.txt`).
- I first tried a matcher guard (focus counts only for a window in the list). It did not fix the relaunch case, so I reverted it.
- The nested test's third scenario now closes the earlier dialog after the shell has the launch, which makes it fail on the old shell every time. Every scenario also asserts the shell never stops saying "opening" before its own window maps.

**Leak fix (your first message)**
- Cause: the old test ended windows by title and class only and relied on a pattern kill. An app whose window never mapped survived, and Hyprland double-forks `exec_cmd` children, so `pgrep -P` misses them.
- Now: every app registers pid and start time in a file. After each scenario the windows are closed the way a user closes them, then registered pids go TERM then KILL. A stop file makes a launch still on its way do nothing. An EXIT trap sweeps anything still carrying the session's private `XDG_RUNTIME_DIR` by `/proc/*/environ`, names it as `LEAK`, ends it by pid and fails the test. No pattern kills.
- Before: the old test with apps that never map left 4 processes (`launch_first_available.sh`, the app script, two `sleep 60`).
- After: 22 runs (11 of the nested test, plus its variants, the dev runs and the suite) left 0 processes carrying a nested runtime dir. In those same runs `pgrep -af slow-probe-app` and `pgrep -af 'launch_first_available.sh no-such-app-x'` print nothing. Per-run lines are in `evidence/final-tree/leak-summary.txt`.
- The literal `pgrep -af launch_first_available` also lists the founder's own Chrome-launch wrapper, so I used the exact argument.
- A deliberate leaker (a stray `sleep 500` from the bind) is named `LEAK: pid N (sleep) outlived the nested session`, ended by pid, and the test fails with exit 1.
- The abort path (SIGTERM mid-run) was checked only against fake kwin and Hyprland, where everything was reaped.
- The test never starts the host's easyeffects or hyprsunset. Its `pidof` stub says they are running and delegates every other name to the real `pidof`.
- Batch 3a was complete. Batch 3b never ran. Nothing here rests on either; every figure comes from batches on the final tree.

**Several launches pending at once (your second message)**
- The bar shows the newest pending launch.
- The shell keeps eight; the oldest are forgotten first.
- Each launch ends at its own window in any order. One window ends one launch for as long as it exists, and one focus move ends one.
- A launch that never maps blocks no other. It ends at its own 8 s, and only hides older pending ones while it is the newest.
- Covered by `test_launch_match.sh` ("several apps at once", three checks) and `test_launch_identity.sh` (`several()` and `crowd()`).
- Real eight-launch run: the final-tree numbers above.

**Not done or unverified**
- Not run: two monitors, the vertical bar (it has no identity), fullscreen and notification states over the bar.
- Not run: `systemd-run --scope` keeping the pid for the pid rule. The nested session has no user manager, so I did not test it and did not touch the live manager.
- The live seat and a deploy are untouched.
- Hardest limit: the nested harness stalls. In about 60 launches, 2 started a dialog that never mapped (kdialog in a futex, empty client list), both right after another dialog closed. One batch also lost three session starts to KWin's no-output wedge. This looks like J15's stall. The nested test now starts a never-mapped dialog once more and prints a `note:`, and waits for the bar surface before the empty-desktop screenshot.
- `coredumpctl` in my batch windows lists only node and easyeffects aborts, with no core files. No Hyprland, kwin_wayland, qs, kdialog or koompi-shelld. I did not attribute them.

**For others, not mine**
- Launch paths that bypass `LauncherSearch.launch` and `koompi-launch`, so no Opening and no `app.slice`: the waffle family (`startMenu/searchPage/SearchResultButton.qml:31`, `startPage/AppCategoryGrid.qml:282`, `startPage/BigAppGrid.qml:33`, `bar/tasks/TaskAppButton.qml:51,57,117`), all `DesktopEntry.execute()`. J45's brief covers them.
- `services/SessionRestore.qml:131` still calls `entry.execute()` on my base; J43's merge on dev routes it through `LauncherSearch.launch`. After the rebase, restore announces each app once.
- Proposed line for `koompi_de_gotchas` under QML (I did not write the shared vault): "A handler for one property's change sees the previous value of its siblings bound to the same source. Qt re-evaluates one push's bindings one after another and the handler runs between them. Read the source object in the handler. Repro: `evidence/push-order/qt-handler-sees-previous-sibling.qml`."

All scratch work dirs my tests kept have been removed by exact path.

## Round 2 (rebased at a38dc9c5a)

Three tests fixed in 412b6dd8d, eb6bb6721, b957130b9; full suite 138 passed, 4 skipped, 0 failed. Evidence: J13-handoff/evidence/round2/.
