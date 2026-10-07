# J15: `test_update_now_runs.sh` fails about one run in four under load

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: `tests/test_update_now_runs.sh`; `modules/koompi/bar/UpdatesPopup.qml` only if the cause is there.

## Evidence (lead, 2026-10-07, `dev` at `e6d563717`)

- 3 failures in 11 runs, each `FAIL: Update now opened no window (hyprctl clients is empty)` after the full 60 s client wait (runs take 88 s instead of 6 s).
- In every failed run the shadow `koompi` recorded `update`, so the terminal started and ran its child; its window never reached `hyprctl clients`.
- wezterm's GUI log is the same in failed and passing runs: one portal appearance warning at start, "Broken pipe" at teardown.
- Failures came while two other workers ran nested sessions; six quiet runs in a row passed. The J01 worker saw it once inside a loaded suite run, before the private-bus change.
- Kept runtime dirs from two failures: `/tmp/hr.jZwbjN` and `/tmp/hr.BJn5Mj` (wezterm and Hyprland logs). Their work dirs under `~/.tmp` were lost to a worker's glob `rm`. A third failure from a full-suite run is in `/home/userx/workspace/koompi/koompi-desktop/.work/J15-evidence/j06-suite-sample/`. Do not delete any of them.

## Do

1. Find why the window does not map: run the nested session with Hyprland's verbose log (`debug:disable_logs = false`, or the Lua equivalent from `/usr/share/hypr/stubs/hl.meta.lua`) and wezterm's (`WEZTERM_LOG=debug`), under load (run three copies at once), until a failure is captured. Name the cause from the logs, not a guess.
2. Fix the cause. If it is the harness (timing, GPU contention, the terminal choice), make the test deterministic; a longer wait is not a fix unless the logs show the window arrives late.
3. Prove it: 20 runs, three at a time, 0 failures; paste the tally.

## Acceptance

- The cause in one paragraph with the log lines behind it.
- The tally before and after.
- Full suite: 0 failed.

## Lead notes at dispatch (2026-10-07)

- J09 found a start-up wedge in the harness: KWin sometimes never finishes its dmabuf feedback, so the nested Hyprland has no output.
  - The symptoms are `qt.qpa.wayland: There are no outputs - creating placeholder screen`, grim's `no wl_output`, and nothing mapping.
  - J09 saw four of these in about 35 sessions, before and after the heavy lock.
  - `test_search_window_focus.sh` failed once that way in J09's full-suite run.
  - Your symptom (no client after 60 s although the shadow `koompi` ran) fits a session with no output.
  - Check the kept logs for it first.
- Fix it where nested sessions start:
  - `tests/test_update_now_runs.sh`, `tests/test_search_window_focus.sh` and `tests/test_qt_platform_nested.sh` (J09's retry loop at `:131-136`, which is a workaround, not the fix).
  - `.work/tools/hyprshot.sh`, which has no guard and printed `no images` once.
  - These files become yours for this.
  - If the cause is shared, fix it once and say where.
  - Remove J09's retry once the root fix holds.
- Proof stays as written: 20 runs, three at a time, 0 failures, for the update test and for one other nested test.

## More evidence (lead, 2026-10-08)

- J12 saw `grim` answer `no wl_output` in 2 of 6 nested runs on its tree; both reruns passed and it found no cause. Same wedge as J09's.
- `test_motion.sh` failed once in six runs under heavy.sh on J10 round 3's tree (2026-10-08, first in a heavy batch; the failing check was lost to a truncated log), then passed five in a row. Its bounds are 260 ms per role and 300 ms per surface; synchronous Config and Persistent writes (`blockWrites`, 33 ms median) now stall the UI thread, so a probe step that writes a setting right before a timed animation can push it over.
