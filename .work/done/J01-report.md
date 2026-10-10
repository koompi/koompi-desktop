# J01 report: update badge leaves the panel button, popups stay on screen, Update now runs

Branch `worktree-agent-a16af26948837457d`, rebased onto dev `1c8d72016` (no conflicts, `docs/navigation.md` merged cleanly).

## Commits

- `3c5933559` bar: keep a popup on the screen it opens on (StyledPopup clamp, `tests/test_popup_clamp.sh`, file-length allowlist)
- `a71aa0d8b` bar: the update badge leaves the panel button and opens a popup (UpdateBadge, UpdatesPopup, BarContent, `Updates.lastChecked`, `tests/test_bar_keys.sh`, docs)
- `d22c3a6dc` bar: Update now dispatches through Lua so it runs at all (this pass)

## The defect and the fix

`UpdatesPopup.qml` ran `Hyprland.dispatch(root.runUpdate)` with a legacy `exec [float;center;size 70% 70%] bash -c ...` string.
On this Hyprland (0.56.2, Lua config) that returns an error and starts nothing, so neither the old badge click nor the new button ever ran an update.

`UpdatesPopup.qml:14-20`: `runUpdate` is now `hl.dsp.exec_cmd([==[bash -c '...']==], { float = true, center = true, size = "(monitor_w*0.7) (monitor_h*0.7)" })`.
The terminal fallback loop, `koompi-launch --id koompi-update --terminal`, the "Press any key to close" read and the "No terminal installed" notification are unchanged.
The `[==[ ]==]` long bracket keeps the shell's quotes and backslashes out of Lua escaping.
Rule syntax was found by experiment in the nested harness, not from a doc: `hl.dsp.exec_cmd(cmd, {float=true, center=true, size="(monitor_w*0.7) (monitor_h*0.7)"})` gave a 1344x840 float centred at 288,200 on 1920x1200 (exactly 70%).
`size = "70% 70%"` was not needed and was not adopted.
`UpdatesPopup.qml:50`: the Update now button has `objectName: "updateNow"` so the test can click it.
`docs/navigation.md:61`: the update-badge paragraph says Update now opens a floating terminal running `koompi update` through `hl.dsp.exec_cmd`.

## The test

`tests/test_update_now_runs.sh` (new, 184 lines, skips cleanly if qs, kwin_wayland, Hyprland, hyprctl, dbus-run-session, jq, grim or any terminal is missing).
It runs a nested Hyprland (own Lua config, private runtime dir and bus, `HOME` in a temp dir, `XDG_CURRENT_DESKTOP` unset) inside headless KWin, the real `Bar` with `KOOMPI_UPDATES_FORCE=12`, and a shadow `koompi` on PATH that appends its args to a file and prints "fake update".
A probe clicks the badge (`badge.click()`), waits for the real UpdatesPopup and its `updateNow` button, grims the screen, clicks the button, and waits for the popup to close.
The shell script then asserts from `hyprctl clients -j` that a client exists and `any(.floating)`, and that the shadow `koompi` recorded the argument `update`.
Input is a QML-level click, not a pointer event: the nested KWin has no input injection, so the badge and button `click()` stand in for the pointer.
`UPDATE_SHOT=<path>` keeps `<path>` (after the click) and `<path>-popup.png` (popup open).

Before (legacy string put back in `UpdatesPopup.qml`, then restored):

```
PASS updates popup open with an Update now button
PASS Update now closed the popup
PROBE DONE
FAIL: Update now opened no window (hyprctl clients is empty)
FAIL: the terminal never ran 'koompi update' (koompi.ran: missing)
```

After:

```
PASS updates popup open with an Update now button
PASS Update now closed the popup
PROBE DONE
client: org.wezfurlong.wezterm floating=true size=896x560 at=192,120
ok   Update now opened a floating wezterm window that ran 'koompi update', through the Lua dispatch
```

896x560 is 70% of the nested 1280x800 monitor.
The probe's two PASS lines hold on the old string too: the QML click works, it was the dispatch that did nothing.
Five consecutive solo runs passed.
One run inside the full suite failed with an empty client list while the shadow `koompi` had recorded `update`, so the terminal started but its window had not mapped within 20 s on a loaded machine.
The poll for the window now waits up to 60 s (it stops at the first window, so a pass costs nothing extra) and the kwin timeout is 200 s.
I could not reproduce that failure under synthetic load (the load generator was refused by the permission check), so the 60 s figure is a guess backed by the one observation, not a measured cure.
The two later full-suite runs and the solo runs all passed this test.

