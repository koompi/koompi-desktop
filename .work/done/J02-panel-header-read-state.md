# J02: right panel header; a notification is read when it has been seen

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.5, rows R1 and R4. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- `modules/koompi/sidebarRight/SidebarRightContent.qml:455-477`: the header's title is `Up %1` (uptime) beside the distro icon.
- `:497-507`: a `restart_alt` button runs `hyprctl reload` and `Quickshell.reload(true)`, one click away in the panel people open most. Reload already lives in Search (`services/commandTree/Entries.qml:189`, "Reload desktop") and on `Ctrl+Super+R`.
- `GlobalStates.qml:40-45`: opening the right panel calls `Notifications.markAllRead()` immediately, so an accidental open clears the unread badge (`services/Notifications.qml:113,216,224`).

## Do

1. **Header.** Replace the uptime text with today's date in the user's locale, long form (e.g. "Wednesday 7 October"), from `services/DateTime.qml` if it already exposes one, else format it there. Keep the distro icon. Remove the reload button. Keep pin, settings and power.
2. **Read state.** Opening the panel still times out the popups at once (`timeoutAll`). `markAllRead` happens only after the panel has stayed open for 1 s; closing it sooner leaves the unread count as it was. Put the dwell where the open state lives (`GlobalStates.qml`), as a `Timer` that stops when the panel closes.
3. **Test.** A test that fails on `dev`: run the shell headless (`/home/userx/workspace/koompi/koompi-desktop/.work/tools/shellshot.sh` shows how: KWin virtual, private bus, `qs -p`), send a notification with `notify-send` inside that session, open and close the panel within 300 ms over IPC, and assert the unread count survived; then open for 1.5 s, close, and assert it is zero. Read the count through something observable: an IPC getter is acceptable if `services/Notifications.qml` gains one small read-only function on its existing `IpcHandler` (`notifications` target), or read it from a probe QML. Keep the test under 150 lines; skip cleanly with a `skip:` line when `kwin_wayland` or `qs` is missing.
4. **Docs.** `docs/navigation.md` paragraph beginning "This matters more for the right sidebar" describes the old zeroing; rewrite it to the new rule.

## Acceptance

- Headless screenshot of the open panel showing the new header.
- The test's output on `dev` (fails) and on your branch (passes).
- Full suite: no new failures.

## Out of scope

- Splitting the panel, moving controls, notification grouping (Phase 2). Uptime's new home in About (Phase 2/3).
