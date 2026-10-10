# J10: motion that feels instant, and a Reduce Motion switch (decision D6)

Audit: `docs/design/ux-audit-2026-10-07.md` sections 5 (F2) and 7 (D6: `fast_critically_damped`). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- `modules/common/Appearance.qml:280-310`: the duration ladder (snap 100 to slowest 650) and curves; `elementMove` is 500 ms on `expressiveDefaultSpatial` (`[0.38, 1.21, ...]`, overshoots), `elementMoveEnter` 400 ms, `elementMoveSmall` 350 ms on `expressiveFastSpatial` (`[0.42, 1.67, ...]`, overshoots hard), `clickBounce` 400 ms.
- `dots/.config/hypr/hyprland/general.lua:151-294`: Hyprland curves and leaves; windows in 300 ms popin, layers in 270 ms, workspaces 400 ms on `workspaceSlide`. Read the comments there on per-frame travel at 60 Hz before changing the workspace curve; the gotchas note warns that curve shape matters more than duration on a 60 Hz panel and never to split `workspacesIn`/`workspacesOut`.

## Do

1. **Ladder.** Panels and popups open in 200 ms and close in 150 ms; small moves 120 ms; no overshoot on any panel, popup, list or toggle (decelerate curves only). Keep overshoot available for motion a finger drives (workspace swipe release, drag-and-drop snap) if anything uses it. Retune the roles rather than every call site; then grep for hard-coded `duration:` numbers in `modules/` that bypass the ladder and bring the ones on panels and popups onto it.
2. **Hyprland.** Windows in/out ≤ 200 ms without popin overshoot; layers ≤ 200 ms in, ≤ 150 ms out; workspaces 300 ms. Measure peak per-frame travel at 60 Hz for the workspace curve you pick (the comment in `general.lua` shows how) and keep it at or under today's 292 px.
3. **Reduce Motion.** A setting (`appearance.reduceMotion`, default false) in Settings beside the other appearance switches: every spatial animation in the shell becomes a 100 ms crossfade or nothing, and Hyprland animations are turned off or set to fade. Hyprland's half: the shell writes nothing to the live compositor config; use the existing config-bridge path the shell already uses for user Hyprland options (find it: `services/HyprlandConfig.qml`), or say in the report why it cannot be done and stop there for that half.
4. **Test.** Assert the ladder through the public surface: a headless probe that loads `Appearance` and fails if any panel role exceeds 200 ms or any role's bezier y-control exceeds 1.0, and that `reduceMotion` collapses spatial roles. Lua: parse `general.lua` the way `tests/test_bar_keys.sh` parses keybinds and fail on any leaf over the budget.

## Acceptance

- Before/after table of every role and Hyprland leaf.
- Hyprshot screenshots mid-animation are not useful; instead record open-to-settled time for the right sidebar and search with the probe (timestamp on `visible` and on the animation's `running` going false) before and after.
- Full suite: no new failures.

## Out of scope

- Gesture tracking (Phase 2), Reduce Transparency (Phase 3).
