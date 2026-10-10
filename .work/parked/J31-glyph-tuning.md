# J31: system glyphs match the text beside them, and on/off never rides on colour alone

Audit: `docs/design/ux-audit-2026-10-07.md` section 4, items 3 and 4. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `modules/common/widgets/MaterialSymbol.qml`;
- the icon-font tokens in `modules/common/Appearance.qml` (`font.family.iconMaterial` `:244`, `font.variableAxes` `:251-262`; nothing in the animation ladder, which is J10's);
- the shared toggle widgets in `modules/common/widgets/` that draw a toggled state (`NavigationRailButton.qml`, `ConfigSelectionArray.qml`, `LightDarkPreferenceButton.qml`);
- a new test; a short rule in `docs/conventions.md`.
Depends on: J10 merged (`Appearance.qml` is at its 467-line ratchet and J10 edits it).
Shared with: the Control Center toggles (J20), the bar's mode indicators (J22) and the overlay buttons (J29) follow the rule this job writes into `docs/conventions.md`. They do not wait for it, but must match it. J31 does not edit their files.

## Evidence (on `dev`)

- `MaterialSymbol.qml:18`: glyph weight follows `fill` (`Font.Normal` to `Font.DemiBold`), not the adjacent text, whose weight is `wght 450` (`Appearance.qml:251-262`). `:19-21`: the only variable axis set is `FILL`; optical size and grade follow the font's defaults. `:24-30`: `fill` animates, so intermediate `FILL` values occur (truncated to 0.1).
- **The cost constraint** (`MaterialSymbol.qml:8-11`, measured by an earlier session): every distinct `variableAxes` tuple is a separate ~8.5 MB font instance held for the process lifetime. Adding `opsz` per icon size once measured 1.23 GB against 340 MB. The shell draws about 20 distinct icon sizes (`grep iconSize:`).
- On/off by colour alone: `RippleButton`-based toggles change `colBackgroundToggled` and the glyph colour only, e.g. `modules/koompi/overlay/OverlayTaskbar.qml:147` and the rail buttons.

## Do

1. **Weight matched to text.** A glyph beside body text uses the body weight. Map the `wght` axis to the text style it sits in (body 450, title 550) through two named tokens, not per call site. On is filled (`FILL 1`) at the same weight; it no longer gets bolder.
2. **Optical size in a few buckets.** Round `opsz` to the font's useful stops (20, 24, 40, 48) from the drawn size, never per size. Keep `FILL` to 0 and 1 with the change crossfaded rather than interpolated, so the instance count goes down, not up.
3. **Measure the cost.** Count distinct `variableAxes` tuples at run time in a headless full shell (a probe that walks every `MaterialSymbol`), and measure full-shell PSS (`.work/tools/measure_surfaces.sh`, the `full` line) before and after. Neither may rise. If buckets cost more than they buy, report the numbers and stop at the weight change.
4. **On/off with more than colour.** In the shared widgets you own, the on state is the filled glyph plus the accent plate, and where a word fits, "On". Write the rule as three lines in `docs/conventions.md`, so J20, J22 and J29 can follow it.

## Tests (fail on `dev` first)

- The probe from step 3, as a test: it fails if any `MaterialSymbol` beside body text has a `wght` other than the body token, if a toggled shared widget's glyph is not filled, or if the distinct tuple count exceeds a budget you set from the measurement (state it in the test).

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light, of the bar, Settings' Quick page and the right panel: glyph weight beside text before and after, cropped and compared at full size.
- Before/after: distinct tuple count and full-shell PSS. Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- App icons, the icon plate and the icon theme (J33, J34). Replacing Material Symbols. Toggles inside J20/J22/J29's files.
