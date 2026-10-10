# J46 report

Commits (branch worktree-agent-a5fadae728d0b83a2, base 4c0e2db9a):
- 7b31be533 logind inhibited reads as possible: SessionWarnings, doctor and hibernation-setup stop calling the shell's own keep-awake a refusal; pin Battery's plugged-in to OnBattery
- 084d1c7b9 test: what MprisController shows after a browser's media ends, on a private bus with a stub player
- d5e031fdc MprisController: drop the playerctl stale-position workaround (separate last commit, droppable)

## Battery: was already fixed
Battery.qml:27 `isPluggedIn: ShellServices.power?.plugged_in`; shell-services/power/src/service.rs:197,222 `plugged_in: !on_battery` (UPower manager OnBattery). No `isCharging ||` / PendingCharge left. fully-charged uses (BatteryPopup.qml:26,50,59, PowerConfig.qml:27) are time-to-full text, not plugged-in. Guard added in tests/test_battery_health.sh (passes on dev by design).
Not addressed: the ~1.4 s OnBattery/State disagreement at replug (Battery.isCharging still comes from device state).

## Suspend / logind Can*: fixed
ShellServices does not publish session capabilities, so each shell reader was fixed in place. Readers of Can* found: SessionWarnings.qml:47 (CanHibernate, gates SessionScreen and the command tree), dots/.local/bin/koompi-health:193, dots/.local/share/koompi/libexec/hibernation-setup (new hibernate_possible(), used by the status line and exit code). All accept yes|challenge|inhibited; na/no/inhibitor-blocked stay refusals. Nothing in the shell asks CanSuspend any more.
Test: tests/test_hibernation_setup.sh (stub busctl answering inhibited; also extracts the real probe command from SessionWarnings.qml and runs it against yes/challenge/inhibited vs na/no/inhibitor-blocked). Fails on base: "FAIL: status with logind inhibited: exit 1, wanted 0".

## Media: evidence, removal committed separately
tests/test_mpris_phantom.sh: private bus (tests/private-bus.conf), headless KWin, stub plasma-browser-integration player, real MprisController sampled each second.
- ends (Paused, Position pinned at length): players=1 playing=false media=true, identical with or without the workaround (its timer only runs while Playing). A paused card for the finished clip stays, as for any paused player; not a Playing phantom.
- drops (bus name released): players=0 active=no media=false within 1 s. Clean.
- frozen (stays Playing, Position frozen; the case the workaround targets, never seen on the real host): with the workaround media=false stale=true at t=11 (~9 s). Without it that phantom would show forever. Removal loses protection only against behaviour not observed in the wild.
Removal commit d5e031fdc deletes the stale/playerctl/timer block and `&& !activePlayerStale`; the frozen scenario leaves the test. Drop that commit to keep the workaround (frozen scenario is in 084d1c7b9). Quickshell.Io import kept (IpcHandler needs it).

## Verification
Full suite: `135 passed, 4 skipped, 0 failed` (skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh). Run under heavy.sh with HYPRLAND_INSTANCE_SIGNATURE unset.
Not done: no screenshots (no visible UI change; MprisController probed headless by the test). TODO.md not edited (outside owned files); the three lines can close.
