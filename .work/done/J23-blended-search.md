# J23: one Search list with sections, Quick Look on files, shortcuts on commands

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.2 (S2-S5); section 3.6 (Translate becomes a Search command); section 3.5 (one-shot actions belong in Search). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on:
- J07 merged; the search panel's root becomes a lazy surface.
- J04 merged; `modules/koompi/cheatsheet/cheatsheet-binds.js` `keyLabel()` draws shortcut keycaps.
- J20's report: the list of one-shot actions it took out of the toggle grid.

Files owned:
- `dots/.config/quickshell/koompi/services/LauncherSearch.qml` (508 lines, at its row in `tests/file-length-allow.txt`; split it, never grow it), new files under a new `services/launcherSearch/` for what you split out
- `services/FileSearch.qml`
- `services/commandTree/*`
- `modules/common/models/LauncherSearchResult.qml`
- `modules/koompi/overview/SearchBar.qml`, `SearchItem.qml`, `SearchPanel.qml`, `SearchWidget.qml`
- `Overview.qml`: only its `search` IPC routes; J19 owns `workspacesToggle`
- the search tests (`tests/test_search_*.sh`, `tests/bench/search/`)
- `docs/manual/02-opening-things.md`, the Search paragraph and rows of `docs/navigation.md`
- the `LauncherSearch.qml` row of `tests/file-length-allow.txt` (lower it)

## Evidence (verified on `dev` at `9de7a575a`)

- `LauncherSearch.qml:323-460`: each prefix is its own mode:
  - clipboard `:330`, emoji `:366`, windows `:383`, settings `:386`, files `:389`;
  - the un-prefixed list holds only math, apps (`:412`), shell command (`:414`), web search (`:431`) and actions (`:446`), ranked at `:462-470`.
  Files, settings and clipboard never appear without their sigil (audit S2).
- The sigil hints are drawn as a footer: `LauncherSearch.qml:285-308`, rendered at `SearchWidget.qml:283-295`.
- `FileSearch.qml:66-82`: `fd` by name under `~`, at most 30 results, after a 250 ms debounce (S3). `fileResults` (`LauncherSearch.qml:218-240`) shows the path only, plus a "Show folder" action. There is no date and no preview (S4).
- `dots/.local/bin/koompi-quicklook <path>` toggles a preview and `koompi-quicklook close` closes it; the script header has the contract.
- App rows show the desktop entry's actions as 34 px icon-only buttons with a tooltip (`LauncherSearch.qml:270-277`, `SearchItem.qml:310-349`). That is the Chrome row's two unlabelled icons (S5).
- `LauncherSearchResult.heading` (J03) draws a group heading on a row's first item, already used for Recent and for the command groups.
- `services/commandTree/Entries.qml` has toggles, display, session and system commands. It has no capture commands (snip, record, colour picker, identify music) and no translate.
- Translation today is the left sidebar's tab, which runs `trans -brief` (translate-shell, online; `modules/koompi/sidebarLeft/Translator.qml:64-70`). J24 removes the tab.
- Search speed is guarded by `services/SearchBench.qml`, `tests/bench/search/` and `tests/test_search_bench_parity.sh`.

## Do

1. **Split first** at a real seam, with no behaviour change, and prove it with the existing search tests. Good seams: each provider (apps, files, clipboard, commands, math, web) into `services/launcherSearch/`, and ranking into a pure JS file (kebab-case) that bun can test.
2. **One ranked list for an un-prefixed query.** Sections are drawn with the existing `heading` mechanism, in this order when they have rows:
   - **Top Hit:** the single best match across all providers;
   - Applications;
   - Commands and Settings (command-tree leaves and settings pages);
   - Files;
   - Calculator;
   - Clipboard (up to three matches; the work-safety blur rules still apply).
   Web search stays the last row. Each section keeps at most five rows, plus a "Show all N" row that switches to that sigil's scope.
3. **Rows that arrive late** (files after the 250 ms debounce) slot into their section without moving the selection: the row under the keyboard cursor stays under it.
4. **Sigils stay as filters** for people who know them. The footer hints are drawn at 12 px or more.
5. **File rows** show the parent folder (home-relative) and the modified date ("Today 14:02", "3 Oct"). Get dates in one batch per result set, never a process per row.
   - When a file row has keyboard focus (after an arrow key moved into the list), `Space` toggles Quick Look with `koompi-quicklook <path>`, and `Escape` closes it before closing Search.
   - While the text field has focus, `Space` types a space as today.
6. **Commands show their shortcut.** Map each command-tree leaf to its keybind through `HyprlandKeybinds`, by description or dispatcher. Draw it with `cheatsheet-binds.js` `keyLabel()` keycaps, right-aligned. A command with no bind shows none.
7. **One-shot actions become commands,** each with its shortcut: region snip, record region, record screen with sound, colour picker, identify music, on-screen keyboard, translate screen. Cross-check J20's list.
8. **Translate.**
   - `Translate <text>` translates the text with the same `trans` call, reading engine and languages from `language.translator` (`Config.qml:501-505`). With no text, it translates the primary selection (`wl-paste --primary --no-newline`, run only when the row is invoked).
   - The result row says the text was sent to an online translator. `Enter` copies the result.
9. **S5.** On the selected app row, desktop-entry actions show as labelled text buttons ("New Window", "New Incognito Window"). Unselected rows show none.
10. **Speed.** No process per keystroke. Report `tests/bench/search` numbers before and after, and `tests/test_search_bench_parity.sh` must still pass where it can run.

## Tests that fail first

- **bun:** the ranking function. Assert section order, the Top Hit choice, the per-section cap and stable selection when late rows arrive.
- **Headless or nested probe** (extend `tests/test_search_providers.sh` / `tests/test_search_commands.sh` patterns). An un-prefixed query that matches an app, a settings page and a seeded file in a temp HOME. Assert:
  - the section headings and their order;
  - the file row's folder and date text;
  - a capture command row carrying its keycaps.
  On `dev` the file never appears without `~`.
- **Quick Look:** with `koompi-quicklook` shadowed by a script that records its argv, Space on a focused file row records `<path>`, and Space in the text field records nothing.
- `tests/file-length-allow.txt` lowers the LauncherSearch row, and `tests/test_file_length.sh` passes.

## Acceptance

- hyprshot renders at 1920x1200 and 1366x768, dark and light, looked at in full:
  - empty query (Recent);
  - "term";
  - "set" (commands and settings);
  - a file query with dates;
  - a selected Chrome row showing its labelled actions;
  - the Translate row.
  Nothing clipped, no text under 12 px.
- Keyboard only: type, move into sections, open a file with Enter, Quick Look with Space, a command with Enter.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- The on-device content index (Phase 4), the overview's own filter (J19), the left sidebar (J24).
