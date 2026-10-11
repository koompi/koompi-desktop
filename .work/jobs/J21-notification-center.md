# J21: the right panel becomes the Notification Center

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.5 (R2, R3, R5) and decision D4 (section 7). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on:
- J07 merged. `SidebarRight.qml` becomes a lazy surface, so read the merged file first.
- J20 merged first: the controls this panel gives up must already live in the Control Center, and `quickshell:controlCenterToggle` must exist. You may build in parallel with J20, but rebase on it before handing back.
- **Before dispatch, the lead confirms one fact** (read-only, on the live seat, never by the worker): the `appName` of the kernel "Memory Shortage Avoided" toasts, read from the notification store at `Directories.notificationsPath`. Lead, 2026-10-07: `appName = Linux Kernel`. The toast is KDE's kded module `oom_notifier` (plasma-workspace 6.7.5, `/usr/lib/qt6/plugins/kf6/kded/oom_notifier.so`). KNotification sends its notifyrc's `[Global] Name` as the app name: `/usr/share/knotifications6/oom_notifier.notifyrc:6` `Name=Linux Kernel`, translated by `Name[xx]` in other locales. Its `x-kde-appname` hint is `oom_notifier` in every locale: match on that if Quickshell exposes the hint, else on the name. Not seen live: the store held only ten KOOMPI toasts when read, so the test sends a fixture with both.

Files owned:
- `dots/.config/quickshell/koompi/modules/koompi/sidebarRight/SidebarRight.qml`, `SidebarRightContent.qml` (allow-listed at 522 lines; it must shrink, never grow), `SidebarDrawer.qml`, and `notifications/`, `calendar/`, `todo/`, `pomodoro/`
- new files under `sidebarRight/` for the widgets
- `dots/.config/quickshell/koompi/modules/common/widgets/NotificationGroup.qml`: a per-group clear behind a property that defaults off, because the popups use it too
- `dots/.config/quickshell/koompi/services/Notifications.qml`: the System grouping
- `dots/.config/quickshell/koompi/services/Weather.qml`: the fetch filter and two fields
- `dots/.config/hypr/hyprland/keybinds.lua`: only lines 65-67 (the comment above `SUPER + ALT + N` and the bind itself)
- `tests/test_sidebar_drawer_binds.sh`
- the right-panel step of `modules/koompi/tour/steps.js` (`:54-60`)
- the right-panel rows of `docs/navigation.md`
- new tests

Do not edit the controls components under `sidebarRight/` (`quickToggles/`, `QuickSliders.qml`, `wifiNetworks/`, `bluetoothDevices/`, `nightLight/`, `volumeMixer/`, `ChargeLimitRow.qml`): J20 imports them. Stop using them here, and leave the files in place.

**Shared contract (from J20):** `GlobalStates.controlCenterOpen`, GlobalShortcut `controlCenterToggle`, IPC target `controlCenter`. J20's `GlobalStates.qml` closes whichever side panel is not being opened. This panel keeps its names: `GlobalStates.sidebarRightOpen`, IPC target `sidebarRight`, namespace `quickshell:sidebarRight`, `Super+N`, the top-right hot corner. J22 makes the clock open it.

## Evidence (verified on `dev` at `9de7a575a`)

- `SidebarRightContent.qml` today:
  - `:85-120`: quick sliders, toggles and the "All controls" row (`:113-114`) come first;
  - `:134-200`: the Today heading, the weather card (`:139-150`), today's calendar events (`:156-180`) and the notification list (`:200`);
  - `:207-225`: the Personal rows into the Calendar, To Do and Timer drawer pages;
  - `:229-250`: the drawer, with the controls page at `:256-282`;
  - `:476`: J02's header shows `DateTime.fullDate`.
- `SidebarRight.qml:137-186`: shortcuts `sidebarRightToggle`, `Open`, `Close`, `Controls`, `Calendar`, `Todo` and `Timer`. `keybinds.lua:64-70` binds them; `:67` is `SUPER + ALT + N` to `quickshell:sidebarRightControls`.
- `tests/test_sidebar_drawer_binds.sh:22-46` asserts exactly four drawer pages and four bound shortcuts, Controls included.
- Grouping and clearing:
  - `services/Notifications.qml:147-175` already groups by `appName`.
  - `modules/common/widgets/NotificationGroup.qml` can expand (`:19`, `:76-78`) but has no per-group clear.
  - `notifications/NotificationList.qml:61-67` clears everything at once.
