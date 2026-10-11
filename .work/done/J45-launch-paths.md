# J45: every launch goes through koompi-launch, pins match by app, and no lookup runs on an empty class

Found by J43 on 2026-10-08, verified by the lead in dev's tree. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- The waffle panel family starts apps with `desktopEntry.execute()` in seven places:
  - `modules/waffle/startMenu/searchPage/SearchResultButton.qml:31`
  - `modules/waffle/startMenu/searchPage/SearchResults.qml:213`
  - `modules/waffle/startMenu/startPage/BigAppGrid.qml:33`
  - `modules/waffle/startMenu/startPage/AppCategoryGrid.qml:282`
  - `modules/waffle/bar/tasks/TaskAppButton.qml:51`, `:57` and `:117`
- Those apps skip `koompi-launch`: no app scope for oomd, no xcb menu rule, and no launch feedback.
  - `LauncherSearch.launch(entry)` is the shell's one launch path; see the comment at `services/LauncherSearch.qml:241`.
  - `docs/navigation.md` says every launch goes through `koompi-launch`.
- `TaskAppButton.qml:108` runs a desktop action with `action.execute()`.
- `modules/waffle/startMenu/searchPage/SearchResults.qml:205-206` reads pins with `includes(appId)`. A dock pin saved under an app's other class (`dolphin` vs `org.kde.dolphin`) shows as unpinned there.
- These call `DesktopEntries.heuristicLookup` on a window class that can be empty:
  - `modules/koompi/mediaControls/MediaControls.qml:47`
  - `modules/koompi/dock/DockAppButton.qml:21` and `:29`
  - J43 measured that `heuristicLookup("")` returns an arbitrary entry: `org.kde.plasma.settings.open` in one run, `kcm_colors` in the next. The result is a wrong icon and name, or the wrong window taken as the media player's.
- `services/SessionRestore.qml` relaunches `NoDisplay=true` entries. `kdialog` starts bare and opens nothing, and a 90 s claim for its class can move an unrelated dialog onto the saved workspace.

## Decided

- `J43_found_routing new_job_after_j44 p=0.97 (jev-1.13.0)`
- `J43_restore_nodisplay skip_nodisplay p=0.89 (jev-1.13.0)`

## Do

1. Every waffle launch of a desktop entry goes through `LauncherSearch.launch(entry)`.
   - Check `modules/koompi/overview/SearchItem.qml:345` too, and any other `.execute()` on a desktop entry you find.
   - Desktop actions: use a `koompi-launch` path if `LauncherSearch` has one. If it has none, stop and report rather than build one.
2. Waffle's pin check uses `TaskbarApps.isPinned` for dock pins, so a pin under either class counts. Check whether the launcher's own pins at `:206` need the same.
3. No `heuristicLookup` runs on an empty class. Fix `MediaControls.qml:47`, `DockAppButton.qml:21,29`, and any other caller you find.
4. `SessionRestore` skips entries with `NoDisplay=true`, the way it skips windows with no entry.
5. Tests, each failing on dev:
   - no waffle file starts a desktop entry with `.execute()`;
   - a dock pin under the other class reads as pinned in waffle search;
   - a window with an empty class maps to no entry;
   - a saved `kdialog` window is not relaunched.
6. Update `docs/navigation.md` if it names the launch paths.

## Acceptance

- The tests fail on `dev` and pass on your branch.
- A nested-harness screenshot: Dolphin started from the waffle start menu shows its menus in the bar, which is the xcb rule through `koompi-launch`. Put the repo's `dots/.local/bin` first on `PATH`; the installed `koompi-launch` predates the xcb rule. Close every app before the nested session ends.
- Full suite: no new failures.

## Depends

- J43 merged, for `TaskbarApps.appKey` and `isPinned`.
- J13 edits `LauncherSearch.launch` (its launch-feedback registration). J45 calls it and does not edit it.

## Out of scope

- `services/LauncherSearch.qml`.
- The koompi dock delegate, beyond the empty-class guard.
