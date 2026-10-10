# J15 report (hand-back message; the harness refused the worker's file)

J15 is done on branch `worktree-agent-a1e11b11540d39ec6`, and the full suite is 0 failed on the tree that ships.
Base `686e9aa20` was confirmed, the worktree is clean, and the diff is 7 files (+243/-66).
I could not write `.work/J15-report.md`: the Write tool refused it ("Subagents should return findings as text"). This message is the report.
Evidence copies are in `/home/userx/.tmp/J15-handoff/`.

**Commits, oldest first**
```
6584ddf00 tests: a nested Hyprland that comes up with no output is started again
98c19ae4a tests: the update, search-focus and Qt platform tests start Hyprland through it
072dcb8ea hyprshot: start Hyprland through tests/nested-hyprland.sh
b01fd591b tests: test_motion times the animation, not the search that starts it
8ba6eb2c2 hyprshot: the host's kded6, mako and dunst are not conflicts in the nested shell
```
Two commit bodies had inexact clauses, so I replayed the branch once with `git rebase --exec` on the same base. Every commit's tree is identical to before.

**Cause of the wedge**
A Hyprland nested in headless KWin sometimes starts with no output and never gets one.
- qs.log shows `qt.qpa.wayland: There are no outputs - creating placeholder screen` and `hyprctl monitors` is `[]`.
- In the four kept update failures the shadow `koompi` ran `update`, but `clients.json` was `[]`.

The cause is aquamarine 0.15.1's Wayland backend.
- `CWaylandBackend::start()` ends `dispatchEvents(); createOutput();`.
- `createOutput()` only queues `create_surface`, `get_xdg_surface`, `get_toplevel` and the first `commit`, and never calls `wl_display_flush`.
- `dispatchEvents()` flushes at its top, but it runs only when the host socket is readable.
- What makes it readable is KWin's `wl_keyboard.keymap`, sent 0.3 ms after the `wl_callback.done` that ends Hyprland's first roundtrip.
- When the roundtrip's read already took the keymap, nothing more arrives. Hyprland idles in `epoll_wait(-1)`: the thread dump shows `wchan=do_epoll_wait` and timeout `0xffffffffffffffff`.

Log lines, from 30 sessions with `WAYLAND_DEBUG=client` on Hyprland and `server` on KWin:
- In each of the 5 wedged sessions, KWin's log ends at `-> wl_keyboard#3.keymap(1, fd 61, 35572)`, 109 identical lines.
- Hyprland's log shows `wl_keyboard#3.keymap(...)` received before `-> wl_compositor#4.create_surface(...)` in all 5 wedged runs, and after it in all 25 healthy ones.
- In healthy runs the keymap arrives about 114 ms later and wakes the loop.

