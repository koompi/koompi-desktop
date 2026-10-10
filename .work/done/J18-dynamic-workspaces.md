# J18: desks appear when used, like Spaces

## Founder decision, 2026-10-10: KOOMPI is a tiling desktop (overrides the spec below and audit decision D2 `dynamic_like_macos`)

- Workspace numbers stay **fixed**: Super+1...9 always go to the same workspace. There is no renumbering, and no workspace is created or destroyed behind the user's back.
- What changes is the bar: empty workspaces are hidden from the indicator (with the active one always shown), and one "next free" slot shows where Super+N would open a fresh one. A setting brings back the full row of ten.
- `workspace-slots.js` still exports the slot function for J19, now over fixed ids.
- Rename the job in reports to "the bar shows the workspaces in use"; the manual's desks chapter explains fixed numbers.

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.1 (B2) and decision D2 (section 7: `dynamic_like_macos`). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on: J07 merged. J19 builds its workspace strip on this job's slot function, so J18 merges first.

Files owned:
- `dots/.config/quickshell/koompi/modules/koompi/bar/Workspaces.qml` (used by both bars: `modules/koompi/verticalBar/VerticalBarContent.qml:110`)
- new `dots/.config/quickshell/koompi/modules/common/functions/workspace-slots.js`
- `dots/.config/quickshell/koompi/modules/common/Config.qml`: one new key in `bar.workspaces` only
- `dots/.config/quickshell/koompi/modules/settings/BarConfig.qml`: only the "Workspaces shown" control at `:213-219` and a switch beside it
- `docs/manual/03-desks.md` and the workspace rows of `docs/navigation.md`
- new tests

Shared contract: `workspace-slots.js` exports `slots(occupiedIds, activeId, groupSize)`, which returns the ordered ids to draw plus which one is the empty "new desk" slot. J19's overview strip imports it unchanged.

## Evidence (verified on `dev` at `9de7a575a`)

- `modules/common/Config.qml:413-415`: `bar.workspaces.shown: 10`.
- `modules/koompi/bar/Workspaces.qml:24-25`: the widget draws `shown` slots for the group around the active workspace. `:68` marks which are occupied, and `:124-125` and `:202-207` repeat over all ten. The live seat drew seven empty dots out of ten (audit B2).
- `dots/.config/hypr/hyprland/lib/init.lua:22-27`: `workspace_in_group(i)` maps `Super+N` into the current group of `workspaceGroupSize`. `keybinds.lua:326-330` binds `Super+1..0` through it, and `:276-293` sends windows the same way. Hyprland creates a workspace on first use, so desks are already dynamic in the compositor; only the shell draws ten fixed ones.
- `modules/koompi/overview/OverviewWidget.qml:21-22,92-105` draws a fixed `rows x columns` grid of the same ten; J19 replaces it.
- `modules/koompi/bar/WorkspaceHelp.qml` hangs under the widget on first run (`tests/test_workspace_help_onscreen.sh`). Per-workspace wallpapers key on workspace ids (`Config.qml:330-336`, `tests/test_workspace_wallpaper_wrap.sh`), so ids must not be renumbered.

## Do

1. **Slot rule** in `workspace-slots.js`, as pure functions:
   - The slots are the occupied ids of the current group, plus the active id if it is empty, in ascending order.
   - Then one empty slot: the lowest unused id in the group, if the group has room.
   - Ids are never renumbered: occupied {1, 2, 5} draws 1, 2, 5 and an empty 3. `Super+5` still means desk 5.
2. **Bar.**
   - `Workspaces.qml` draws exactly those slots. The empty slot reads as "new desk" (a quieter dot, tooltip "New desk"), and clicking it focuses that id with the Lua form.
   - Numbers, app icons, the Super-held number reveal, scrolling and the right-click to Overview behave as today on the remaining slots.
   - The widget's width follows the slot count, animated with the `Appearance.animation` roles (J10 retunes them, so use roles, never raw durations). Nothing beside it jumps beyond that.
3. **Config.** Add `bar.workspaces.dynamic: true`. With it false, today's fixed `shown` behaviour returns unchanged. Settings (`BarConfig.qml:213-219`, "Workspaces shown") gains the switch beside it, and "Workspaces shown" applies only when the switch is off.
4. **Keys and gestures** stay as they are:
   - `Super+1..0` focuses, creating an empty desk if needed, and the bar then shows it.
   - The 4-finger horizontal swipe walks numeric neighbours (`general.lua:56-76`), so it can create the next empty desk, and the bar shows it.
   - Say in the report what you observed for each.
5. **Docs:** `docs/manual/03-desks.md`, and in `docs/navigation.md` the Workspace keyboard section and the entry-point row for the workspace hint.

## Tests that fail first

- **bun:** `slots()` for empty {}, {1}, {1,2,5} with active 5, active empty 7, a full group, and a group other than the first (ids 11-20).
- **Nested Hyprland** (shape of `tests/test_search_window_focus.sh`). Open windows on workspaces 1, 2 and 5 with the Lua form `hl.dsp.window.move`. Read the bar's slots from the probe or item tree (give the slot delegates an `objectName`). Assert:
  - four slots drawn: 1, 2, 5 and the empty 3;
  - focusing workspace 8 adds 8;
  - closing 5's window removes 5 after the focus leaves it.
  On `dev` the bar draws ten.
- `tests/test_workspace_help_onscreen.sh` and `tests/test_workspace_wallpaper_wrap.sh` still pass.

## Acceptance

- Renders of the bar with 1, 3 and 9 occupied desks at 1920x1200 and 1366x768, dark and light, plus the vertical bar once. Look at each in full; the slots are centred and nothing beside them jumps.
- Keyboard only: `Super+N` and `Super+Alt+N` round trips, as described in step 4.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- The overview's grid (J19), renaming desks, per-monitor workspace sets.
