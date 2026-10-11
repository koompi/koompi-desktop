# J51: the tour and the cheatsheet teach the tiling moves first

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Decided

Founder, 2026-10-10: KOOMPI is a tiling desktop, keyboard first. Lead, same day: the first things a new user learns are the moves that make tiling work, not mouse habits from a floating desktop.

## Evidence (dev)

- `modules/koompi/tour/steps.js:70-72`: the window step, "Moving and arranging windows", teaches `Super + drag`, which is a mouse habit. No step teaches focusing or moving a window by keyboard.
- The cheatsheet groups binds by the category before the colon in each bind's description (`cheatsheet-binds.js:69-70`), in order of first appearance. Check where Window sits among its 10 categories and what order its rows come in.
- The keys that make tiling work are already bound (`dots/.config/hypr/hyprland/keybinds.lua`):
  - focus: Super+arrows;
  - move: Super+Shift+arrows;
  - workspaces: Super+1..0, and Super+Alt+1..0 to send the window;
  - Alt+Tab back to the previous window, Alt+Shift+Tab to cycle this workspace;
  - Super+Tab for the overview;
  - float, fullscreen and close.

## Do

1. Tour (`steps.js`), the window step: teach by keyboard.
   - Focus with Super+arrows, move with Super+Shift+arrows, and send to a desk with Super+Alt+number.
   - Say in one short line that the mouse still works (Super+drag).
   - Keys must match `hyprctl binds`, as the file's header comment requires.
   - Do not touch the overview step (`:40-46`); J19 owns it and runs in parallel.
2. Tour: add one step on Alt+Tab ("back to the window you were just in, on any desk"), if it fits the tour's length rule. Otherwise fold it into the window step.
3. Cheatsheet: the Window category shows first, or as early as the layout allows, with its rows in the order a newcomer needs them:
   1. focus;
   2. move;
   3. send to a desk;
   4. Alt+Tab;
   5. float, fullscreen and close;
   6. resize.

   Do it through the existing ordering mechanism (category order, or `overrides`), not by reordering `keybinds.lua`. That file is at its line ratchet, and its order is shared.
4. Plain words, the tour's style: short sentences, no jargon ("tile", "workspace" only if the tour already uses them; it says "desk").

## Files owned

`modules/koompi/tour/steps.js` (everything except the overview step), `modules/koompi/cheatsheet/cheatsheet-binds.js` and the cheatsheet QML only where ordering lives, their tests, and the tour and cheatsheet lines of `docs/manual/*` and `docs/navigation.md`.

## Tests (fail on dev first)

- A test that the tour's window step lists the focus, move and send keys, and that every key in every step exists in the bound set. Use the existing tour or cheatsheet tests if one already reads `hyprctl binds` or the Lua declarations.
- A test that the cheatsheet's first rows of the Window category come in the order above.

## Acceptance

- Renders, dark, 1920x1200 and 1366x768: the tour's window step and the cheatsheet's first column. Say what you see.
- Full suite: no new failures.
