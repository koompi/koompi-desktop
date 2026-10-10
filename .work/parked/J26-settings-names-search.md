# J26: Settings speaks plainly and can be searched

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.10. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `settings.qml` (the header search field only);
- `services/SettingsPages.qml` (a `keywords` field per page);
- `modules/settings/QuickConfig.qml` (only the colour-scheme array `:195-238` and the bar-style array `:290-308`);
- `modules/settings/BarConfig.qml` (the bar-style array `:94-110`);
- `welcome.qml` (the bar-style labels `:248-262`);
- `modules/settings/AdvancedConfig.qml`;
- a new palette-preview script under `scripts/colors/` and a new test.
Depends on: J11 (Settings hosted by the running shell) merged; J05 is merged.
Shared with:
- J32 (Reduce Transparency) adds one switch to `QuickConfig.qml` beside J10's Reduce Motion. Leave the switch rows `:240-248` and anything J10 added alone.
- J23 (Search) may read the new `keywords` field.

## Evidence (on `dev`)

- `QuickConfig.qml:195-238`: the palette chooser lists Material's internal scheme names, "Content, Expressive, Fidelity, Fruit Salad, Monochrome, Neutral, Rainbow, Tonal Spot", as text chips with no preview. The values are `scheme-*` (`modules/common/Config.qml:246`).
- `QuickConfig.qml:290-308`, `BarConfig.qml:94-110` and `welcome.qml:248-262` label the bar style "Hug" and "Float".
- `settings.qml:151-203`: a navigation rail with no search. J05 left "Edit config file" as the last rail item (`:194-203`, `configFileButton`); the audit's target is the config file under Advanced.
- `services/SettingsPages.qml:10-100` lists the pages (name, icon, component), and `LauncherSearch.qml:196-213` turns them into "Open <page>" results. No option inside a page is searchable anywhere.
- `scripts/colors/generate_colors_material.py:14-19` already generates a palette for `--path <image> --scheme <s> --mode <m>`.

## Do

1. **Plain scheme names with live swatches.** Each scheme option shows its name and a swatch of three or four colours. The swatch is generated from the current wallpaper for that scheme in the current mode, by a small script that calls `generate_colors_material.py` once per scheme. Cache it keyed by wallpaper path, mtime and mode under the shell's state dir, and regenerate when the wallpaper changes. Proposed names: Auto → "Automatic", tonal-spot → "Balanced", neutral → "Soft", monochrome → "Mono", expressive → "Expressive", fidelity → "Faithful", content → "Matches wallpaper", fruit-salad → "Playful", rainbow → "Rainbow". The lead confirms the table before you start (it may go to Jev). Values in `Config` do not change.
2. **Bar style names.** "Hug" and "Float" become words that say what happens, with the existing icons. Proposed: "Attached to the edge" and "Floating". Change the same labels in `QuickConfig.qml`, `BarConfig.qml` and `welcome.qml`, so one option has one name everywhere.
3. **Search in Settings.** A search field at the top of the navigation. Typing filters the rail to pages whose name or keywords match (fuzzy, the same `Fuzzy` the shell uses). Enter opens the first page and scrolls to and briefly highlights the matching option when the match was a keyword. Keywords live in `SettingsPages.qml`, one string per page, listing the visible option labels on that page.
4. **Config file under Advanced.** The "Edit config file" rail item moves into `AdvancedConfig.qml` as the first row ("Edit the config file", same action, plus "Copy path"). The rail ends at About. Update J05's `tests/test_settings_config_item.sh` to the new place; it is the test of that behaviour.

## Tests (each fails on `dev` first)

- A headless probe on `settings.qml` (pattern: `tests/test_settings_config_item.sh`):
  - no option label equals a Material scheme id ("Fruit Salad", "Tonal Spot", "Fidelity", "Content") or "Hug"/"Float";
  - each scheme option draws a swatch;
  - typing a keyword ("night light", "transparency", "bar position") leaves its page in the rail, and Enter opens it.
- **Drift guard:** the probe instantiates every page and fails if a visible `ConfigSwitch`/`ConfigSelectionArray`/`ConfigSlider` label on it is missing from that page's keywords, so the index cannot go stale. Not by grepping QML.
- The palette script: one cached JSON per (wallpaper, mode); a second run reuses it.

## Acceptance

- shellshot renders of Settings at 1920x1200 and 1366x768, dark and light: the Quick page showing swatches and new names, and a search in progress. Look at them in full.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Adding or removing schemes, or any option's behaviour. Search across Settings from the shell's Search (J23). Translations (J40).
