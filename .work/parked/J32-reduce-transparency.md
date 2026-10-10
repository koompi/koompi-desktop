# J32: Reduce Transparency, on by itself when the battery needs it

Audit: `docs/design/ux-audit-2026-10-07.md` section 5, F7. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- the Transparency rows of `modules/settings/QuickConfig.qml` (`:240-248`) and one new switch beside J10's Reduce Motion;
- `modules/common/Config.qml` (one option under `appearance.transparency`);
- `modules/common/models/quickToggles/GameModeToggle.qml` (its `HyprlandConfig` calls only, `:12-35`);
- a new `services/VisualEffects.qml` if needed (see Do 3);
- a new test; the blur value in `dots/.config/hypr/hyprland/general.lua:113` only if the lead decides it (line-neutral).
Depends on: J10 merged. J10 adds Reduce Motion through the same `HyprlandConfig` bridge and edits `Appearance.qml` and `general.lua`.
Shared with:
- J26 edits other parts of `QuickConfig.qml` (the scheme and bar-style arrays only).
- J20 (Control Center) shows Game mode as a toggle but must not change `GameModeToggle`'s `mainAction`.

## Evidence (on `dev`)

- `dots/.config/hypr/hyprland/general.lua:107-122`: window/layer blur is on with `passes = 3`, `size = 10`, `xray = true`.
- `modules/common/Config.qml:228-233`: `appearance.transparency.enable` (default false) is the shell's own translucency, set by the "Transparency" switch (`QuickConfig.qml:240-248`). Nothing reduces Hyprland's blur.
- `services/HyprlandConfig.qml:15-50`: the bridge writes `~/.config/hypr/hyprland/shellOverrides/main.lua` with `set`/`setMany`/`reset`/`resetMany`.
- **The trap:**
  - `GameModeToggle.qml:12-35` sets `decoration:blur:enabled` 0 and `animations:enabled` 0 on, then **resets** both on off.
  - A naive Reduce Transparency that also writes `decoration:blur:enabled` is undone the moment Game mode turns off. The same goes for J10's Reduce Motion and `animations:enabled`.
- `services/PowerSaving.qml:25-26,41-47`: `onBattery`, `saving` (battery and the save-on-battery setting) and the active power profile (`power-saver` exists).

## Do

1. **The switch.** "Reduce transparency" in Settings beside Reduce Motion. On means:
   - Hyprland blur off;
   - the shell's own transparency off (the existing switch shows it is overridden);
   - layers drawn opaque.
   Off restores the user's own choices.
2. **Automatic.** It also turns on by itself while `PowerSaving.saving` is true or the power profile is `power-saver`, unless the user turned it off explicitly during that time. Show "On (saving battery)" when automatic.
3. **One owner for the shared keys.** Effects that more than one feature turns off are computed in one place: `decoration:blur:enabled` = not (game mode or reduce transparency), and the same shape for `animations:enabled` with J10's Reduce Motion. Game mode, Reduce Transparency and Reduce Motion set flags there; that place writes the bridge. Turning one feature off never re-enables what another still holds. Coordinate the `animations:enabled` half with J10's merged code; do not fork its logic.
4. **Measure blur.** On the nested harness, with two translucent windows and the live desktop idle, measure GPU busy with `intel_gpu_top -J` (installed) for blur passes 3, 2 and off, three runs each. Report the numbers and screenshots of passes 3 and 2 side by side. Do not change `passes` yourself: the lead decides from your numbers, and the live seat is measured only with the founder's word.

## Tests (fail on `dev` first)

- A headless probe with `HyprlandConfig` writing to a temp `shellOverrides` file:
  - Reduce Transparency on writes blur off;
  - Game mode on then off leaves blur off while Reduce Transparency is on;
  - Reduce Transparency off with Game mode off restores blur;
  - `PowerSaving` forced to saving turns it on automatically.
- The same shape for `animations:enabled` once J10's Reduce Motion exists.

## Acceptance

- shellshot renders of the Settings rows at 1920x1200 and 1366x768, dark and light. The blur measurement table and screenshots.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Changing blur parameters other than on/off (the lead decides `passes`). Per-app opacity rules.
