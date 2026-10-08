# J44: the conflict dialog never shows empty, and kded6's tray watcher stands aside instead of being killed

Found by the lead on 2026-10-08; not in the audit. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- The lead's nested run, `/home/userx/.tmp/lead-dolphin.WDYgiP/out/dolphin.png`: a "Kill conflicting programs?" window with an empty body and no buttons.
- `services/ConflictKiller.qml`: when `Config.ready` turns true, it runs `pidof kded6` (the tray conflict) and `pidof mako dunst` (the notification conflict). Either one opens `qs -p killDialog.qml`, unless `conflictKiller.autoKillTrays` or `autoKillNotificationDaemons` is set; then it runs a machine-wide `killall` instead.
- `killDialog.qml:177-184` has one row, for mako and dunst, and no row for kded6.
- `killDialog.qml:23-28` closes the window only when `conflictCount` changes to 0. When no row ever shows, the count never changes, so the window stays open, empty.
- The live seat, checked read-only on 2026-10-08:
  - kded6 runs with its `statusnotifierwatcher` module loaded.
  - The shell (`qs -c koompi`) owns `org.kde.StatusNotifierWatcher`.
  - So the next shell start there opens the empty window.
- `pidof` and `killall` see every process on the machine, so a nested test shell checks the host's processes.

## Decided

`J44_kded6_tray_conflict unload_watcher_module p=0.93 (jev-1.13.0)`: unload kded6's tray module, session-scoped, and drop kded6 from the dialog.

## Do

1. At shell start, unload kded6's tray module when it is there.
   - Check the shell's own session bus: is `org.kde.kded6` on it, and is `statusnotifierwatcher` in `loadedModules`?
   - If both, call `unloadModule("statusnotifierwatcher")` on `org.kde.kded6` at `/kded`, and log one line.
   - kded6 itself keeps running.
2. Drop kded6 from the conflict check.
   - Remove `pidof kded6`, its `killall`, and `autoKillTrays`.
   - Remove that key from `Config.qml` only if nothing else reads it; grep the settings pages first.
3. Leave the mako and dunst check and its row as they are.
4. `killDialog.qml` never shows empty.
   - It shows a row for each conflict that is running.
   - The process quits when no row is left, including when its own check finds none (the daemon may exit between the service's check and the dialog's).
5. Test, headless:
   - With a fake `pidof` that finds no mako or dunst, the dialog process quits by itself.
   - With a stub `org.kde.kded6` on the test's private bus (`dbus-run-session --config-file=tests/private-bus.conf`) that lists `statusnotifierwatcher`, the shell asks it to unload exactly that module, once.
   - With no kded6 on the bus, the shell calls nothing.
   - Each case fails on dev.
6. Update any of `docs/agents/*` or `docs/manual/*` that describes the conflict killer.

## Never

Call kded6, or anything else, on the founder's session bus. Every D-Bus call in your runs goes to a private bus. Unloading the module on the live seat is a deploy step, not yours.

## Acceptance

- The test fails on `dev` and passes on your branch.
- A nested-harness screenshot of a shell start shows no conflict window, on dev and on your branch, with the window listed or not in the run log.
- Full suite: no new failures.

## Out of scope

- How mako and dunst are detected or killed.
- Any other surface.
