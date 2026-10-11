# J19: the overview becomes Mission Control

## Founder decision, 2026-10-10: KOOMPI is a tiling desktop (overrides the spec below where they differ)

- The overview is a **grid of workspaces, each drawn with its tiles in place**, not windows spread out Mac-style. The layout a user built is what they see.
- From the overview: click a workspace to go there, drag a window onto another workspace to move it, and type to search (J23). Keyboard first: arrows move between workspaces, Enter goes, Super+Shift+N moves the focused window.
- Workspaces follow J18's fixed numbers; empty ones show as one "next free" slot.

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.4 (O1-O3) and section 5 (F6). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on:
- J07 merged; the overview's root becomes a lazy surface, so read the merged `modules/koompi/overview/Overview.qml` and `OverviewPanel.qml` first.
- J18 merged; the workspace strip uses `modules/common/functions/workspace-slots.js` unchanged.
- J10 owns the animation section of `general.lua`. Touch only the gesture block named below.

Files owned:
- `dots/.config/quickshell/koompi/modules/koompi/overview/OverviewPanel.qml`, `OverviewWidget.qml`, `OverviewWindow.qml`, and any new file under `modules/koompi/overview/` whose name starts with `Overview`. `Search*.qml` in the same folder belong to J23; do not touch them.
- `Overview.qml`: only the overview half (the `workspacesToggle` route); the search IPC routes stay as they are.
- `dots/.config/quickshell/koompi/modules/common/Config.qml`: only the `overview` block (`:582-590`)
- `dots/.config/hypr/hyprland/general.lua`: only the 4-finger up/down gestures (`:24-37`)
- `plugins/koompi-swipe-progress/*`, only if step 6 needs it
- `docs/manual/03-desks.md` (the `Super+Tab` paragraphs at `:30-39`), the overview step in `modules/koompi/tour/steps.js` (`:40-46`), the overview rows of `docs/navigation.md`
- new tests

## Evidence (verified on `dev` at `9de7a575a`)

- `OverviewWidget.qml:21-22,92-105` draws a fixed grid of `overview.rows x overview.columns` (2x5, `Config.qml:582-590`) at `overview.scale: 0.18`. Each window is a 0.18-scale tile (`:175-243`); on the live seat seven of ten tiles were empty numbers (audit O1).
- `OverviewWindow.qml:93-97`: every tile is a `ScreencopyView` with `live: true` while the overview is open, at any size (audit O2).
- Drag to another workspace already works (`OverviewWidget.qml:150-160` DropArea, `:260-275` move via the Lua form `hl.dsp.window.move`). Keep that path.
- `general.lua:24-37`: 4-finger up and down fire `quickshell:overviewWorkspacesToggle` when the swipe ends; nothing follows the fingers (audit O3).
- `plugins/koompi-swipe-progress/main.cpp:36-79` publishes only the horizontal workspace swipe (`koompiswipebegin`, `koompiswipe`, `koompiswipeend`). Its consumer is `modules/koompi/background/Background.qml:158-170`, via raw Hyprland events. The plugin's test hook is the `koompiswipesim` dispatcher (`:116-121`).
- Hyprland 0.56.2 has a Lua gesture with separate start, update and end callbacks: `/usr/include/hyprland/src/managers/input/trackpad/gestures/LuaFunctionGesture.hpp:7-19` (`CLuaFunctionGesture(int startRef, int updateRef, int endRef)`, `m_legacyEndOnly`). The stub types `action` only as `string|function` (`/usr/share/hypr/stubs/hl.meta.lua:460-470`). `hl.dsp.event` exists in the dispatcher namespace (`hl.meta.lua:870-891`).

## Do

1. **Layout, as a pure JS file** (kebab-case, bun-testable). The windows of the current workspace on the focused monitor are laid out as large as possible without overlap:
   - preserve each window's aspect ratio;
   - keep the left-to-right reading order close to the windows' real positions;
   - stay inside the area under the strip, with a gap.
   One window fills most of the area; twelve still read.
