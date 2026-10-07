# J22: the bar's right end in a fixed order, readable on any wallpaper, wired to the two panels

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.1 (B3, B4 and the proposal under the table) and section 3.5 ("Uptime moves to About"). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on:
- J07 merged.
- J20 and J21 merged. The glyph and the clock open their surfaces, and the manual pages describe both.
- J13 merged. J13 owns `modules/koompi/bar/ActiveWindow.qml` for launch feedback, and this job then changes only that file's text colours.

Files owned:
- `dots/.config/quickshell/koompi/modules/koompi/bar/BarContent.qml` (right section, `:144-378`), `ModeIndicators.qml`, `BatteryIndicator.qml`, `NotificationUnreadCount.qml`, `ClockWidget.qml`, `ClockWidgetPopup.qml`, `UpdateBadge.qml` (placement only)
- the text colours in `ActiveWindow.qml`
- `dots/.config/quickshell/koompi/modules/koompi/verticalBar/VerticalBarContent.qml` (its indicator button `:200-222`, clock and battery)
- `dots/.config/quickshell/koompi/modules/common/Appearance.qml`: only `colBarBackground` and the bar text colours, if the contrast step needs them
- `dots/.config/quickshell/koompi/modules/settings/About.qml`: one uptime row
- `docs/manual/05-the-strip-along-the-top.md`, `docs/manual/07-getting-online.md` (`:5` says "Press `Super+N`" for Wi-Fi), and the bar rows of `docs/navigation.md`
- new tests

**Shared contract (from J20 and J21):** the Control Center glyph toggles `GlobalStates.controlCenterOpen`, and the clock toggles `GlobalStates.sidebarRightOpen`, the Notification Center. J20's `GlobalStates.qml` closes the other one.

## Evidence (verified on `dev` at `9de7a575a`)

- `BarContent.qml:173-378`: a right-to-left row (`:177`) holding:
  - the clock (`:179-184`, `PluginSlot` `koompi.clock`) and Pomodoro (`:186-199`);
  - the panel button (`:201-227`), which toggles `sidebarRightOpen` (`:218`, `:225-226`) and wraps the indicator row (`:229-327`): screen recording, `ModeIndicators`, volume muted, mic muted, `HyprlandXkbIndicator`, `NotificationUnreadCount`, the Wi-Fi glyph;
  - then `UpdateBadge` (`:329`, J01), `BatteryIndicator` (`:331-334`), agent usage (`:336-343`), media (`:345-360`), `SysTray` (`:362`), and a spacer (`:374`).
  The live cluster read `67`, a moon, `384`, `us`, Wi-Fi and the time, with no volume or Bluetooth state (audit B4).
- `BatteryIndicator.qml:21-24`: the battery is a number inside a progress pill, not a glyph with a percent.
- `ModeIndicators.qml:79-97` already shows keep awake, night light and dictation only while each is active.
- `ClockWidget.qml:40-46`: hovering the clock shows `ClockWidgetPopup`, which includes uptime (`ClockWidgetPopup.qml:12`); clicking the clock does nothing. `modules/settings/About.qml` shows no uptime.
- Contrast:
  - `Appearance.qml:125-127`: `colBarBackground` is 75% opaque in dark mode and 85% in light.
  - `ActiveWindow.qml:150,159`: on a monitor that is not focused, the identity draws in `colOnLayer1Inactive`.
  - On the live HDMI monitor that was grey text on a bright wallpaper, close to unreadable (audit B3).
- `verticalBar/VerticalBarContent.qml:200-222` has its own panel button with the same indicators.

## Do

1. **Order, left to right**, with every hit area separate:
   - tray extras: `SysTray`, plus media, agent usage and a running Pomodoro, each still conditional;
   - mode indicators, each only while active: screen recording, microphone in use (`Privacy.micActive`), mic muted, volume muted, keep awake, night light, Do Not Disturb (moon), dictation;
   - the update glyph (J01's, unchanged, its own hit area);
   - input source;
   - Wi-Fi;
   - battery as a glyph with its percent beside it, on battery hardware only;
   - **one Control Center glyph**, toggling `GlobalStates.controlCenterOpen` and drawn toggled while it is open;
   - the **clock**.
2. **The clock** opens and closes the Notification Center on click and is drawn toggled while it is open.
   - The hover popup (bar popup 4, `Super+Ctrl+4`) stays, minus uptime.
   - Unread notifications show as a small dot on the clock, with no count. Do Not Disturb is the moon indicator.
3. **The panel button goes away.** Nothing else in the bar opens a panel. Keep scroll-to-change-volume and brightness on the bar sections; they are wheel behaviours (see `docs/navigation.md`, Entry points).
4. **Uptime moves to About:** one row, "Up for 3 h 12 min", from `DateTime.uptime`.
5. **Contrast.**
   - Every text and glyph colour drawn on the bar must reach 4.5:1 against the bar composited over the worst wallpaper pixel: white under the dark bar, black under the light one. That covers focused and unfocused monitors, in both modes.
   - Measure it, then raise `colBarBackground`'s opacity and/or retune the bar's inactive text colour until it does. Report the before and after ratios for every colour.
   - `bar.showBackground: false` is the user's explicit choice and is exempt; say so in the report.
6. **Vertical bar.** The same wiring: a Control Center glyph, the clock opening the Notification Center, the battery glyph, and no panel button.
7. **Docs.**
   - `docs/manual/05-the-strip-along-the-top.md` describes the new order.
   - `docs/manual/07-getting-online.md:5` sends people to the Control Center glyph or `Super+Alt+N`.
   - In `docs/navigation.md`, the Entry points rows for the two panels and the bar popups row, and the paragraph about one bar button per sidebar. `tests/test_manual_references.sh` must pass.

## Tests that fail first

- **Contrast, computed.** A headless probe loads `Appearance` in dark and in light and composites `colBarBackground` over white and over black. It computes the WCAG ratio for each bar text colour (`colOnLayer0`, `colSubtext`, `colOnLayer1Inactive`, the indicator glyph colour) and fails under 4.5. It fails on `dev`; say which colours did.
- **Bar wiring** (extend `tests/test_bar_keys.sh` or a new test, headless KWin, `tests/private-bus.conf`). Click the clock (a QML `click()`, as J01's test does) and assert `sidebarRightOpen`. Click the Control Center glyph and assert `controlCenterOpen` and not `sidebarRightOpen`. Read the indicator order from the item tree. Assert the battery shows a percent text.
- `tests/test_popup_clamp.sh` and `tests/test_bar_keys.sh` still pass.

## Acceptance

- Renders of the bar on a bright and on a dark wallpaper, in dark and light mode, focused and unfocused, at 1920x1200 and 1366x768. Look at each in full.
- One render with every mode indicator forced on, to check that nothing overlaps. One render of the vertical bar.
- Keyboard: `Super+N`, `Super+Alt+N` and `Super+Ctrl+4` still work. The bar itself takes no new keys.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- The left section, the workspaces (J18), the update popup's content (J01), the icon plate (J33).
