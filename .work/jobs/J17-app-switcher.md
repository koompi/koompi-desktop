# J17: Alt+Tab switches apps, the way Mac and Windows hands expect

## Founder decision, 2026-10-10: KOOMPI is a tiling desktop (overrides the spec below where they differ)

- Alt+Tab cycles **windows on the current workspace first**, most recent first; windows on other workspaces come after them, marked with their workspace number. In tiling the current workspace's windows are side by side, so they are the ones a switch is usually for.
- Choosing a window on another workspace goes to that workspace; it never pulls the window across.
- The switcher never changes the tiling layout. Focus moves; tiles stay where they are.
- Super+Tab stays the overview (J19). Keep the Mac and Windows wording in the manual, but say how it maps onto workspaces.

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.3 and decision D3 (section 7: `alt_tab_switcher_keep_super_tab_overview`). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on: J07 merged (the switcher's window lives inside J07's lazy-surface component; read the merged `modules/common/LazySurface.qml` and one converted surface before writing yours). The lead merges `.work/jobs/phase2-navigation-draft.md` into `docs/navigation.md` before this job starts.

Files owned:
- new `dots/.config/quickshell/koompi/modules/koompi/appSwitcher/` (root, window, model; every file under 400 lines)
- `dots/.config/hypr/hyprland/keybinds.lua`: only a new `--##! App switcher` block of Alt binds and its submap
- `dots/.config/quickshell/koompi/GlobalStates.qml`: one line, `property bool appSwitcherOpen: false`
- `dots/.config/quickshell/koompi/panelFamilies/KoompiFamily.qml`: one import and one loader entry
- `docs/manual/01-coming-from-mac-or-windows.md`, `docs/manual/04-windows.md`, and the switcher rows of `docs/navigation.md`
- new tests

Shared files: J20 also adds one line to `GlobalStates.qml` and `KoompiFamily.qml`; J21 changes one other line of `keybinds.lua`. Add only your lines.

## Evidence (verified on `dev` at `9de7a575a`)

