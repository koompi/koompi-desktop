# J27: the Launchpad shows apps, and tools go in a folder

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.7. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `modules/koompi/launchpad/LaunchpadContent.qml` and `LaunchpadItem.qml`;
- new `modules/koompi/launchpad/LaunchpadFolder*.qml` and a new `services/LaunchpadFolders.qml`;
- a new `tests/test_launchpad_folders.sh`;
- the Launchpad lines of `docs/navigation.md` and `docs/manual/*`.
Depends on: J07 merged (it converts `Launchpad.qml`, the root; do not edit the root).
Shared with: J33 (icon plate, later) restyles the tile icon in `LaunchpadItem.qml`. Keep tile structure changes small and named in the report.

## Evidence (on `dev`)

- The live grid lists developer and system utilities beside real apps, with no folders: Qt V4L2 test utility, Qt V4L2 video capture, Qt Widgets Designer, KDE Connect SMS, PulseAudio Volume Control, Kiri Voice Popup and three terminals (audit, live seat).
- `LaunchpadContent.qml:29-30`: `frontCategories` and `toolCategories`; `tier()` (`:35-46`) already ranks tools (`Development`, `System`, `Settings`, `Monitor`…) last. `allApps` (`:50-63`) orders by `LaunchpadUsage.score`, then tier, then name; `apps` (`:64-66`) switches to fuzzy search while typing.
- `:431-433`: a `DragHandler` takes the grab from a tile past the drag threshold, which is how a swipe starting on an icon pages instead of launching. Folder dragging must coexist with it.
- `LaunchpadContent.qml` is at its 575-line ratchet (`tests/file-length-allow.txt`): new behaviour goes in new files.
- `services/LaunchpadUsage.qml:18,57-64`: the pattern for a persisted JSON (`${Directories.state}/user/launchpad-usage.json`, `FileView` + `JsonAdapter`). Folders use the same pattern in their own file, not `Persistent.qml`.

## Do

1. **A Utilities folder by default.** Apps in tier 2 (`toolCategories`), plus any of the audit's named stragglers whose categories miss the list (check their real `.desktop` files under `/usr/share/applications`, read-only), go into one folder named "Utilities" on the first page's last slot. Launched apps keep their usage ranking inside the folder. An app the user drags out stays out.
2. **Folders by dragging.** Press and hold (or drag a tile slowly with the pointer) to pick an icon up. Dropping it on another icon makes a folder with both (name from their shared category, editable); dropping on a folder adds it; dragging out of an open folder removes it; a folder with one app dissolves. A quick horizontal swipe still pages; the pickup must not steal it (prove both).
3. **Open folder.** Click opens it in place over a dimmed grid with its name editable, keyboard arrows move inside it, Esc closes it. Typing a search still searches every app, folders included.
4. **Persist.** `services/LaunchpadFolders.qml` stores folders, membership, order and the "user moved this out of Utilities" set in `${Directories.state}/user/launchpad-folders.json`, written debounced. A missing or corrupt file means the default layout, logged, never a crash.

## Tests (fail on `dev` first)

- A headless probe on the Launchpad with a fixture `XDG_DATA_DIRS` holding a few app `.desktop` files and two tool ones (`Categories=Development;`):
  - the tools are in a "Utilities" folder, not on the grid;
  - a scripted drop of app A on app B makes a folder that survives a shell restart (same state dir);
  - dragging one out leaves it out after restart.
- The swipe still pages when it starts on an icon. Probe the `DragHandler` path the way `:431-433` describes, and keep the existing launchpad tests green.

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light: the grid with the Utilities folder, a folder open, and a drag in progress. Look at them in full.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Icon plates and icon theme (J33, J34). Hiding apps. The dock.
