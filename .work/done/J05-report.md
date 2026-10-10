# J05 report: Settings stops sending people to a JSON file

Branch `worktree-agent-aee9c9d12b4cb401c` (worktree `.claude/worktrees/agent-aee9c9d12b4cb401c`), cut from `dev` at `d37e21fb6`, one commit: `b9d406166`.
(This file lives in the worktree's gitignored `.work/`; the tool refused a write to the shared checkout path. Copy it to `.work/J05-report.md` in the main checkout if wanted.)

## What changed

- `dots/.config/quickshell/koompi/modules/settings/QuickConfig.qml`: the `NoticeBox` banner ("Not all options are available...") and its "Copy path" button are deleted. No import became unused.
- `dots/.config/quickshell/koompi/settings.qml`:
  - The filled `FloatingActionButton` "Config file" above the page list is deleted.
  - A `NavigationRailButton` "Edit config file" (icon `edit`, `toggled: false`, `showToggledHighlight: false`, `onClicked: Qt.openUrlExternally(`${Directories.config}/koompi/config.json`)`) now sits after the `Repeater`, so it is the last child of the page list. Same URL expression as the old action.
  - `navRailWrapper.implicitWidth` referenced `fab.baseSize`; it now reads `configFileButton.baseSize` (56 either way).
  - `navRail` anchors gained `right: parent.right`. The FAB was the only thing giving the rail a width; without the anchor the whole page list rendered at 0 width (blank rail, seen in a screenshot before the fix). The test catches that now.
- `tests/test_settings_config_item.sh` (new, 166 lines): see below.
- Docs: nothing in `docs/` or `dots/.local` mentions the button or banner (grepped `config file`, `copy path`, `Not all options`), so no doc change.

Decisions for the lead:
1. `services/SettingsPages.qml` is NOT touched. `SettingsPages.list` is also read by `LauncherSearch.qml` (Search shows every entry as an "Open <page>" result and runs `koompi-settings <pageArg>`), by `ApprovalCard.qml`, by `tests/test_search_providers.sh`, and by the Ctrl+PageUp/Down/Tab paging in `settings.qml`. A non-page action in that list would show up in Search as a page that cannot open and would be a paging stop. So the item is appended after the list's `Repeater` in the one file that renders the rail (one place, not two).
2. The pill's hidden right-click "copy path" (with its "Path copied" label state and tooltip) is gone along with the banner's Copy path button. Restoring it is a `TapHandler { acceptedButtons: Qt.RightButton }` on the new button; I left it out as unrequested and untestable headless (no input injection in the harness).
3. `translations/*.json` untouched per contract: "Edit config file" has no entry and falls back to the English key; the old keys ("Config file", "Copy path", the banner sentence) remain as dead entries in `en_US.json`.

## The test and its before/after

`tests/test_settings_config_item.sh` runs the real `settings.qml` (instantiated from a probe `ShellRoot` in a symlinked shell root) inside headless `kwin_wayland --virtual` under `dbus-run-session`, with a private `XDG_RUNTIME_DIR`, private XDG config/state/cache, `HYPRLAND_INSTANCE_SIGNATURE` unset, `QT_NO_XDG_DESKTOP_PORTAL=1`, and `xdg-open`/`kde-open*`/`gio`/`gnome-open` shimmed to a log. After the Quick page renders it walks the item tree and asserts: no text containing the banner sentence, no "Copy path" text, no `FloatingActionButton`, the `NavigationRailButton` texts sorted by y equal `SettingsPages.list` names followed by "Edit config file", every nav item has a shown width over 40 px inside its clipping ancestors, the last item is not toggled, and emitting `clicked()` on it makes the opener receive `file://.../koompi/config.json` under the private config dir. No QML source grep.

On `dev` code (the two source files checked out from `dev`, final test file):

```
PASS the Quick page rendered (its Wallpaper & Colors heading is in the tree)
FAIL no banner text anywhere in the tree
FAIL no Copy path button
FAIL no FloatingActionButton in the window (found 1)
FAIL navigation is the page list then Edit config file, got ["Quick","General","Bar","Background","Interface","Displays","Input","Shortcuts","Network","Bluetooth","Sound","Power","Privacy","Account","AI","Services","Advanced","About"]
PASS every navigation item shows inside the rail, narrowest 134 px
PASS the last item is not the selected one
FAIL: the settings window does not match the contract above
FAIL: pressing Edit config file did not open the config file; opener got 'nothing'
exit=1
```

On the committed code:

```
PASS the Quick page rendered (its Wallpaper & Colors heading is in the tree)
PASS no banner text anywhere in the tree
PASS no Copy path button
PASS no FloatingActionButton in the window (found 0)
PASS navigation is the page list then Edit config file, got ["Quick","General","Bar","Background","Interface","Displays","Input","Shortcuts","Network","Bluetooth","Sound","Power","Privacy","Account","AI","Services","Advanced","About","Edit config file"]
PASS every navigation item shows inside the rail, narrowest 150 px
PASS the last item is not the selected one
PASS pressing Edit config file opens file:///home/userx/.tmp/tmp.hci54O1R2J/xdg/config/koompi/config.json
ok   settings: no banner, no filled Config file button, Edit config file is the last navigation item and opens config.json
exit=0
```

The "every item shows inside the rail" assertion also fails on the blank-rail variant (committed code minus the `right: parent.right` anchor): `FAIL every navigation item shows inside the rail, narrowest 0 px`.

## Full suite

`unset HYPRLAND_INSTANCE_SIGNATURE; NO_COLOR=1 bash tests/run.sh` on the committed tree:

```
104 passed, 4 skipped, 0 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

`test_bar_keys.sh` ("no Hyprland session, hyprctl binds not checked") and `test_globalmenu.sh` ("no compositor") skip because the signature is unset, as the contract requires; the BACKLOG baseline lists only the other two as skipped, so those two are skip-by-environment, not failures. `test_search_providers.sh` (reads `SettingsPages.qml`, checks `settings.qml` still reads `SettingsPages.list`) and `test_file_length.sh` pass.

Process slip, disclosed: my first suite launch inherited `HYPRLAND_INSTANCE_SIGNATURE` from my shell. I stopped it within seconds, while it was on `test_ai_e2e.sh` (alphabetically before `test_bar_keys.sh`), and re-ran with the variable unset. I do not believe any `hyprctl` call of mine reached the live session, but that first run was not isolated.

## Screenshots looked at (shellshot.sh, headless KWin, full size)

Before (dev), 1920x1200, `/tmp/j05-before/settings.png`: a filled rounded pill "Config file" with a pencil is the first and brightest thing in the nav, above Quick (selected), General...; the Quick page ends in the primary-container notice "Not all options are available in this app ... hitting the "Config file" button on the topleft corner or opening <path> manually." with a "Copy path" button. Collapsed rail (`/tmp/j05-before-collapsed/collapsed.png`, window 800 wide): a filled pencil tile above the icon column and the same banner. Scrolled to the bottom (`/tmp/j05-before-scroll/scrolled.png`): list ends at About, the pill stays pinned at the top.

After, same views:
- `/tmp/j05-after/settings.png` (expanded, top): the nav starts with Quick selected, no filled pill anywhere, the Quick page ends at "Bar & screen" with no banner. My first attempt (before the `right: parent.right` anchor) rendered the rail blank; that is the defect the anchor and the shown-width assertion fix.
- `/tmp/j05-after-scroll/scrolled.png` (expanded, nav scrolled to the bottom): About, then "Edit config file" with a pencil, a plain text row with no highlight, same style as the other rows. The list is 19 rows, so at the 750 px window height it is reached by scrolling the rail (the list already scrolled before).
- `/tmp/j05-after-collapsed/collapsed.png` (800 px wide, collapsed rail, scrolled): icon-only column, the pencil is the last icon after the info icon, unfilled. Like every collapsed item it has no label or tooltip.
- `qs.log`/`run.log` of the after runs: 0 matches for `TypeError|ReferenceError|Binding loop|Cannot assign`.

Not checked: hover and press states (no input injection), light mode, the right-click copy path (removed).

## Reproducing the screenshots

`/tmp/j05-probe/` is a symlinked copy of the shell root whose `shell.qml` instantiates `settings.qml` (env `SHOT_W`, `SHOT_H`, `SHOT_SCROLL=1` resize the window or scroll the nav): `SHOT_SCROLL=1 .work/tools/shellshot.sh /tmp/j05-probe /tmp/out -- sleep:10 shot:x`. Scratch, not committed.