Demonstration, not only correlation:
- I added one line, `wl_display_flush(waylandState.display);`, at the end of `createOutput()` in 0.15.1.
- I built it in scratch and loaded it into the nested Hyprland through `LD_LIBRARY_PATH` only; nothing was installed.
- In alternating batches of 15, three at a time: 60 of 60 starts got an output with the flush, 44 of 60 with the packaged library.
- Upstream fixed it after 0.15.1 (hyprwm/aquamarine#415, `7bb8bdf4e`).
- KOOMPI does not package aquamarine, and real sessions use the DRM backend, so only nested test sessions meet this.
- Only the one-line flush was tested, not all of #415.

**Fix**
- `tests/nested-hyprland.sh` (new, sourced): `nested_hyprland_start CONFIG LOG` finds Hyprland by the pid in its `hyprland.lock` and waits 5 s for an output.
- With no output it stops that Hyprland and its children and starts another, ten starts at most.
- A Hyprland that dies on its own is not restarted, and a config without `no_update_news` and `no_donation_nag` is refused.
- `tests/test_nested_hyprland_start.sh` (new) holds the policy with stand-ins. It fails with one start allowed, and fails again with a stopped Hyprland's children left running.
- The update, search-focus and Qt platform tests call the helper (`test_update_now_runs.sh:120-121`, `test_search_window_focus.sh:96-97`, `test_qt_platform_nested.sh:38-42`). J09's session retry is gone.
- `hyprshot.sh` calls the helper too, so it now needs `tests/nested-hyprland.sh` in the same tree. Merge both together.

**Tallies** (three at a time, one `heavy.sh` call each)

| test | before | after |
| --- | --- | --- |
| `test_update_now_runs.sh` | 16 passed, 4 failed (88 s each) | 60 of 60 |
| `test_search_window_focus.sh` | 18 passed, 2 failed (60 s each) | 20 of 20 |
| `test_qt_platform_nested.sh` | J09's retry | 20 of 20, no retry |

- Of the 124 starts in those 100 runs, 24 came up empty. Each was restarted, none gave up, and the slowest run took 24 s.
- An earlier helper with 3 starts of 10 s failed 1 qt run in 20, hence ten starts of 5 s.
- All 6 failures before had "There are no outputs" in qs.log; the 4 update ones also had an empty `hyprctl clients`.

**Full suite**
Run through `heavy.sh` on tree `e4cd368c9be8`, which is the branch tip's tree.
```
126 passed, 4 skipped, 0 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

**test_motion.sh**
It had no cause named, so I named one.
- The failures were the search pill's "reduce motion on: ... settles in 61-178 ms, budget 60" and once `elementMoveEnter ran 266 ms, limit 260`.
- The pill's clock started at `LauncherSearch.query = "a"`, and that assignment is the search. It blocks the UI thread 25-78 ms (median 40), and the first step comes 33-66 ms in (median 49). With Reduce Motion the animation is 0 ms, so the 60 ms budget measured the search.
- With a stall logger running, 153 of 175 stalls of 60 ms or more fell in the search phase, and only 11 had a `config.json` write beside them. Config's synchronous writes are not the main cause.
- `settle()` now clocks from the property's first step, and the role timing takes the best of three.
- `proveSettle` fails 3 runs in 3 on the old clock ("a jump after a 150 ms block settles in 150 ms").
- Before: 59 of 62 plain runs passed, and 4 of 15 with the logger. After: 60 of 60, and 15 of 15 with the logger.

**Crashes my runs caused today: 4** (journal entries, attributed by cwd and command line)
- qs SIGSEGV at 11:29:47 and 11:30:18, in my bare 60-run `test_motion` batch (`qs -p motion_probe.qml`).
- easyeffects SIGABRT at 10:53:04 and 14:02:33, inside my two full-suite runs (cwd is my worktree).
- None came from Hyprland, KWin, wezterm, the hyprshot runs or the gdb runs.
- There were 10 easyeffects aborts today, one per worktree suite run, so each re-run you do adds one.
  - The crashed command is `easyeffects --hide-window --service-mode`, which is what `EasyEffects.enable()` runs.
  - So some nested full-shell test starts the real binary (J12's toggle defaults on). I did not investigate or touch it.

**The qs crash hunt: no backtrace**
- I ran 69 gdb-wrapped runs of the patched probe; all reached `PROBE DONE` and none crashed.
- The bare rate was 2 in 60. I did not fall back to the bare hunt.
- When quickshell crashed, it relaunched, ran the probe again from the start, and the test passed. So the test hides a crash.
- The crashes appeared only in the patched probe (2 of 90 runs, against 0 of about 125 before). My busy-wait in `proveSettle` cannot be excluded as a trigger. If it correlates, swap `while (Date.now() < end) {}` for a Timer delay. Other probes crashed on 10-07 too (`media_probe`, `recent_probe`), so the family pre-exists.
- Decision for you:
  - (a) more gdb runs, which at the bare rate would take about 100 runs to expect 3 crashes;
  - (b) a bare hunt under `ulimit -c 0`, which I could not test without crashing something and so do not know suppresses the journal entry;
  - (c) make `test_motion` fail when qs relaunches, which would make it red about 3% of the time until the crash is fixed.

**Merge note**
- `dev` has 13 commits since my base. Merging conflicts in one file only, `.work/tools/hyprshot.sh`, where dev's `5033bff71` app-kill block sits next to my log-copy line.
- The resolved file (dev's copy plus my hunks) is `/home/userx/.tmp/J15-handoff/hyprshot.sh.merged-with-dev-5033bff71`.
- I ran it 3 times with dev's `heavy.sh` while the host's kded6 was running: 3 of 3 screenshots, no stderr, no dialog.

**Other findings**
- `hyprshot`: the shell's ConflictKiller read the host's kded6 and put a "Kill conflicting programs?" window over the search pill. It showed in 5 of the 5 screenshots I opened. The new `pidof` stub answers "none" for kded6, mako and dunst only. A blanket stub would make the shell start a real easyeffects per screenshot.
- One update run took 200 s and passed (the session's own `timeout 200` ended it). It had no restart, and 100 later runs with a process snapshot armed did not hang, so the cause is unknown.
- `test_hypr_modes.sh` still starts its nested Hyprland by hand. It never needs an output, so I left it (not owned).
- My first gdb hunt held the heavy lock about 15 minutes in one call before I stopped it at a wave boundary. Later calls were bounded.

**Evidence**
- `/home/userx/.tmp/J15-handoff/` holds the wire-log excerpts, the aquamarine patch and the 120-start comparison, the tallies, the suite output, the motion latency and stall statistics, the baseline failure logs, screenshots, and `scripts/`.
- My scratch lab, `/home/userx/.tmp/j15-lab.hAprHS` (43 MB), is safe to delete by that exact path.
