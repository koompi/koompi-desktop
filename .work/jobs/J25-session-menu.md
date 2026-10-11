# J25: the session menu says what each button does, and shutting down can be undone

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.9. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: `modules/koompi/sessionScreen/SessionScreen.qml` (content only, after J07), `modules/koompi/sessionScreen/SessionActionButton.qml`, new files in `modules/koompi/sessionScreen/`, a new `tests/test_session_menu.sh`, the session menu lines of `docs/navigation.md` and `docs/manual/*`.
Depends on: J07 (lazy surfaces) merged; it rewrites `SessionScreen.qml`'s `Scope`/`PanelWindow` wrapping. Rebase onto it and change only what is inside the window.

## Evidence (on `dev`)

- `modules/koompi/sessionScreen/SessionScreen.qml:102-235`: a 4-column `GridLayout` of eight `SessionActionButton`s (Lock, Sleep, Logout, Task Manager, Hibernate when available, Shutdown, Reboot, Reboot to firmware settings).
- `SessionActionButton.qml:45-56`: each tile draws only its glyph (45 px); the name is a hover tooltip. `SessionScreen.qml:238-241`: the focused tile's name shows once, under the grid, in `DescriptionLabel`. `:98` puts two lines of keyboard instructions above the grid.
- `SessionScreen.qml:189-219` and `modules/common/functions/Session.qml:44-57`: Shutdown and Reboot call `Session.poweroff()` / `Session.reboot()` at once. `closeAllWindows()` kills every window, then `systemctl poweroff`. One misclick ends the session with no way back.
- `Session.poweroff()` is also called by the lock screen (`modules/common/panels/lock/LockScreen.qml:103`) and the waffle family (`modules/waffle/...`). Those callers keep today's behaviour.

## Do

1. **Labels.** Every tile shows its name under the glyph at all times. Use plain words: "Lock", "Sleep", "Log out", "Restart", "Shut down", and "Hibernate" when shown. The tooltip and the under-grid `DescriptionLabel` become redundant; remove them. Keep the keyboard focus ring.
2. **Two rows.** The primary row is Lock, Sleep, (Hibernate), Log out, Restart, Shut down. A smaller secondary row is Task manager and Firmware setup ("Restart to firmware setup"). Arrow-key navigation still reaches every tile in reading order, and Enter activates.
3. **Countdown, not a second dialog.** Shut down and Restart (and Restart to firmware setup) do not act immediately. The menu shows "Shutting down in 10 seconds" (or "Restarting…"), a progress ring or bar, a Cancel button that has focus, and a "Shut down now" / "Restart now" button. Esc, Cancel or clicking outside cancels. When it reaches zero it calls the same `Session` function as today. The countdown lives in the session menu, not in `Session.qml`, so the lock screen and waffle callers are unchanged. Lock, Sleep and Log out stay immediate.
4. The package-manager and download warnings (`:250-270`) stay visible during a countdown, because that is when they matter most.
5. Remove the two-line instruction text (`:98`). Labels and a focused default make it unnecessary. If something must stay for keyboard users, use one short line.

## Tests (each fails on `dev` first)

- A headless probe (`shellshot.sh`, or a `qs -p` probe on a private bus with `Session` shimmed so nothing powers off) that:
  - opens the menu and asserts every action tile has a visible text label;
  - presses Shut down and asserts nothing was called for 9 s and a countdown with focused Cancel is shown;
  - presses Esc and asserts nothing was called at all;
  - presses Shut down then "Shut down now" and asserts exactly one call.
- Shim `systemctl`, `loginctl`, `reboot` and `kill` on PATH to record argv. Never let a test reach the real ones.

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light: the idle menu and a countdown in progress. Look at them in full; nothing clipped, labels readable, the countdown readable at a glance.
- Test before/after output. Full suite: 0 failed (`test_update_now_runs.sh` is the known J15 flake).

## Out of scope

- The lock screen, the greeter, the waffle family's session screen. `Session.qml`'s commands.
