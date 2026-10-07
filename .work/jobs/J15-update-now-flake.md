# J15: `test_update_now_runs.sh` fails about one run in four under load

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: `tests/test_update_now_runs.sh`; `modules/koompi/bar/UpdatesPopup.qml` only if the cause is there.

## Evidence (lead, 2026-10-07, `dev` at `e6d563717`)

- 3 failures in 11 runs, each `FAIL: Update now opened no window (hyprctl clients is empty)` after the full 60 s client wait (runs take 88 s instead of 6 s).
- In every failed run the shadow `koompi` recorded `update`, so the terminal started and ran its child; its window never reached `hyprctl clients`.
- wezterm's GUI log is the same in failed and passing runs: one portal appearance warning at start, "Broken pipe" at teardown.
- Failures came while two other workers ran nested sessions; six quiet runs in a row passed. The J01 worker saw it once inside a loaded suite run, before the private-bus change.
- Kept dirs from two failures: `/home/userx/.tmp/tmp.bz4shtS0az` with `/tmp/hr.jZwbjN`, and `/home/userx/.tmp/tmp.ayxM9W6P7M` with `/tmp/hr.BJn5Mj`. Do not delete them until the report is written.

## Do

1. Find why the window does not map: run the nested session with Hyprland's verbose log (`debug:disable_logs = false`, or the Lua equivalent from `/usr/share/hypr/stubs/hl.meta.lua`) and wezterm's (`WEZTERM_LOG=debug`), under load (run three copies at once), until a failure is captured. Name the cause from the logs, not a guess.
2. Fix the cause. If it is the harness (timing, GPU contention, the terminal choice), make the test deterministic; a longer wait is not a fix unless the logs show the window arrives late.
3. Prove it: 20 runs, three at a time, 0 failures; paste the tally.

## Acceptance

- The cause in one paragraph with the log lines behind it.
- The tally before and after.
- Full suite: 0 failed.
