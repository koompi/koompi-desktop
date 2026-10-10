# J30: one tiled window fills its space, with no strip of wallpaper around it

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.11 (Window frame). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: the workspace-rules block of `dots/.config/hypr/hyprland/rules.lua` (`:138-144`), a new `tests/test_single_window_gaps.sh`, the frame lines of `docs/manual/*` if any.
Depends on: J09 merged. It edits other parts of `rules.lua` (Qt/Telegram class rules, `:73-77`).
Does not touch `general.lua`. It stays at its 371-line ratchet, and `gaps_out` keeps its value for two or more windows.
Shared with: `modules/common/Appearance.qml:441` (`hyprlandGapsOut: 5`) is read by the bar and popups. Leave it; the bar does not move.

## Evidence (on `dev`)

- `dots/.config/hypr/hyprland/general.lua:79-82`: `gaps_in = 4`, `gaps_out = 5`. With a single tiled window, a 5 px strip of a busy wallpaper surrounds it and reads as a flickering border (audit: edge pixels sampled from `#99CEC5` to `#FFFFFF`).
- `rules.lua:138-144`: workspace rules already set `gaps_out` per special workspace with `hl.workspace_rule({ workspace = ..., gaps_out = ... })`. `/usr/share/hypr/stubs/hl.meta.lua:603-612` types `HL.WorkspaceRuleSpec` with `gaps_out`/`gaps_in`.

## Do

1. A workspace rule for workspaces with exactly one tiled, visible window: no outer and no inner gap, and no border on that window. Use Hyprland's workspace selector for "one tiled visible window", and confirm the selector syntax this Hyprland accepts from its stubs and source on this machine, not from memory. Two or more windows keep today's gaps. Floating windows and special workspaces are unaffected.
2. Fullscreen and maximised behave as today.
3. Prove it loads: `Hyprland --verify-config` on the staged config prints `config ok` (the J06 worker's `verify-full.sh` in `.work/J06-evidence/` shows how).

## Tests (fail on `dev` first)

- A nested-Hyprland repo test (the shape of `tests/test_search_window_focus.sh`: own HOME, runtime dir, private bus, skips cleanly without the tools):
  - open one terminal window: its `hyprctl clients -j` geometry touches the work area's edges (gap 0) and its border is 0;
  - open a second: both windows are inset by today's gaps;
  - close one: the remaining one fills again.

## Acceptance

- hyprshot renders at 1920x1200 and 1366x768 (dark and light wallpaper) with one tiled window and with two. Look at the edges at full size.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Rounding, shadows, the bar's own gap, gaps with two or more windows.
