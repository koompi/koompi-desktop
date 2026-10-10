# J04: the cheatsheet speaks keys, once each

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.8. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

Live screenshot of `Super+/` on 2026-10-07:
- Raw key names on keycaps: `grave`, `backslash`, `Semicolon`, `Apostrophe`, `Comma`, `MouseBack`, `mouse:274`, `mouse:276`, `Bracket<Direction>`, `BracketRight`, `Page_Up`, `Page_Down`, `<Direction>`, `<Number>`.
- Duplicate rows with the same description: `Terminal` twice, `Record region (no sound)` twice, `Send to workspace left` three times, `Send to workspace right` three times, `Move` twice, `Focus <Direction>` twice, `Next track` and `Previous track` twice each.
- Substitution table: `modules/koompi/cheatsheet/CheatsheetKeybindsCategory.qml:40-80,132`; binds come from `services/HyprlandKeybinds.qml`; descriptions from `dots/.config/hypr/hyprland/keybinds*.lua`.

## Do

1. **Key names.** Every key a bind can name renders as what is printed on the key or a clear glyph: ` for grave, \ for backslash, ; ' , . / [ ] for the punctuation, PgUp/PgDn, arrows for directions, "1–0" for number ranges, "Middle click", "Back", "Forward" for mouse buttons 274/275/276, "Scroll" for wheel binds. Unknown names fall back to the raw name, so nothing disappears.
2. **One row per action.** Rows in the same category with the same description merge into one row that shows each chord, separated by "or". Order the chords so the simplest (fewest modifiers) comes first.
3. **Wrong descriptions.** Where two different actions share a description because one is mislabelled (check `Record region (no sound)` twice: one may record the screen or with sound), fix the description in the `.lua` file. Only descriptions; never change a chord or its dispatcher.
4. **Test.** The parse and merge logic must be testable without Hyprland: if it lives in QML, move the pure part (substitute, merge) into a small JS file beside it, kebab-case per `docs/conventions.md`, and test it with `bun` or `node` from `tests/` (see how `tests/bench/search/` tests pure JS). The test fails on the old table and passes on yours. `tests/test_keybind_descriptions.sh` must still pass.

## Acceptance

- Test before/after output.
- The cheatsheet does not get binds under headless KWin (no Hyprland). Feed the merged rows for the live keybinds.lua through your JS and paste the resulting table for the Window and Utilities categories in the report.
- Full suite: no new failures.

## Out of scope

- Reordering categories, the essentials-first layout, or making rows clickable (already done by J35).

## Round 4 (lead, after the round-3 renders)

- `J04_elements_fit fit_tiles_now p=1.0 (jev-1.13.0)`: at 1366x768 the clamp left Hydrogen, Helium and the actinide row as slivers and cut the outer columns. Size the tiles from the space the panel leaves.
- `J04_wheel_direction swap_wheel_binds p=0.94 (jev-1.13.0)`: Hyprland 0.56.2 fires `mouse_down` for a positive (downward) wheel delta (`KeybindManager.cpp` `onAxisEvent`), so the end-4 label table is inverted and the wheel binds go the opposite way to the Page Up/Down binds in the same rows.
- Request: `.work/jev/J04-round4.json`.
