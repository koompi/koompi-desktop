# Campaign: UX 10x, from docs/design/ux-audit-2026-10-07.md

Started 2026-10-07 on `dev` at `e9521d2d7`. Lead: Opus, verifies. Workers: Sonnet, one job each, two at a time, each in its own worktree.
The previous campaign is in `archive/2026-08-25-maintainability-omarchy/`.

## Baseline, before any job

`NO_COLOR=1 ./tests/run.sh` on `e9521d2d7`: 101 passed, 2 skipped, 1 failed (4 min 49 s).
- failed: `test_update_guards.sh`, "a deleted Hyprland exe must print the reboot line" (pre-existing; J06 owns it).
- skipped: `test_hypridle_logged.sh` (needs KOOMPI_TEST_LIVE_LOCK=1), `test_search_bench_parity.sh` (needs a bench-enabled qs).

Live shell at baseline: qs PSS 505 MB.

Baseline fixes by the lead on `dev`:
- `f989757a7`: `test_update_guards.sh` raced (deleted the fake Hyprland binary before the child exec'd); it failed under suite load only.
- `68b5707f9`: `test_ai_remote_default.sh` passed only with a live `HYPRLAND_INSTANCE_SIGNATURE`; the probe now pins its own.
Suite on `dev` at `d0112f2e0` (J01, J02, J03 merged), lead run: 105 passed, 4 skipped, 0 failed. Skipped: `test_bar_keys.sh` (live-binds half only, signature unset), `test_globalmenu.sh`, `test_hypridle_logged.sh`, `test_search_bench_parity.sh`. Run it with `env -u HYPRLAND_INSTANCE_SIGNATURE` (`test_bar_keys.sh` otherwise reads the live binds).

## Verification tools (lead's, not committed)

- `.work/tools/shellshot.sh SHELL_ROOT OUT_DIR [WxH] -- STEP...` runs a shell tree in headless KWin with a private bus and fresh XDG dirs and screenshots it. Steps: `ipc:<target> <fn> [args]`, `run:<cmd>`, `sleep:<s>`, `shot:<name>`. Hyprland-only surfaces (search, overview, cheatsheet binds) do not render there.
- `.work/tools/timelaunch.sh` from the archive: launch-to-window timing.

## Phase 0 jobs

| Job | Title | Files owned | State |
| --- | --- | --- | --- |
| J01 | Update badge out of the panel button; popup clamp | `modules/koompi/bar/{BarContent,UpdateBadge,StyledPopup}.qml`, new `UpdatesPopup.qml`, `tests/test_bar_keys.sh`, `docs/navigation.md` (update badge row) | merged `d22c3a6dc`, lead fix `6a515b2c3` |
| J02 | Right panel header; read state | `modules/koompi/sidebarRight/SidebarRightContent.qml`, `GlobalStates.qml`, `services/Notifications.qml`, `docs/navigation.md` (sidebar paragraph) | merged `6533e4863` |
| J03 | Plain words: crash toast, media empty state, Recent labels | `dots/.local/bin/koompi-crash-watch`, `tests/test_crash_watch.sh`, `docs/agents/crash.md`, `modules/koompi/mediaControls/MediaControls.qml`, `services/LauncherSearch.qml`, `modules/koompi/overview/Search*.qml` | merged `ea0e71d92`, lead fix `d0112f2e0` |
| J04 | Cheatsheet key names and duplicate rows | `modules/koompi/cheatsheet/*`, `services/HyprlandKeybinds.qml`, `dots/.config/hypr/hyprland/keybinds*.lua` (descriptions only) | round 2 verified (columns hold, page scrolls, 1920x1200 and 2560x1600 clean); round 3: Cheatsheet.qml clamp for 1366x768 overflow, Jev clamp_in_j04_now p=0.68. Real-binds check (founder approved, lead ran hyprshot on `a728ad11a`): 162 described binds, 0 raw key names, no QML errors, no crash |
| J05 | Settings: config-file banner and button | `settings.qml`, `modules/settings/QuickConfig.qml` | merged `aab3c5b5d` (lead: test bus config) |
| J06 | External monitor refresh | `dots/.config/hypr/hyprland/general.lua` (monitor rule), its test | `highrr` measured harmful (would set the founder's HDMI to 1024x768@75); Jev D7 keep_preferred p=0.79; merged `d154e810a` (same-line why comment, `config ok`) |

Contended: `docs/navigation.md` (J01, J02, different paragraphs). Translation JSON files belong to nobody in this phase.
Moved out of Phase 0: the cursor theme. Adwaita is deliberate (`394153191`); it joins the Phase 3 identity decision.

## Phase 1 jobs

Measurements behind them: `/tmp/surfaces.tsv` (per-surface PSS, headless), `/tmp/qt_menus.txt` (Qt menus and launch times, live seat).

| Job | Title | Files owned | Wave | State |
| --- | --- | --- | --- | --- |
| J07 | Lazy surfaces | `panelFamilies/*`, new `modules/common/LazySurface.qml`, root files of launchpad, cheatsheet, polkit, screenTranslator, mediaControls, overview, sidebarRight, sessionScreen, tour, screensaver, sidebarLeft | A | next free slot |
| J09 | Qt on Wayland, xcb allowlist | `hypr/hyprland/env.lua`, `dots/.local/bin/koompi-launch`, rules keyed on Qt X11 classes, kdeconnectd override | A | running |
| J08 | Screen corners | `modules/koompi/screenCorners/*` | B | queued |
| J10 | Motion and Reduce Motion | `modules/common/Appearance.qml`, `hypr/hyprland/general.lua` (animations), `Config.qml` (one option), the appearance settings page | B | running |
| J11 | Settings in the running shell | `settings.qml`, `dots/.local/bin/koompi-settings`, `panelFamilies/KoompiFamily.qml` (one loader) | C, after J07 | queued, after J07 |
| J12 | Clipboard watcher; memd on demand | `hypr/hyprland/execs.lua` (wl-paste lines), `services/Cliphist.qml`, `services/MemoryService.qml` | C | running |
| J13 | Launch feedback | `modules/koompi/bar/ActiveWindow.qml`, new launch service, `koompi-launch` (one call) | D, after J09 | queued, after J09 |
| J16 | Refresh rate per monitor in Settings > Displays (F8, D7) | `modules/settings/DisplaysConfig.qml`, `dots/.local/bin/koompi-displays`, its test | C | running |
| J15 | `test_update_now_runs.sh` flakes under load | `tests/test_update_now_runs.sh` | after Phase 0 | queued |

Live seat damage from test harnesses, fixed 2026-10-07 (`e6d563717`): private buses auto-started the host's portals; xdph segfaulted (crash toasts on the founder's desktop) and a private document portal unmounted the live `/run/user/1000/doc`. The lead restarted `xdg-document-portal.service`.

Live seat findings outside any job: hot corners are dead because `fakeScreenRounding` is 0 there (J08 fixes the coupling; the live config is the founder's).

## Swarm, from 2026-10-07 (founder: "identify the leftover work and assign a subagent swarm")

Jev: `swarm_concurrency six_with_heavy_lock p=0.91 (jev-1.13.0)`. Six Sonnet workers at once; every nested compositor and full suite runs under `.work/tools/heavy.sh` (flock on `/tmp/koompi-heavy.lock`); the harness tools lock themselves. Specs J17-J32 and J36-J41 are written and reviewed.

| Job | Work | Depends on | State |
| --- | --- | --- | --- |
| J04 | Cheatsheet keys, rows, layout, 1366 clamp | | round 3 verified (panel clear of edges and bar); round 4 running: Elements tiles fit at 1366x768 (`J04_elements_fit fit_tiles_now p=1.0`), wheel labels corrected and wheel binds swapped to match Page Up/Down (`J04_wheel_direction swap_wheel_binds p=0.94`, Hyprland 0.56.2 `onAxisEvent`: positive delta is `mouse_down`), one modifier order, `[ ]` label, Utilities copy |
| J09 | Qt on Wayland, xcb allowlist | | running |
| J10 | Motion and Reduce Motion | | running; scope added: one owner for `animations:enabled` with Game mode, which resets the key and reads its own state from it (J32 extends the owner to blur) |
| J12 | Clipboard watcher, memd on demand | | running |
| J14 | Three identity mockups | | running |
| J16 | Refresh rate per monitor in Displays | | running |
| J07 | Lazy surfaces (the hub: Phase 2 and most Phase 3 build on it) | J04 for the cheatsheet root only | next free slot; converts the cheatsheet last, after J04 merges |
| J08 | Screen corners | | queued |
| J15 | `test_update_now_runs.sh` flake | | queued (holds the heavy lock for its load runs) |
| J11 | Settings in the running shell | J07 | queued |
| J13 | Launch feedback | J09 | queued |
| J17-J24 | Phase 2: Alt+Tab, dynamic workspaces, overview, Control Center, Notification Center, bar order and contrast, blended Search, one assistant | all J07; J19 after J18; J21 after J20; J22 after J20, J21, J13; J23 after J04; J24 merges after J23 | specs reviewed; their navigation.md section committed (`0009c9de8`); J21's kernel-toast sender filled in (KDE oom_notifier, "Linux Kernel") |
| J25-J32 | Phase 3: session menu, Settings names and search, launchpad folders, wallpaper gallery, widget overlay labels, single-window gaps, glyph tuning, Reduce Transparency | J25, J27: J07. J26: J11, and Jev on its proposed names before dispatch. J28, J29: none. J30: J09. J31, J32: J10 | specs reviewed by the lead |
| J33-J35 | Icon plate, koompi-icons, cursor | the founder's pick from J14 | waiting |
| J36-J38 | Phase 4: content index, appmenu bridge, Now drawer | J36 stage A: none, stage B: J23. J37: J09, J13. J38: J24, J07 | specs reviewed; J36 and J37 stop after a design note for Jev |
| J39 | Settings > Shortcuts key names | J04 | spec reviewed |
| J40 | Translations for the campaign's strings | everything else | spec reviewed; Khmer (`km_KH.json`) is a founder call, raised in its report |
| J41 | Crash watch announces only this session's crashes (nested tests run with their own `XDG_RUNTIME_DIR`) | | queued, small |

Founder-only: the pick from J14's mockups; authorising deployment to the live seat and the re-measurement; pushing `dev` and any merge to `main`.