- Plain words:
  - Kernel notices reach the user as "Memory Shortage Avoided" six times over (audit R3).
  - `dots/.local/bin/koompi-crash-watch` sends its plain-worded toast as `-a KOOMPI` since J03.
- Weather:
  - `services/Weather.qml:98` keeps only `current`, `location` and `astronomy` from wttr, so there is no high or low.
  - `:59` reads the place; `wCode` is the condition.
  - The panel's card shows `28°C` and nothing else (audit R5).
- `modules/koompi/tour/steps.js:54-60` still says "The second tab holds your calendar, to-do list and timer"; the tabs are gone.

## Do

1. **Order, top to bottom:**
   - the header (date, pin, settings, power: J02's, unchanged);
   - notifications grouped by app, each group with its own clear, then "Clear all";
   - a **System** group;
   - widgets: **Up next** (the next three calendar events across today and tomorrow); **Weather** (place, condition in words, now, and today's high and low); **To-do** (the first three unfinished items; the row opens the To Do page); **Timer** (the running timer, or "Start a timer", which opens the Timer page).
   - The Calendar, To Do and Timer drawer pages stay, and so do `Super+Alt+C`, `D` and `T`.
2. **Remove** from this panel: the quick sliders, the toggles, the "All controls" row, the controls drawer page and the `sidebarRightControls` GlobalShortcut.
3. **Rewire** `keybinds.lua:67`: `SUPER + ALT + N` goes to `hl.dsp.global("quickshell:controlCenterToggle")` with the description `"Shell: Control Center"`. Rewrite the comment at `:65-66` so it still holds for `C`, `D` and `T` but no longer claims `N` opens a page of this panel. Update `tests/test_sidebar_drawer_binds.sh` to three pages and three shortcuts, and add a check that `SUPER + ALT + N` names `controlCenterToggle`.
4. **The System group.**
   - Members: notifications whose `appName` is in `notifications.systemApps`. Defaults: `KOOMPI`, plus the kernel notice's sender confirmed above. Add the key to the top-level `notifications` block (`Config.qml:555`); that one key is yours.
   - It is collapsed by default and reads in plain words.
   - Identical summaries within it collapse into one row with a count ("Memory shortage avoided ×6"). The newest body is shown, and clearing the row clears all of them.
   - It never pops a toast louder than normal urgency.
5. **Per-group clear.** `NotificationGroup.qml` gets a property, default false, that shows a clear button on the group's title row. Only this panel turns it on.
6. **Weather.** Extend the filter at `Weather.qml:98` with today's `maxtempC`/`mintempC` (or F with `useUSCS`) and the condition text. Draw the new widget in `sidebarRight/` rather than editing `modules/koompi/bar/weather/` (J22's).
7. **Docs.**
   - In `docs/navigation.md`, the Roles row for Today becomes the Notification Center (the panel is still `SidebarRight.qml`), the Entry points row is renamed, and the paragraph describing the panel is rewritten.
   - Rewrite the tour step `steps.js:54-60` for the new panel.
   - Manual pages are J22's.

## Tests that fail first

- **Headless probe** (shape of `tests/test_notification_read_state.sh`, `tests/private-bus.conf`, its own runtime dir). Send notifications through the private bus with `notify-send`:
  - two apps × two notifications each;
  - six identical KOOMPI-sender notices, using the confirmed kernel `appName` if it differs.
  Open the panel and read the item tree. Assert:
  - two app groups, each with a clear button, and clearing one removes only that group;
  - one collapsed System group whose collapsed row shows ×6;
  - no quick toggles in the panel;
  - the widget order as in step 1.
- **Weather:** a fixture of wttr's `format=j1` JSON fed through the filter gives high and low. Use a shimmed `curl` in PATH, as other tests shim network tools; no network.
- `tests/test_sidebar_drawer_binds.sh` in its updated form passes, and fails on `dev`'s keybinds.

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light, looked at in full:
  - an empty panel;
  - a busy panel (three app groups and the System group);
  - each drawer page.
  Nothing clipped, no text under 12 px, the System row in plain words.
- Keyboard only: `Super+N` opens, Tab through groups, Enter expands, Delete clears the focused group (add it if missing), Escape closes.
- The J02 read rule still holds: `tests/test_notification_read_state.sh` passes.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- The Control Center (J20), the clock and bar wiring and the manual pages (J22), notification toasts' own layout.
