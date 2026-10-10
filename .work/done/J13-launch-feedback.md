# J13: something answers the moment you launch an app

Audit: `docs/design/ux-audit-2026-10-07.md` sections 3.11 and 5 (F10). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first. Runs after J09 (both touch `koompi-launch`).

## Evidence

- Between Enter in Search (or a key) and the first window there is 0.3 to 1.5 s with nothing on screen (lead's measurements in J09's file).
- `modules/koompi/bar/ActiveWindow.qml:16-29,152-161` shows the focused window's app name and title on the left of the bar.
- `dots/.local/bin/koompi-launch` is the single path for keys, Search, Launchpad and dock launches.

## Do

1. A launch registers itself with the shell: from shell surfaces directly (Search, Launchpad, dock call a function on a small service), and from `koompi-launch` for key binds (an IPC call in the background, never blocking the launch, failing silently only if the shell is not running, logged otherwise).
2. While a launch is pending, the bar's app identity shows the launching app's icon and name with a subtle pulse ("Opening Dolphin"), from the moment of launch until a window of that app maps (match by desktop-entry id, `StartupWMClass`, class or pid) or 8 s pass. Then it shows the real focused window as today.
3. Reduce Motion (J10) turns the pulse into a static dim state.
4. **Test.** Nested Hyprland harness: launch a slow app (a script that sleeps 1.5 s then execs a window client) through `koompi-launch`; screenshot at 0.3 s shows "Opening …" in the bar; at 3 s the real window identity. Plus a unit-level test of the matching rule.

## Acceptance

- The two screenshots; test before/after; full suite: no new failures.

## Out of scope

- A dock (off by default) beyond calling the same service if it is enabled.

## Lead notes at dispatch (2026-10-07)

- J09 merges before you start. Its `koompi-launch` picks each Qt app's platform, and the class of one app differs by platform (`dolphin` on xcb, `org.kde.dolphin` on Wayland; the table is in J09's report). Match on the desktop entry id, not the raw class.
- Decided: `J13_empty_desktop_identity desktop_only p=0.91 (jev-1.13.0)`.
  - With no window, the identity reads "Desktop" alone, with no second line.
  - Today it reads "Desktop" over "Workspace N", which elides to "Works…": the block is sized to the app name (`ActiveWindow.qml:72-75`).
  - The centre of the bar already shows the workspace.
  - Assert it in your test.
- In J09's nested renders (`/home/userx/.tmp/J09-handoff/evidence/dolphin-xcb.png`, `kdeconnect-wayland.png`), the identity read "Desktop" while Dolphin was focused and its menus were in the bar.
  - Find out why before you build on it: `HyprlandData.activeWindow` unset in a nested session, a harness timing, or a real defect.
  - Your "real window identity" screenshot depends on it.
  - Name the cause and fix it if it is the shell's.
