# Campaign: UX 10x, from docs/design/ux-audit-2026-10-07.md

Started 2026-10-07 on `dev` at `e9521d2d7`. Lead: Opus, verifies. Workers: Sonnet, one job each, two at a time, each in its own worktree.
The previous campaign is in `archive/2026-08-25-maintainability-omarchy/`.

## Baseline, before any job

`NO_COLOR=1 ./tests/run.sh` on `e9521d2d7`: 101 passed, 2 skipped, 1 failed (4 min 49 s).
- failed: `test_update_guards.sh`, "a deleted Hyprland exe must print the reboot line" (pre-existing; J06 owns it).
- skipped: `test_hypridle_logged.sh` (needs KOOMPI_TEST_LIVE_LOCK=1), `test_search_bench_parity.sh` (needs a bench-enabled qs).

Live shell at baseline: qs PSS 505 MB.

## Verification tools (lead's, not committed)

- `.work/tools/shellshot.sh SHELL_ROOT OUT_DIR [WxH] -- STEP...` runs a shell tree in headless KWin with a private bus and fresh XDG dirs and screenshots it. Steps: `ipc:<target> <fn> [args]`, `run:<cmd>`, `sleep:<s>`, `shot:<name>`. Hyprland-only surfaces (search, overview, cheatsheet binds) do not render there.
- `.work/tools/timelaunch.sh` from the archive: launch-to-window timing.

## Phase 0 jobs

| Job | Title | Files owned | State |
| --- | --- | --- | --- |
| J01 | Update badge out of the panel button; popup clamp | `modules/koompi/bar/{BarContent,UpdateBadge,StyledPopup}.qml`, new `UpdatesPopup.qml`, `tests/test_bar_keys.sh`, `docs/navigation.md` (update badge row) | ready |
| J02 | Right panel header; read state | `modules/koompi/sidebarRight/SidebarRightContent.qml`, `GlobalStates.qml`, `services/Notifications.qml`, `docs/navigation.md` (sidebar paragraph) | ready |
| J03 | Plain words: crash toast, media empty state, Recent labels | `dots/.local/bin/koompi-crash-watch`, `tests/test_crash_watch.sh`, `docs/agents/crash.md`, `modules/koompi/mediaControls/MediaControls.qml`, `services/LauncherSearch.qml`, `modules/koompi/overview/Search*.qml` | ready |
| J04 | Cheatsheet key names and duplicate rows | `modules/koompi/cheatsheet/*`, `services/HyprlandKeybinds.qml`, `dots/.config/hypr/hyprland/keybinds*.lua` (descriptions only) | ready |
| J05 | Settings: config-file banner and button | `settings.qml`, `modules/settings/QuickConfig.qml` | ready |
| J06 | External monitor refresh; the failing update test | `dots/.config/hypr/hyprland/general.lua` (monitor rule), `dots/.local/share/koompi/libexec/update*`, `tests/test_update_guards.sh` | ready |

Contended: `docs/navigation.md` (J01, J02, different paragraphs). Translation JSON files belong to nobody in this phase.
Moved out of Phase 0: the cursor theme. Adwaita is deliberate (`394153191`); it joins the Phase 3 identity decision.

## Phase 1 jobs

Measurements behind them: `/tmp/surfaces.tsv` (per-surface PSS, headless), `/tmp/qt_menus.txt` (Qt menus and launch times, live seat).

| Job | Title | Files owned | Wave | State |
| --- | --- | --- | --- | --- |
| J07 | Lazy surfaces | `panelFamilies/*`, new `modules/common/LazySurface.qml`, root files of launchpad, cheatsheet, polkit, screenTranslator, mediaControls, overview, sidebarRight, sessionScreen, tour, screensaver, sidebarLeft | A | ready |
| J09 | Qt on Wayland, xcb allowlist | `hypr/hyprland/env.lua`, `dots/.local/bin/koompi-launch`, rules keyed on Qt X11 classes, kdeconnectd override | A | ready |
| J08 | Screen corners | `modules/koompi/screenCorners/*` | B | ready |
| J10 | Motion and Reduce Motion | `modules/common/Appearance.qml`, `hypr/hyprland/general.lua` (animations), `Config.qml` (one option), the appearance settings page | B | ready |
| J11 | Settings in the running shell | `settings.qml`, `dots/.local/bin/koompi-settings`, `panelFamilies/KoompiFamily.qml` (one loader) | C, after J07 | ready |
| J12 | Clipboard watcher; memd on demand | `hypr/hyprland/execs.lua` (wl-paste lines), `services/Cliphist.qml`, `services/MemoryService.qml` | C | ready |
| J13 | Launch feedback | `modules/koompi/bar/ActiveWindow.qml`, new launch service, `koompi-launch` (one call) | D, after J09 | ready |

Live seat findings outside any job: hot corners are dead because `fakeScreenRounding` is 0 there (J08 fixes the coupling; the live config is the founder's).
