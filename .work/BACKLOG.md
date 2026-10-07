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
| J04 | Cheatsheet key names and duplicate rows | `modules/koompi/cheatsheet/*`, `services/HyprlandKeybinds.qml`, `dots/.config/hypr/hyprland/keybinds*.lua` (descriptions only) | rounds 1-4 merged (`50015dba4`); round 5 running (see the swarm table). Round 3's clamp: Jev clamp_in_j04_now p=0.68. Real-binds check (founder approved, lead ran hyprshot on `a728ad11a`): 162 described binds, 0 raw key names, no QML errors, no crash |
| J05 | Settings: config-file banner and button | `settings.qml`, `modules/settings/QuickConfig.qml` | merged `aab3c5b5d` (lead: test bus config) |
| J06 | External monitor refresh | `dots/.config/hypr/hyprland/general.lua` (monitor rule), its test | `highrr` measured harmful (would set the founder's HDMI to 1024x768@75); Jev D7 keep_preferred p=0.79; merged `d154e810a` (same-line why comment, `config ok`) |

Contended: `docs/navigation.md` (J01, J02, different paragraphs). Translation JSON files belong to nobody in this phase.
Moved out of Phase 0: the cursor theme. Adwaita is deliberate (`394153191`); it joins the Phase 3 identity decision.

## Phase 1 jobs

Measurements behind them: `/tmp/surfaces.tsv` (per-surface PSS, headless), `/tmp/qt_menus.txt` (Qt menus and launch times, live seat).

| Job | Title | Files owned | Wave | State |
| --- | --- | --- | --- | --- |
| J07 | Lazy surfaces | `panelFamilies/*`, new `modules/common/LazySurface.qml`, root files of launchpad, cheatsheet, polkit, screenTranslator, mediaControls, overview, sidebarRight, sessionScreen, tour, screensaver, sidebarLeft | A | stopped at the base step; see the swarm table |
| J09 | Qt on Wayland, xcb allowlist | `hypr/hyprland/env.lua`, `dots/.local/bin/koompi-launch`, rules keyed on Qt X11 classes, kdeconnectd override | A | merged (`c78cbb1c0`) |
| J08 | Screen corners | `modules/koompi/screenCorners/*` | B | queued |
| J10 | Motion and Reduce Motion | `modules/common/Appearance.qml`, `hypr/hyprland/general.lua` (animations), `Config.qml` (one option), the appearance settings page | B | running |
| J11 | Settings in the running shell | `settings.qml`, `dots/.local/bin/koompi-settings`, `panelFamilies/KoompiFamily.qml` (one loader) | C, after J07 | queued, after J07 |
| J12 | Clipboard watcher; memd on demand | `hypr/hyprland/execs.lua` (wl-paste lines), `services/Cliphist.qml`, `services/MemoryService.qml` | C | round 1 merged (`f7554a90f`); round 2 running |
| J13 | Launch feedback | `modules/koompi/bar/ActiveWindow.qml`, new launch service, `koompi-launch` (one call) | D, after J09 | queued (J09 merged) |
| J16 | Refresh rate per monitor in Settings > Displays (F8, D7) | `modules/settings/DisplaysConfig.qml`, `dots/.local/bin/koompi-displays`, its test | C | running |
| J15 | `test_update_now_runs.sh` flakes under load | `tests/test_update_now_runs.sh` | after Phase 0 | queued |

Live seat damage from test harnesses, fixed 2026-10-07 (`e6d563717`): private buses auto-started the host's portals; xdph segfaulted (crash toasts on the founder's desktop) and a private document portal unmounted the live `/run/user/1000/doc`. The lead restarted `xdg-document-portal.service`.

Live seat findings outside any job: hot corners are dead because `fakeScreenRounding` is 0 there (J08 fixes the coupling; the live config is the founder's).

At the next authorised deploy: J42 replaces the hand-made `~/.config/systemd/user/hyprland-session.target`, and the founder's Chrome app and fcitx5 start at login for the first time; the kdeconnectd D-Bus override in `~/.local/share/dbus-1/services/org.kde.kdeconnect.service` is redundant after J09 and its comment is stale (founder's file, not the repo's).
The seat's `~/.config/autostart/fcitx5.desktop` (2026-07-26, `Exec=fcitx5`) duplicates the system `org.fcitx.Fcitx5.desktop`, so login would start two units for one daemon; propose hiding the user copy at deploy (the founder's file).
Its `discord.desktop` points at a missing binary and the generator skips it.
Login items take effect at the next login, not at deploy: the running target does not re-read `Wants=`.

## Swarm, from 2026-10-07 (founder: "identify the leftover work and assign a subagent swarm")