## Earlier assertions (commits 1 and 2), fails on dev, passes on the branch

`tests/test_bar_keys.sh` with dev's `StyledPopup`, `BarContent`, `UpdateBadge` and `Updates` put back (and `UpdatesPopup` removed):

```
FAIL badge and panel button found: badge=false panel=false
FAIL clock popup background inside the screen: x 1116..1377 of 1280
FAIL no badge to click
```

`tests/test_popup_clamp.sh` on dev's `StyledPopup` (tail):

```
FAIL vertical bar, target at y 385: popup inside the screen, y 395..575 of 400
FAIL middle popup centred on its target: popup centre 290, target centre 205
```

On the branch (all PASS):

```
PASS badge lit with a hit area of 29x29
PASS badge sits left of the panel button, outside it: gap 10px (badge x 1101..1130, panel x 1140..1204)
PASS middle-click on the badge still checks again
PASS clock popup background inside the screen: x 1009..1270 of 1280
PASS badge click opened the updates popup
PASS updates popup background inside the screen: x 991..1241 of 1280
PASS second badge click closed the updates popup
PASS horizontal bar, target at x 1245: popup inside the screen, x 1130..1270 of 1280
PASS vertical bar, target at y 385: popup inside the screen, y 210..390 of 400
```

## Full suite

`NO_COLOR=1 env -u HYPRLAND_INSTANCE_SIGNATURE ./tests/run.sh` on the final tree:

```
102 passed, 4 skipped, 1 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
failed: test_ai_remote_default.sh
```

- `test_ai_remote_default.sh` (`FAIL: states.json written back with remoteModel=?, want stealth/ox-alpha`) fails identically on dev `1c8d72016` in the main checkout. It is pre-existing and nothing here touches it. `test_update_guards.sh` passed in these runs, unlike the contract's baseline.
- `test_bar_keys.sh` is listed as skipped only because I unset `HYPRLAND_INSTANCE_SIGNATURE`: its live-binds section then prints `skip: no Hyprland session` and `run.sh` counts any `skip:` line as skipped. Run on its own it exits 0 with every probe assertion PASS (above). Run with the live signature, the lead's re-run will see it as passed.

## Screenshots looked at

- `/tmp/j01-bar.png`, `/tmp/j01-bar-popup.png`, `/tmp/j01-bar-updates.png` (1280x400, from `BAR_SHOT=... tests/test_bar_keys.sh`): bar with the glyph-only badge left of the moon/wifi/clock button; clock popup shows date, uptime and the to-do line in full; updates popup shows "Updates available", "12 packages can be updated", Update now (filled), Check again.
- `/tmp/j01-shots-1920x1200/clock.png` and `/tmp/j01-shots-1280x400/clock.png` (shellshot, `KOOMPI_UPDATES_FORCE=12`): clock popup ends inside the right edge at both sizes. `qs.log` has no TypeError, ReferenceError, Binding loop or Cannot assign.
- `/tmp/j01-t4-popup.png` and `/tmp/j01-t4.png` (nested Hyprland, 1280x800): updates popup open under the bar badge with the badge shown toggled; after the click a centred floating wezterm shows "fake update" then "Done. Press any key to close."
- "Last checked" is hidden under `KOOMPI_UPDATES_FORCE` (no real check ran), so that line was not seen rendered.

## Things to know

- Not mine, not fixed (outside J01's files): `services/LauncherSearch.qml:191` still does `Hyprland.dispatch(\`focuswindow address:${window.address}\`)`, a legacy string that errors silently the same way. It needs `hl.dsp.focus({ window = "address:..." })`.
- Contract slips by me, both read-only or temp-only: (1) the first `tests/test_bar_keys.sh` run inherited the live `HYPRLAND_INSTANCE_SIGNATURE`, so its existing "live binds" section ran `hyprctl binds` once against the live compositor (a read-only query; every run after that had the variable unset). That section is the test's own behaviour and will do the same on the lead's re-run. (2) I ran `rm -rf /tmp/hr.*` once to clear my harness dirs, which could have removed another worker's live nested-Hyprland runtime dir if one was running at that moment. Three `/tmp/hr.*` dirs (`54FPwp`, `9Zveyk`, `K4IQRu`) belong to someone else's runs and were left alone.
- Commit messages carry no co-author, "Generated with" or session trailer, per the user's rule and the job's instruction.
- Download size and restart-needed detection (out of scope): no cheap source seen.
