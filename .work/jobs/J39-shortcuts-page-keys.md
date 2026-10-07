# J39: Settings > Shortcuts shows keys the way the cheatsheet does

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.8; the J04 report's open point on the second key table. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: `modules/settings/ShortcutsConfig.qml`, a new or extended test.
Depends on: J04 merged. It adds `modules/koompi/cheatsheet/cheatsheet-binds.js` (`keyLabel`, `buildRows`, `keycaps`) and its bun test `tests/test_cheatsheet_binds.sh`.
Shared with: `cheatsheet-binds.js` stays J04's module. Import it; do not fork it. If Settings needs something it lacks, add it there with a test, and say so in the report.

## Evidence (on `dev`)

- `ShortcutsConfig.qml:15-41` keeps its own copy of the old substitution table (`keySubstitutions`: `mouse_up` → "Scroll ↓", `mouse:272` → "LMB", `Slash`, `Return`), its own `modMaskToStringList`, and `transformKey`. Anything else shows as a raw name.
- `:71-80` lists one row per bind, so duplicates the cheatsheet now merges appear twice here.
- J04 replaced the cheatsheet's table with `cheatsheet-binds.js`: printed key names, one row per action, chords joined by "or".

## Do

1. `ShortcutsConfig.qml` builds its rows with `CheatsheetBinds.buildRows` (the same input mapping as `CheatsheetKeybindsCategory.qml`: `HyprlandKeybinds.modifiersOf`, `keyOf`, `dispatchable`), and draws key labels with `keyLabel`/`keycaps`.
2. Delete the local table, `modMaskToStringList` and `transformKey`.
3. The page's search (`matchesSearch`, `:64`) still filters, by description and by printed key names.

## Tests (fail on `dev` first)

- A headless probe that instantiates the Shortcuts page with a shim `hyprctl` fed the repo's binds (J04's layout test shows how):
  - no visible key label is a raw Hyprland name (`grave`, `mouse:274`, `Page_Up`, `XF86AudioRaiseVolume`);
  - the page's row count per category equals the cheatsheet's for the same binds.

## Acceptance

- shellshot renders of Settings > Shortcuts at 1920x1200 and 1366x768, dark and light. Look at them in full.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Editing binds from Settings. The cheatsheet itself.