Jev: `swarm_concurrency six_with_heavy_lock p=0.91 (jev-1.13.0)`. Six Sonnet workers at once; every nested compositor and full suite runs under `.work/tools/heavy.sh` (flock on `/tmp/koompi-heavy.lock`); the harness tools lock themselves. Specs J17-J32 and J36-J43 are written and reviewed.
Queue: `queue_order breakage_then_hub p=0.71 (jev-1.13.0)`: J42, J07, J13, J15, J43, J41, J08, J28, J29.
Full suite on `dev` at `c78cbb1c0` (J09 merged, before J04 and J12), 2026-10-08: 112 passed, 4 skipped (the baseline's four), 0 failed.

| Job | Work | Depends on | State |
| --- | --- | --- | --- |
| J04 | Cheatsheet keys, rows, layout, 1366 clamp | | rounds 1-4 merged (`364c3e4fc`..`50015dba4`, 2026-10-08): round 4 fits the Elements tiles at 1366x768 (`J04_elements_fit fit_tiles_now p=1.0`), swaps the wheel binds to match Page Up/Down (`J04_wheel_direction swap_wheel_binds p=0.94`, Hyprland 0.56.2 `onAxisEvent`: positive delta is `mouse_down`), one modifier order, `[ ]`, plain copy; six tests pass on the rebased tree, six renders seen. The wheel has not been turned for real: a deploy check (Super + scroll down goes right). Round 5 running: the Copilot key reads "AI" alone (Hyprland sees `SUPER + SHIFT + code:201`), Kiri rows say what happens, and a migration rewrites shipped lines in the user-owned `custom/keybinds.lua` |
| J09 | Qt on Wayland, xcb allowlist | | merged (`cc16a7fad`..`c78cbb1c0`, 2026-10-08): round 2's comment pass and the bare-`wayland` rewrite (`J09_shell_launch_platform launch_rewrites_bare_wayland p=0.96`); five tests pass on the rebased tree under heavy.sh; the lead's commit fixes the audit's F4 line. Env vs argv for the four xcb apps is still with the founder (`J09_xcb_leak argv_platform p=0.51 ESCALATE: keep_env=0.47`); env stays meanwhile |
| J10 | Motion and Reduce Motion | | running; scope added: one owner for `animations:enabled` with Game mode, which resets the key and reads its own state from it (J32 extends the owner to blur) |
| J12 | Clipboard watcher, memd on demand | | round 1 merged (`ad1641612`, `f7554a90f`, 2026-10-08): a copy costs one `cliphist store`, the list refreshes only while something reads it, memd starts on first use; three tests pass on the rebased tree. Round 2 running: EasyEffects starts at login only if its toggle was left on (`J12_easyeffects_login remember_toggle p=1.0`; 31 MB resident + 30 MB swap on the seat, no presets), hyprsunset stays (`J12_hyprsunset_login leave p=0.79`), one-line test headers, `Ai.qml`'s stale `memoryWarmed`, the length allowlist row |
| J14 | Three identity mockups | | delivered 2026-10-08, sent to the founder (`.work/mockups/compare-{dark,light}.png`; README, six full frames and evidence beside them): A tinted glyph plates, B colour icon on a plate, C squircle-masked colour icons, all on WhiteSur-green. Waits for the founder's pick. The worker ran two `qml6` probes with the real HOME and runtime dir, and one aborted (the 23:09:09 crash toast); the lead then closed the harness gap it named (shellshot and measure_surfaces shared `/run/user/1000`) |
| J16 | Refresh rate per monitor in Displays | | round 1 merged (`5027d05ae`); round 2 queued: rules keyed by display description and kept while unplugged (`J16_persist_scope desc_keyed_merge p=0.99`), whole-hertz labels unless ambiguous (`J16_rate_labels round_unless_ambiguous p=0.68`), keep-or-revert countdown (`J16_confirm_revert confirm_or_revert p=1.0`; a deploy blocker for the rate row), errors on the page, CLI usage, comments. Its queue position escalated (`J16_round2_position after_j42 p=0.53 ESCALATE: end_of_queue=0.4`); end of the queue until the founder says otherwise |
| J07 | Lazy surfaces (the hub: Phase 2 and most Phase 3 build on it) | J04 for the cheatsheet root only | dispatched 2026-10-08, stopped at contract step 4: the worktree-isolation check refused the compound `checkout -B` ("too complex to verify that it stays inside the worktree"), no edits; worktree auto-cleaned. Waits for the founder's call on the base step. Converts the cheatsheet last, after J04 merges |
| J08 | Screen corners | | queued |
| J15 | `test_update_now_runs.sh` flake, and the KWin start-up wedge J09 found (nested Hyprland with no output) | | queued (holds the heavy lock for its load runs); owns the nested start-up in the three nested tests and `hyprshot.sh` |
| J11 | Settings in the running shell | J07 | queued |
| J13 | Launch feedback | J09 (merged) | queued, needs a new worker; adds the empty-desktop identity (`J13_empty_desktop_identity desktop_only p=0.91`) and the nested "Desktop" identity question |
| J17-J24 | Phase 2: Alt+Tab, dynamic workspaces, overview, Control Center, Notification Center, bar order and contrast, blended Search, one assistant | all J07; J19 after J18; J21 after J20; J22 after J20, J21, J13; J23 after J04; J24 merges after J23 | specs reviewed; their navigation.md section committed (`0009c9de8`); J21's kernel-toast sender filled in (KDE oom_notifier, "Linux Kernel") |
| J25-J32 | Phase 3: session menu, Settings names and search, launchpad folders, wallpaper gallery, widget overlay labels, single-window gaps, glyph tuning, Reduce Transparency | J25, J27: J07. J26: J11, and Jev on its proposed names before dispatch. J28, J29: none. J30: J09. J31, J32: J10 | specs reviewed by the lead |
| J33-J35 | Icon plate, koompi-icons, cursor | the founder's pick from J14 | waiting |
| J36-J38 | Phase 4: content index, appmenu bridge, Now drawer | J36 stage A: none, stage B: J23. J37: J09, J13. J38: J24, J07 | specs reviewed; J36 and J37 stop after a design note for Jev |
| J39 | Settings > Shortcuts key names | J04 | spec reviewed |
| J40 | Translations for the campaign's strings | everything else | spec reviewed; Khmer (`km_KH.json`) is a founder call, raised in its report |
| J41 | Crash watch announces only this session's crashes (nested tests run with their own `XDG_RUNTIME_DIR`); test shells stay off the session's polkit agent (J12 found every test shell registers on the system bus) | | queued, needs a new worker |
| J42 | The session target ships with KOOMPI and login items start: `xdg-desktop-autostart.target` refuses the manual start in `execs.lua:33`, and `hyprland-session.target` exists only on the founder's host, so a fresh install gets no `graphical-session.target` (no hypridle, crash watch, portals) and fcitx5 never starts anywhere | | round 1 stopped at contract step 4 (the classifier refused `checkout -B` as irreversible local destruction), nothing committed, worktree auto-cleaned; its findings and round 2 are in the job file: PKGBUILD comment only, KDE Connect hidden (`J42_kdeconnect_login hide_kdeconnect p=0.73`), a migration for package-route users. Waits for the founder's call on the base step. `J42_autostart_scope autostart_hide_duplicates p=0.98` |
| J43 | Restored and pinned apps match the running app by desktop entry (J09 open points 2, 3) | J09 (merged) | queued, needs a new worker |

Founder-only: how new workers get onto `dev` (the permission checks refused contract step 4 for J42 and J07, asked 2026-10-08); the four xcb apps' children (`J09_xcb_leak` ESCALATE, asked 2026-10-07); the pick from J14's mockups; authorising deployment to the live seat and the re-measurement; pushing `dev` and any merge to `main`.

## State at the usage limit (2026-10-08)

- J10 (motion, Reduce Motion, one owner for held Hyprland options): reviewed, renders seen, rebased onto `dev` (branch tip `7b08fbe79`); its tests were queued under heavy.sh (log `/home/userx/.tmp/j10-verify.log`); not merged. Round 2 to send after merge:
  1. `HyprlandConfig.apply` fails loudly: a `Process` with argv (no `bash -c`), log a non-zero exit with stderr, and re-read the overrides file on failure so `applied` matches it.
  2. `scripts/hyprland/hyprconfigurator.py` imports only the stdlib: shebang to `#!/usr/bin/env python3` (the venv shebang is the silent-failure source), and line 50's `'\{'` to `r'\{'`.
  3. Updates keep `hyprland/shellOverrides/` (Game mode and the anti-flashbang shader live only there): exclude it from the `SYNC_DIRS` mirror and from `koompi-migrate`'s hyprland pair, seed the stub only when absent; test both routes.
  4. Reduce Motion reaches the waffle family's `Looks.transition` tokens (give the Timers that borrow rungs their own intervals).
- For J07: `SidebarRight.qml:24-34`, a drawer requested over IPC on a closed sidebar opens without its page (J10, old tree too).
- For J20: in a headless shell the Internet tile reads "On" with the wifi-off glyph and Power Profile "On" with an X; check the tiles when their service is absent.
- Lead fixes committed after their run passed: the AI remote probe in a headless KWin and the `/run/user` check (`tests/`), and `hyprshot.sh` copying `hyprland/` (a nested write landed in the copy; the repo stayed clean).
- J10's queued tests then passed on its rebased tree (`/home/userx/.tmp/j10-verify.log`): merge it first, then send round 2.
- J04 round 5 handed back, not yet verified: four commits on `117dc671e` (`000c822e2` AI key as itself, `f83649a16` docs, `9f895fbae` Kiri wording, `7dbc233d4` migration `sdata/migrations/1791394815-custom-keybind-descriptions.sh` with its test); worker's suite 117 passed, 4 skipped, 0 failed; renders `.work/shots/J04-r5-*`. The migration also rewrites the first release's `$HOME/.local/bin/kiri` lines (the last four reword pairs). Verify, rebase, merge.
- Still running at the limit: J12 round 2 (`dev`-based worktree).
