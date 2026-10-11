# Translation keys

Every user-facing string goes through `Translation.tr("...")`. The key is the English
text. `Translation.tr` looks the key up exactly (no trim) and falls back to the key,
so a missing key shows English and nothing breaks; the file only has to hold a key
for a translator to find it.

Files: `dots/.config/quickshell/koompi/translations/<lang>.json`, one per language.
The tool lives in `translations/tools/` (`manage-translations.sh`, guide in
`tools/guide/`). Run it from anywhere:

```
translations/tools/manage-translations.sh status     # key count per language
translations/tools/manage-translations.sh extract    # every literal the scan finds
printf 'y\nn\n' | translations/tools/manage-translations.sh update -l de_DE
```

## Adding or changing a string

1. Write the literal in the code: `Translation.tr("Copy path")`. One literal on one
   call, no `+` inside the call: the scan matches `Translation.tr("...")` only.
2. Run `update -l <lang>` for each language file. Answer `y` to "add missing keys";
   each is added with the English text as its value. Answer `n` to the deletion
   prompt unless you have checked it (below). Do not pass `--yes`: it deletes.
3. `tests/test_translation_keys.sh` fails while any literal has no key in `en_US.json`.
4. Changing a string's wording makes a new key. The old key stays until you delete it (next section).
   Translated values stay under the old key, so move them by hand if the meaning is the same.

The tool writes a `<lang>.json.bak` beside each file it changes; delete those.

## Deleting a key

The tool lists keys no literal produces and offers to delete them. Delete one only
after grepping the whole tree (not just `Translation.tr` calls) for the exact text,
in `.qml`, `.js`, `.lua`, `.sh` and the Rust and Zig services. Keep it if it is
produced another way:

- `Translation.tr(variable)`: weekday names from `calendar_layout.js`, tour text
  from `tour/steps.js`, `statusText` of the quick toggles, `categoryName` in
  `ShortcutsConfig.qml`, `CcExtraRow`. The scan cannot see these, so list their
  strings as keys by hand and mark each with a value ending `/*keep*/` if the tool
  should stop offering to delete it.
- Keys with leading or trailing spaces (`"Auto, "`, `"Saved    "`): the scan strips
  them, the runtime does not. Leave the padded key; the tool also adds a stripped
  twin that never matches.

## What the scan does not see

- Strings built by concatenation inside the call (`Translation.tr("a " + "b")`,
  `ResearchService.qml`). They never match a key; keep the literal on one line.
- Strings that never reach `Translation.tr`: Hyprland bind descriptions in
  `keybinds.lua` (the cheatsheet shows them as written), `GlobalShortcut.description`,
  tool descriptions sent to the model. They are English until the code translates them.

## Khmer

There is no `km_KH.json`. Creating one is a product decision, not a tool step.
