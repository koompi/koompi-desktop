# J40: every string the campaign added reaches the translation files

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first. The contract forbade hand-editing `translations/*.json` during the campaign. This job brings them up to date through the repo's own tool, once.
Files owned: `dots/.config/quickshell/koompi/translations/*.json` (written only by the tool), a new test, a note in `docs/agents/`.
Depends on: runs last, after every other campaign job that adds `Translation.tr` strings has merged.

## Evidence (on `dev`)

- `dots/.config/quickshell/koompi/translations/` holds 14 languages (`en_US.json`: 616 keys) and `tools/`:
  - `manage-translations.sh` with `status`, `extract`, `update`, `clean`, `sync` (`:16-33`);
  - `translation-manager.py`;
  - `translation-cleaner.py`;
  - a guide (`tools/guide/translation-tools-guide.md`).
- `translation-manager.py`:
  - `extract_translatable_texts` scans `*.qml` and `*.js` for `Translation.tr("…")` literals;
  - `interactive_update` (`:141-190`) adds missing keys with the key itself as the value, and offers to delete "extra" keys unless their value ends in `/*keep*/`. `--yes` answers yes to both.
- `Translation.tr` falls back to the key, so a missing key shows English. Adding keys changes nothing at run time until someone translates them.
- There is no Khmer file (`km_KH.json`), though Khmer is the founder's market's language and the audit measures text with Khmer.

## Do

1. Run `manage-translations.sh status` and `extract` on the merged tree. Report the counts: missing keys per language, extra keys.
2. Add the missing keys to every language with the tool (value = English key, its convention).
3. **Do not blindly delete extra keys.** For each one, grep the tree. A key is removed only when no literal and no dynamically built string (`Translation.tr(variable)`, `.arg()` templates, strings built in JS) can produce it. List every removal with its grep in the report. Never run the tool with `--yes` for deletions.
4. Add a test that fails when a `Translation.tr` literal in the tree has no key in `en_US.json`, so the next campaign cannot drift. Use the tool's own extractor; do not re-implement the regex.
5. Note how to add and update keys in `docs/agents/`, pointing at the tool.

## Acceptance

- The status counts before and after, the list of deliberate deletions, the test's before/after output.
- Full suite: 0 failed.

## Out of scope

- Translating anything. Creating `km_KH.json`: that is a product decision for the lead and founder. Raise it in the report with the key count it would need.

## Addition, 2026-10-11

- `ja_JP`, `it_IT` and `de_DE` carry the removed tray string. It goes, by the grep rule above.
- Runs after J55, J56, J57 and J58 merge, so their strings are included.