2. **The overview surface.**
   - **Strip.** Along the top runs a strip of desk tiles from `workspace-slots.js`: occupied desks plus the empty "new desk" slot, drawn as `+`.
   - **Mouse.** Clicking a desk tile goes to that desk and closes the overview; `+` goes to the empty slot's id. Dragging a window tile onto a desk tile moves it there with the existing Lua-form move, without following. Clicking a window tile focuses it and closes.
   - **Titles.** A tile shows its title on hover and on keyboard selection.
   - **Keys.** Arrows move the selection, `Enter` focuses, `Escape` closes, and `Super+Tab` closes as today.
3. **Typing filters.** Any printable key starts a filter: the main area shows windows from every desk whose title or app name matches, using the `Fuzzy` the shell already uses for Search's window scope, each labelled with its desk number. `Enter` focuses the first match and `Backspace` to empty restores the desk view. Do not edit `services/LauncherSearch.qml` (J23); call `Fuzzy` directly.
4. **Live capture only where it can be read** (F6). A tile renders `live: true` only when its drawn width is at least 320 logical px; smaller tiles capture one frame on open and stop. Put the threshold in one named property.
5. **Config.**
   - `overview.rows`, `overview.columns` and `overview.scale` stop driving the layout. Remove them if nothing else reads them (grep), or leave them inert and say so.
   - Any default that existing users carry in `config.json` must not break the new layout. Check `docs/agents/migrations.md`, and add a migration only if a stored value would now do harm.
6. **Gesture by progress** (O3). 4-finger up opens the overview and 4-finger down closes it, following the fingers and reversing when they reverse; the release past the halfway point commits.
   - First find the Lua shape that gives `hl.gesture` separate start, update and end callbacks (strings in `/usr/bin/Hyprland`, then `Hyprland --verify-config` on a scratch config), and what the update callback receives.
   - Publish progress without a process per update: `hl.dispatch(hl.dsp.event("koompioverview>>" .. value))`, or whatever `hl.dsp.event` accepts. The overview reads it the way `Background.qml:158-170` reads `koompiswipe`.
   - Only if Lua cannot carry the delta, extend `plugins/koompi-swipe-progress` and its `rebuild` path; `tests/test_swipe_plugin_rebuild.sh` must still pass.
   - Reduce Motion (J10's `appearance.reduceMotion`) makes the gesture a fade.
   - If neither path works, stop after step 5 and report the evidence; the lead files the gesture as its own job. Steps 1-5 ship either way.
7. **Docs:**
   - `docs/manual/03-desks.md:30-39`;
   - the tour's overview step (`steps.js:40-46`), whose body still says "laid out small";
   - in `docs/navigation.md`, the overview rows and the Gestures table.

## Tests that fail first

- **bun.** The layout function for 1 to 12 windows of mixed aspect ratios. Assert:
  - no overlap, everything inside the area;
  - aspects kept within 1%;
  - one window takes at least 60% of the area width or height.
- **Nested Hyprland** (shape of `tests/test_search_window_focus.sh`). Three windows on desk 1 and one on desk 3. Open the overview by its global and read the item tree (give the tiles `objectName`s). Assert:
  - three window tiles that do not overlap;
  - the strip shows 1, 3 and `+`;
  - typing the second window's class leaves one tile, and Enter focuses it (`hyprctl activewindow -j`);
  - tiles under 320 px are not `live`.
  On `dev` the grid shows ten workspace cells.
- **Gesture.** If step 6 lands, a test that feeds synthetic progress events (or the plugin simulator) and asserts the overview's openness follows them and settles on release.

## Acceptance

- hyprshot renders: overview with 1, 4 and 9 windows, a filter in progress, and the strip with three desks, at 1920x1200 and 1366x768, dark and light. Look at each in full; no tile overlaps, titles readable, the strip clear of the bar.
- Keyboard only: open, move, filter, focus, close.
- A before/after note on the PSS of an open overview with 9 windows (`measure_surfaces.sh` style or `ps`/`smem` of the nested `qs`), showing the live-capture rule's effect.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- The bar's workspace widget (J18), the app switcher (J17), Search (J23), renaming desks.
