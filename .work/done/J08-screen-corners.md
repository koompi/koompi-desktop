# J08: screen corners cost what they do, and hot corners work without rounding

Audit: `docs/design/ux-audit-2026-10-07.md` section 5, F1. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- Lead's measurement: removing ScreenCorners frees about 44 MB in the headless shell.
- `modules/koompi/screenCorners/ScreenCorners.qml:139-171`: four `CornerPanelWindow`s per screen, always.
- `:26`: each window's `visible` is the fake-rounding setting (`appearance.fakeScreenRounding` 1, or 2 when not fullscreen). The hot-corner region that opens a sidebar (`sidebarCornerOpenInteractionLoader`, `:62-130`) lives inside those windows. On the live seat `fakeScreenRounding` is 0, and `hyprctl layers` lists no `quickshell:screenCorners` layer at all: the documented top-corner sidebar triggers (`docs/navigation.md`, Edges) are dead there.
- `docs/navigation.md`, Edges: only the corner pair matching `sidebar.cornerOpen.bottom` should be live.

## Do

1. A corner window exists only when it has a job: drawing the fake rounding (per the setting), or hosting a hot-corner region (`sidebar.cornerOpen.enable`, and only the top or bottom pair per `cornerOpen.bottom`). No job, no window.
2. Hot corners work with `fakeScreenRounding` 0.
3. A window that only hosts a hot-corner region is the size of that region, with the region as its input mask.
4. Measure before/after with `/home/userx/workspace/koompi/koompi-desktop/.work/tools/measure_surfaces.sh <worktree shell> /tmp/j08.tsv ScreenCorners` and a full run's `full` line; report both.
5. **Test.** Headless probe or harness: with `fakeScreenRounding` 0 and `cornerOpen.enable` true, the top-left and top-right corner layers exist and opening works (move the pointer into the corner region in the nested Hyprland harness: `hypr:hl.dsp.cursor.move(...)` or `hyprctl dispatch` equivalent; find the dispatcher name with the probe in the gotchas note), and no bottom corner layer exists. With both off, no corner layer exists.

## Acceptance

- The test fails on `dev`, passes on your branch.
- Screenshots: rounding on, rounding off with corners on (hover the top-right corner, right sidebar opens).
- Memory before/after. Full suite: no new failures.

## Out of scope

- Any other surface.
