# J43: a restored or pinned app is the same app as the running one

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `dots/.config/quickshell/koompi/services/SessionRestore.qml`
- `dots/.config/quickshell/koompi/services/TaskbarApps.qml`
- the dock delegate, only if keying moves there
- one new test

Start after J09 merges (its `koompi-launch` decides each app's platform).

## Evidence (J09's open points 2 and 3, read by the lead on `dev@2f9a1d514`)

- `SessionRestore.qml:127-131` replays a saved session with `entry.execute()`, which bypasses `koompi-launch`.
  - Restored apps never land in `app.slice`, so systemd-oomd treats them as the session.
  - The xcb allowlist never applies to them, so a restored Dolphin, Okular, Konsole or Ark comes up on Wayland with no menu in the bar.
- `SessionRestore.qml:141` `claim()` compares the saved class with the new window's class.
  - J09 measured that one app reports different classes per platform: `dolphin` on xcb and `org.kde.dolphin` on Wayland, `kdialog` and `org.kde.kdialog`, `TelegramDesktop` and `org.telegram.desktop`.
  - A mismatch leaves the window on the wrong workspace.
- `TaskbarApps.qml:27-50` keys pinned ids and running toplevels by the lowercased app id.
  - The dock pins `org.kde.dolphin`, while a running xcb Dolphin is `dolphin`, so the dock shows two entries for one app.
  - The dock is off by default.

## Do

1. Replay through `LauncherSearch.launch(entry)` (`services/LauncherSearch.qml:242`), so a restore launches exactly as Search does.
2. Match on the desktop entry, not the raw class: `DesktopEntries.heuristicLookup(class)?.id` on both sides, falling back to the lowercased class when there is no entry.
   Use the same rule in `TaskbarApps` for pinned ids against running toplevels.
   If `heuristicLookup` cannot map one of the measured pairs above, say which, and match it another way.
3. Add a test that fails on `dev`: a headless probe (offscreen, private HOME and runtime dir, as the contract requires) that feeds both classes of one app.
   - A restore claims the window once, for the right workspace.
   - The dock model has one entry for a pinned app running under its other class.
4. Look at the screen: enable the dock in a `hyprshot.sh` session, pin Dolphin, start it through `koompi-launch`, and show one dock icon.

## Acceptance

- The test's failing output on `dev` and its passing output after.
- The dock render.
- Full suite through `heavy.sh`: no new failures.
