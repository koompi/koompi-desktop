# J20: a Control Center, opened from its own bar glyph

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.5 (R2) and decision D4 (section 7: `split_control_center_and_notifications`); section 4 item 4 (on and off never by colour alone). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on: J07 merged (the window lives in J07's lazy-surface component). J21 and J22 merge after this job; they rely on the contract below.

Files owned:
- new `dots/.config/quickshell/koompi/modules/koompi/controlCenter/` (root, window, modules, detail pages; every file under 400 lines)
- `dots/.config/quickshell/koompi/GlobalStates.qml`: the `controlCenterOpen` flag and the two mutual-close handlers below
- `dots/.config/quickshell/koompi/panelFamilies/KoompiFamily.qml`: one import and one loader entry
- `dots/.config/quickshell/koompi/modules/common/Config.qml`: one new `controlCenter` block
- the migration for it, if step 5 needs one (`docs/agents/migrations.md`)
- new tests

Read-only for this job: everything under `modules/koompi/sidebarRight/`. Import its components (`QuickSliders.qml`, `ChargeLimitRow.qml`, `wifiNetworks/WifiDialog.qml`, `bluetoothDevices/BluetoothDialog.qml`, `nightLight/NightLightDialog.qml`, `volumeMixer/VolumeDialog.qml`, the toggle files under `quickToggles/androidStyle/`) or copy what you need. Never edit or move them; J21 owns that folder.

**Shared contract (this job adds it; J21 and J22 use it):**
- `GlobalStates.controlCenterOpen: bool`.
- `GlobalShortcut` `controlCenterToggle`, declared in the Control Center's always-loaded root. J21 points `SUPER + ALT + N` at `quickshell:controlCenterToggle`.
- IPC target `controlCenter` with `toggle()`, `open()`, `close()`, `module(name: string)`. `name` is one of `wifi`, `bluetooth`, `display`, `sound`, `nowPlaying`, `battery` and opens that detail page.
- Layer namespace `quickshell:controlCenter`.
- Mutual close, written here in `GlobalStates.qml`: opening the Control Center sets `sidebarRightOpen = false`, and opening the right panel (the Notification Center, J21) sets `controlCenterOpen = false`. Keep J02's existing `onSidebarRightOpenChanged` body intact and add to it.
- J22 puts the bar glyph that toggles `controlCenterOpen`.

## Evidence (verified on `dev` at `9de7a575a`)

- `modules/koompi/sidebarRight/SidebarRightContent.qml:85-120`: the right panel opens on quick sliders and three rows of toggles, with an "All controls" row (`:113-114`) into a drawer page (`:256-282`).
  - That page holds the full grid, an edit mode explained only in a tooltip ("LMB to enable/disable, RMB to toggle size, Scroll to swap position", `:278`) and the charge limit row (`:282`).
  - The grid mixes toggles with one-shot actions: `quickToggles/androidStyle/AndroidScreenSnipToggle.qml`, `AndroidColorPickerToggle.qml`, `AndroidMusicRecognition.qml`, `AndroidScreenRecordToggle.qml`, `AndroidOnScreenKeyboardToggle.qml` (audit R2).
- `modules/common/Config.qml:685-715`: `sidebar.quickToggles.android.toggles` is the persisted grid, and a stored array replaces the default outright (`tests/test_quick_toggles_migration.sh`).
- `keybinds.lua:67`: `SUPER + ALT + N` opens that drawer today (`quickshell:sidebarRightControls`).
- The services every module needs already exist under `services/`:
  - `Network`, `BluetoothStatus`;
  - `Notifications.silent` (do not disturb), `Idle.inhibit` and `Idle.toggleInhibit()` (keep awake);
  - `Brightness`, `Hyprsunset`, `DarkMode`;
  - `Audio`, `MprisController`, `ChargeLimit`.

## Do

1. **Surface.**
   - About 360 px wide, anchored top-right under the bar on the focused monitor.
   - Dismissable through `GlobalFocusGrab`, with keyboard focus `OnDemand` only while `controlCenterOpen`, per `docs/navigation.md` Panel contract.
   - `Escape` closes, and so does a click outside.
2. **Fixed modules, in this order:**
   - **Wi-Fi** and **Bluetooth:** a toggle each, with a chevron into the network or device list.
   - **Do Not Disturb** and **Keep awake:** toggles.
   - **Display:** a brightness slider, Night Light, Dark mode. The chevron leads to Night Light settings.
   - **Sound:** a volume slider and the output device. The chevron leads to the per-app mixer.
   - **Now Playing:** shown only while a player exists. Play/pause, next and title; a click opens media controls.
   - **Battery:** shown only on battery hardware. Charge and the charge limit.
3. **On and off without colour.** Every toggle shows its state three ways: filled glyph, accent plate and the word "On" or "Off". Never colour alone.
4. **Detail pages.** A chevron slides to the module's page, inside the same window, with a back arrow and `Escape`/`Backspace` to go back. Reuse the existing dialog contents rather than rewriting them.
5. **Added modules.**
   - An "Edit" row at the bottom opens a plain list of optional modules with checkboxes: Screen recording (as a mode indicator toggle), Game mode, Cloudflare WARP, EasyEffects, Power profile, and any other non-one-shot toggle in `quickToggles/androidStyle/`.
   - They are stored in `controlCenter.extraModules`.
   - Seed it once from the user's stored `sidebar.quickToggles.android.toggles`, keeping only the types that are still modules. Follow `docs/agents/migrations.md`, so a user who added Game mode to the old grid still sees it.
   - No hidden mouse buttons, no scroll-to-reorder.
6. **One-shot actions** (snip, colour picker, identify music, on-screen keyboard) do not appear in the Control Center. They already have keys. J23 makes each one a Search command; list them in your report so J23 can check.
7. **Reduce Motion** (J10's `appearance.reduceMotion`): the detail page slide becomes a crossfade.
8. **Docs.** In `docs/navigation.md`, move the Control Center from the "decided, not built" section into Roles, Entry points, Keyboard map and Panel contract. The bar glyph row stays marked for J22.

## Tests that fail first

- **Headless probe** (shape of `tests/test_notification_read_state.sh`: kwin_wayland on `tests/private-bus.conf`, its own runtime dir). Open the surface via IPC, then read the item tree (give the modules `objectName`s). Assert:
  - the fixed modules are present in order;
  - Battery is absent when `Battery.available` is false;
  - toggling Do Not Disturb flips `Notifications.silent` and the module's text reads "On";
  - `module("wifi")` shows the network page;
  - `Escape` from a detail page returns to the list;
  - opening the Control Center closes `sidebarRightOpen`.
- **Migration:** a stored old toggles array with `gameMode` and `screenSnip` seeds `extraModules` with Game mode only.

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light, looked at in full:
  - the main list;
  - each of the four detail pages;
  - the Edit list;
  - the Control Center beside an open window.
  Nothing is clipped, every toggle reads On or Off in words, and nothing is under 12 px.
- Keyboard only: open by IPC, Tab and arrows through modules, Space toggles, Enter opens a detail page, Escape back and out.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- Removing the controls from the right panel and rewiring `SUPER + ALT + N` (J21), the bar glyph (J22), the Search commands (J23), the shared icon plate (J33).
