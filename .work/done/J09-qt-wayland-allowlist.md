# J09: Qt apps on Wayland, menu apps on xcb (decision D1, staged)

Audit: `docs/design/ux-audit-2026-10-07.md` sections 5 (F4) and 7 (D1, the founder chose "staged, allowlist now and bridge later"). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence (lead, live seat, `.work/tools/qt_menus.sh`, one run each while two test suites ran)

| app | xcb to window | wayland to window | top-level menus on xcb |
| --- | --- | --- | --- |
| dolphin | 0.93 s | 0.80 s | File, Edit, View, Go, Tools, Settings, Help |
| okular | 0.67 s | 0.48 s | File, View, Edit, Go, Bookmarks, Tools, Settings, Help |
| konsole | 0.55 s | 0.79 s | File, Edit, View, Bookmarks, Plugins, Settings, Help |
| ark | 0.56 s | 0.29 s | Archive, File, Settings, Help |
| kdeconnect-app | 0.95 s | 1.53 s | none |
| pavucontrol-qt | 0.30 s | 0.34 s | none |

The allowlist is: `org.kde.dolphin`, `org.kde.okular`, `org.kde.konsole`, `org.kde.ark` (match by the desktop-entry id `koompi-launch` already derives, and by binary basename for bare commands).

- `dots/.config/hypr/hyprland/env.lua:26-30` forces `QT_QPA_PLATFORM=xcb` for the whole session.
- `dots/.local/bin/koompi-launch` starts every app opened from a key, Search, the Launchpad and the dock (`docs/navigation.md`, Apps).
- Known coupling (vault gotcha): window rules keyed on a Qt app's X11 class die when it moves to Wayland. Telegram is `TelegramDesktop` on X11 and `org.telegram.desktop` on Wayland; `dots/.config/hypr/hyprland/rules*.lua` and the Telegram panel scripts key on it. kdeconnectd has a user D-Bus override pinning Wayland already.

## Do

1. `env.lua`: `QT_QPA_PLATFORM` becomes `wayland;xcb` (Wayland with xcb fallback). Rewrite the comment to say why menus need xcb and where the allowlist lives.
2. `koompi-launch`: when the app id is on the allowlist, export `QT_QPA_PLATFORM=xcb` for that launch only. The list lives in one place in the script (or one data file beside it), not duplicated.
3. Every window rule, script and test keyed on a Qt app's X11 class or title that changes on Wayland: find them all (`grep -rn` the class names Qt apps report on both platforms, starting with Telegram), make each match both forms, and say in the report which you changed and how you know the Wayland class (run the app in the nested Hyprland harness and read `hyprctl clients -j` there).
4. Anything else in the tree that sets or assumes `QT_QPA_PLATFORM=xcb` session-wide (execs, tests, docs, the kdeconnectd override, `sdata/`): update or leave with a reason.
5. **Tests.** `koompi-launch` with systemd-run shadowed: an allowlisted id gets `QT_QPA_PLATFORM=xcb` in the launched environment, another id does not. A test that fails if `env.lua` goes back to plain `xcb`. In the nested Hyprland harness: launch `okular` through `koompi-launch` and `kdeconnect-app` through it, and assert from `hyprctl clients -j` that the first is `xwayland: true` and the second `false`.
6. **Docs.** The global menu's page or section (find it: `docs/`, `README.md`) and `docs/manual/` where they say Qt apps run on X11.

## Acceptance

- Test before/after output; the nested-Hyprland client listing.
- Full suite: no new failures.
- The lead re-measures launch times on the live seat after deployment is authorised; you do not touch the live seat.

## Out of scope

- The appmenu bridge (Phase 4).
