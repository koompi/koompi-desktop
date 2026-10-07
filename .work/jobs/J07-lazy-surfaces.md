# J07: surfaces exist only while someone is using them

Audit: `docs/design/ux-audit-2026-10-07.md` section 5, F1. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence (lead's measurement, `.work/tools/measure_surfaces.sh`, headless, one run each, ±10 MB noise)

Full shell 425 to 435 MB PSS. With only Bar, Background, NotificationPopup, OnScreenDisplay and Lock loaded: 233 MB.
Memory freed by removing one loader: Launchpad 67, Cheatsheet 45, ScreenCorners 44 (J08 owns it, not you), Polkit 26, ScreenTranslator 18, MediaControls 16, Overview 15, SidebarRight 15, SessionScreen 14, Tour 13, Screensaver 11, SidebarLeft 11 MB; the rest under 7.

The shape that costs it, e.g. `modules/koompi/launchpad/Launchpad.qml:9-90`: a `Scope` holding an `IpcHandler`, `GlobalShortcut`s and a `PanelWindow { visible: GlobalStates.launchpadOpen }` that exists all session. `panelFamilies/PanelLoader.qml:8` gates every surface only on `Config.ready`.

## Do

1. **One mechanism.** A small reusable component in `modules/common/` (for example `LazySurface.qml`, a `LazyLoader`) that is active while its `open` flag is true and for `keepWarm` ms after it turns false (default 120000), then releases. It must survive the flag flapping (open, close, open inside the grace window keeps the same instance).
2. **Convert** every surface measured above at 11 MB or more, except ScreenCorners: the `PanelWindow` (or `Variants` of them) moves inside the lazy component; `IpcHandler` and `GlobalShortcut` stay in the always-loaded `Scope`, so keys and IPC still work when the window is gone. Anything else in the `Scope` that the window reads (state, models) stays where it is unless it is the cost.
   Watch for: code that refers to the window by `id` from outside it (IPC handlers focusing it, `GlobalFocusGrab` registration), `keepRightSidebarLoaded` / `Persistent.states.sidebar.pinned` for the right sidebar (a pinned panel is open, so it stays loaded), the left sidebar's detach mode, and surfaces with their own inner `Loader` already (do not double-wrap; remove the inner one if the outer makes it redundant).
3. **No surface may lose a feature.** Each converted surface still opens by its key, its IPC, its gesture and its bar target, and closes by every path it closed by before.
4. **Measure, do not predict.** Re-run `/home/userx/workspace/koompi/koompi-desktop/.work/tools/measure_surfaces.sh <worktree>/dots/.config/quickshell/koompi /tmp/j07.tsv` before and after (it takes about 15 minutes for all variants; the `full` line is what matters, and `resident-only`). Report both tables.
5. **First open stays fast.** In the nested Hyprland harness (`hyprshot.sh`), time from IPC open to the layer being listed by `hyprctl layers -j` for three cold opens of Launchpad, Overview, SidebarRight and Cheatsheet. The bar is 100 ms per surface on this machine; report each number.
6. **Test.** A test that fails when a converted surface's window is instantiated with its flag false, measured from a headless probe (count `PanelWindow`s or windows mapped), not by grepping QML. Keep it under 150 lines.
7. **Docs.** `docs/navigation.md` Panel contract section: one paragraph on the rule (closed surfaces do not exist; shortcuts and IPC live outside the window).

## Acceptance

- Full-shell PSS after ≤ 300 MB in the same headless measurement (before: 425 to 435).
- First-open timings, every surface ≤ 100 ms, or a named reason for any that is not.
- Hyprshot screenshots of each converted surface opened by IPC, after the change.
- Full suite: no new failures.

## Out of scope

- ScreenCorners (J08), services and singletons, the bar.

## Lead notes at dispatch (2026-10-07)

- J04 is in its fourth round and edits the cheatsheet: `Cheatsheet.qml` (the panel clamp, `e48066fdd`) and the Elements page. Convert the cheatsheet last. Before you do, rebase onto `dev` once J04 has merged; the lead tells you when. If J04 has not merged by the time everything else is done, hand back without the cheatsheet and say so.
- J10 (motion) is running and owns `Appearance.qml`, `general.lua`'s animations and Game mode's `animations:enabled`. Do not edit them; read the merged versions if you rebase after it lands.
- Phase 2 (J17-J24) builds every new surface inside your component, and its specs tell those workers to read your merged `LazySurface.qml` and one converted surface first. Keep the component's API small and documented in its header comment: the open flag, `keepWarm`, and how a surface reaches its window from outside.
- Every nested compositor and full-suite run goes through `.work/tools/heavy.sh` (the contract). `measure_surfaces.sh` and `hyprshot.sh` lock themselves.

## Lead notes (2026-10-08)

- J04 has merged (`300f31357`): convert the cheatsheet with the rest, on a `dev` that has it.
- J10 has merged (`e4fcae117`): read its `Appearance.qml` roles for any open or close you add.
- `SidebarRight.qml:24-34`: a drawer requested over IPC on a closed sidebar opens without its page. `onLoaded` applies and clears `pendingDrawer`, then `showDrawer` sets it back to "". It predates you, but you rework this loading, so fix it and cover it in your test.