- No Alt+Tab bind exists in `dots/.config/hypr/hyprland/*.lua`. `keybinds.lua:44` binds `SUPER + Tab` to `quickshell:overviewWorkspacesToggle`, and that stays.
- `keybinds.lua:60` binds `SUPER + grave` to the terminal widget. The audit's `Super+grave` for cycling an app's windows collides with it, so this spec uses **`Alt+grave`**: the same modifier as the switcher, on the key macOS uses for Cmd+`. If the lead overrules, change only the chord.
- `keybinds.lua:38-43` shows how a modifier's press and release reach one `GlobalShortcut` (`ignore_mods`, `transparent`, `release = true`), and `GlobalStates.qml:55-65` consumes them. Alt release is detected the same way.
- `keybinds.lua:389-401` shows a submap (`hl.define_submap`, `hl.dsp.submap("reset")`). A submap lets `Tab`, `Q`, `Escape` and the arrows mean switcher actions only while the switcher is held open.
- Recency order exists already. `services/HyprlandData.qml:22` exposes `windowList` from koompi-shelld. `shell-services/hyprland/src/model.rs:45-46` carries `focusHistoryID` (0 is the most recent), and `shell-services/hyprland/src/event.rs:88-92` refreshes clients on every `activewindow` event.
- `/usr/share/hypr/stubs/hl.meta.lua` lists `hl.dsp.focus`, `hl.dsp.window.close` and `hl.dsp.submap`, plus the bind options `release`, `ignore_mods`, `transparent` and `submap_universal`.
- `docs/manual/01-coming-from-mac-or-windows.md:28-29` tells newcomers they never switch programs except through Search or `Super+Tab`. The dock ships off (`modules/common/Config.qml:475-476`), so the keyboard has no app switcher at all.

## Do

1. **Model.** One entry per app, built from `HyprlandData.windowList`. Group by desktop entry: `DesktopEntries.heuristicLookup(class)` id, or the class when there is no entry. Order apps by the lowest `focusHistoryID` among their windows, and windows inside an app the same way. Skip windows on special workspaces; the scratch panels have their own keys. Put the pure part (group, order, step with wrap) in a small JS file beside the surface, kebab-case per `docs/conventions.md`, so bun can test it.
2. **Behaviour.**
   - **First press.** The first `Alt+Tab` selects the previous app (index 1) and arms a 120 ms show delay.
   - **Quick tap.** Releasing Alt before the delay focuses that app's most recent window and draws nothing.
   - **Held.** Holding past the delay shows the switcher, centred on the focused monitor: app icons in recency order with the selected app's name under them.
   - **Moving.** `Tab`, `Shift+Tab`, `Left` and `Right` move the selection.
   - **Window row.** After 300 ms on one app, its windows appear as a row of titles under it, and `Down` then `Left`/`Right` picks one. Show thumbnails only if they follow J19's readable-size rule; titles alone are acceptable.
   - **Close and cancel.** `Q` closes every window of the selected app with the Lua form `hl.dsp.window.close` and the row updates. `Escape` cancels.
   - **Commit.** Releasing Alt focuses the selected app's most recent window, or the picked window, with `hl.dsp.focus({ window = "address:0x..." })`, and Hyprland switches workspace as it does for any focus.
3. **Keys.**
   - `ALT + Tab` and `ALT + SHIFT + Tab` dispatch `hl.dsp.global("quickshell:appSwitcherNext")` and `...Prev`. Give both the same description so J04's cheatsheet shows one row, e.g. `"Window: Switch apps"`.
   - The first one also enters a submap `appswitcher`. Its binds are `ALT + Tab`, `ALT + SHIFT + Tab`, `ALT + Q`, `ALT + Escape`, the `ALT` + arrow keys, and an `ALT_L`/`ALT_R` release bind (`release = true`, `ignore_mods = true`) that commits and resets the submap.
   - Every dispatch uses the Lua form. The window takes no keyboard focus (`WlrKeyboardFocus.None`), so the app being left keeps focus until the commit.
   - If a release bind does not fire inside a submap on 0.56.2, stop and report it with the log before trying another mechanism.
4. **`Alt+grave` and `Alt+Shift+grave`** cycle the focused app's windows, most recent first, with nothing drawn. Use the same release-commit pattern so holding Alt and tapping grave walks the windows.
5. **IPC.** Target `appSwitcher` with `next()`, `prev()`, `commit()`, `cancel()` and `selection(): string` (the selected app id, for tests). The `GlobalShortcut`s and the IPC handler stay in the always-loaded root, per J07's rule.
6. **Reduce Motion** (J10's `appearance.reduceMotion`): fade only, no slide or scale.
7. **Docs.**
   - `docs/manual/01-coming-from-mac-or-windows.md:28-29` and `docs/manual/04-windows.md` teach Alt+Tab, the quick tap and Alt+grave.
   - In `docs/navigation.md`, move the switcher from the "decided, not built" section into the Roles, Entry points, Keyboard map and Panel contract tables.
   - `tests/test_manual_references.sh` must still pass.

## Tests that fail first

- **Model, under bun** (shape of `tests/test_cheatsheet_binds.sh`). Feed a shelld-shaped window list with `focusHistoryID`, classes and one special-workspace window. Assert:
  - app order and per-app window order;
  - the special window is skipped;
  - next and prev wrap;
  - the quick-tap selection is index 1.
- **Nested Hyprland** (shape of `tests/test_search_window_focus.sh`, its own HOME, runtime dir and private bus). Open three windows of two apps, focused in the order A, B. Drive everything with `hyprctl dispatch 'hl.dsp.global("quickshell:appSwitcherNext")'` (the harness has no key injection). Assert:
  - next then commit within 50 ms moves focus to A, and polling `hyprctl layers -j` throughout shows no `quickshell:appSwitcher` layer;
  - next, wait 250 ms: the layer is listed;
  - Q via its global closes B's windows;
  - commit focuses the selection.
- **Static.** A stub `hl` records the Lua binds, as `tests/test_bar_keys.sh` does at its top. The Alt binds, the submap, the release bind and their descriptions exist.

## Acceptance

- hyprshot renders of the switcher held open with at least five apps, plus the 300 ms window row, at 1920x1200 and 1366x768, in dark and light (`ipc:theme toggleLightDark`). Look at every one in full; icons aligned, no clipped names.
- The quick tap is proven to draw nothing (the layer poll above).
- Every behaviour is reachable with the keyboard alone (it is a keyboard surface).
- Full suite: 0 failed (`test_update_now_runs.sh` is the known J15 flake; say if it is the only failure and that it passes alone).

## Out of scope

- The shared icon plate (J33 later swaps the icon tile for it), the dock, touchpad gestures, the overview (J19).
