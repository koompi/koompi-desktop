# J08 report (hand-back message; the harness refused the worker's file)

J08 report: corner windows exist only for a job, and hot corners work with the rounding off.

Branch `worktree-agent-ac218decd99722df9`, base `3f560be3b` (confirmed). Worktree clean.
I wrote no `.work/J08-report.md`, because my harness forbids report .md files, so this message is the report. Evidence is in `/home/userx/.tmp/J08-handoff/` (`shots/`, `tests/`, `memory/`, `diag/`, `tools/`). Scratch is `/tmp/j08.U15d0x`; delete it when done.

**Commits** (no trailers)
- `916a76252` ScreenCorners: a corner window exists only for a job, and the hot corners work with the rounding off
- `e6ecc7887` ScreenCorners: a hot corner fires once per visit

**What changed**
- `ScreenCorners.qml`, 174 to 180 lines:
  - Each corner is a LazyLoader (`:163`), active only while it draws the rounding (`:157`) or hosts the hot corner (`:158`).
  - A window that only hosts a hot corner is its region in size and mask (`:30-32`, `:53-54`, `:35`).
  - Sizes come from config, not from the Loader. A Loader keeps the implicit size of the item it unloaded, so dev's windows stay 250 px wide after `cornerOpen` is turned off or moved.
  - Dropped the unused `activeWindow` and `brightnessMonitor` members and imports.
  - `armed` (`:82`): a corner fires once per visit.
- `docs/navigation.md`, Edges section only.
- New `tests/test_screen_corners.sh` (303 lines) and `tests/wl_virtual_pointer.py` (129 lines).
- `ScreenCorners.qml` is inherited from end-4. One nesting level is gone, so every handler line is re-indented and the next upstream port of this file is manual.

**The pointer finding**
- The nested Hyprland under headless KWin has no pointer: `hyprctl devices` shows `mice: []`.
- `hl.dsp.cursor.move` changes `hyprctl cursorpos` and sends clients nothing. Six warp variants produced zero events.
- `wl_virtual_pointer.py` gives it a pointer over `zwlr_virtual_pointer_v1`. It is stdlib only and refuses the real `/run/user/<uid>`. The first try worked.
- This belongs in the gotchas note.

**Test, run in the nested Hyprland**
- On dev: 10 FAIL, 5 ok of 15. Examples:
  - `rounding off, corners on: corner windows are [], want two 250x5`
  - both top triggers read `right=0/0` and `left=0/0`
  - stale 250 px windows after `cornerOpen` changes
- On the branch: 15 ok, 0 FAIL, twice in a row.
- Without `armed` (`e6ecc7887` reverted): exactly 1 FAIL, `a second move inside the trigger zone toggled the sidebar again ... 'right=0/2'`. A real flick crossing the 2 px zone in two moves would do that.
- Pointer positions read exactly `1279, 3`, `0, 3`, `1279, 797`, `0, 797`.

**Memory** (PSS in KiB, headless shell, 2 runs each; the same tree varies by up to 7.7k)

| config | dev | branch |
|---|---|---|
| `measure_surfaces.sh ... ScreenCorners` (real tool, 1 run) | 381957 | 380894 |
| default (rounding 2, top corners) | 409324, 416957 | 412083, 420433 |
| rounding 0, corners top (the seat) | 391237, 391684 | 400484, 407123 |
| both off (1 run) | 385051 | 379769 |

- The `full` lines came from a copy of the tool that accepts a config; the `full` variant itself is unchanged.
- There is no saving on the default config, since all four windows have jobs.
- The seat's two now-live windows cost about 12 MB.
- A no-job config gets about 5 MB back.
- The 44 MB figure does not appear anywhere in the default config.

**Screenshots I looked at**
- `shots/off-topright.png`: rounding off, pointer moved to `1919, 3`, right sidebar open (420x1160, `quickshell:sidebarRight` mapped). This is the acceptance shot, taken on `916a76252`'s tree.
- `shots/final-right-sidebar-rounding-on.png` and `final-left-sidebar-rounding-on.png`: final tree, rounding on. Right sidebar opens from the top-right corner; the left assistant panel opens from the top-left.
- `off-start.png` against `on.png`, plus crops `bl-off-vs-on.png` and `tr-off-vs-on.png`: square screen corners with the rounding off, black quarter-circle cutouts with it on.
- `viz.png` and `viz-top.png`: 250x5 strips on the bar's top edge at both top corners, nothing at the bottom. `bottomright.png` (bottom corners selected): strips at the bottom corners, none at the top.
- Two outputs (`two-outputs-*.png`, `seam.png`): each screen has its own windows. Pixel samples: all 8 corner pixels are `(0,0,0)` with rounding on and none with it off; strips appear only at the selected edge on both screens.
- `off-topleft.png` is not a pass. It shows the right sidebar still open and no left sidebar (see not done).

**Full suite on the final tree** (before two trivial test edits):
- `126 passed, 4 skipped, 0 failed`
- skipped: `test_bar_keys`, `test_globalmenu`, `test_hypridle_logged`, `test_search_bench_parity`
- The edits were one reworded comment and `python3` added to the test's tool-check list. They were not re-run; `bash -n` and `shellcheck` are clean.

**Not done, with reasons**
- No screenshot of the left corner opening with rounding off. In the first full-shell run the right sidebar had stayed open from the earlier step, and the left never mapped. The left corner with rounding off is covered by the test (`left=1/1`), and the left opens with rounding on.
- The dev arm of the re-open observation below was lost to the nested start-up wedge (`grim: no wl_output`); my retry check was wrong for that case.

**For you to decide**
- Re-open: a sidebar closed over IPC while the pointer rests in its corner is back one 150 ms sample later and stays open. This is seen with and without `armed`, on both corners. With the pointer elsewhere it closes and stays closed. The cause is not traced and dev is unchecked.
  - Options: (a) leave it; (b) a short holdoff after a sidebar closes; (c) trace the focus-grab cycle first.
- Seat cost: the two live windows cost about 12 MB. One strip window per screen with a two-rectangle input mask would save one window per screen, but it contradicts "the window is the size of its region".
- On deploy the seat gets live corners for the first time. The top 5 px of the bar's two ends take clicks, and the wheel there changes volume or brightness (`valueScroll` is on by default).
- Because of the start-up wedge, `hyprshot.sh` runs may print `no images`; I handled it with retries only in my scratch scripts.
