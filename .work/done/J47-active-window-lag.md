# J47: the bar's app identity follows the focused window

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Source: `~/.config/koompi/TODO.md`, "Global menu": the bar's app identity lags the focused window. Intermittent, predates the layout fix, unstuck by opening a new window. The founder asked for it on 2026-10-09.

## Where to look

- `modules/koompi/bar/ActiveWindow.qml:16-27`: the name and title come from `HyprlandData.activeWindow`, with `Hyprland.focusedMonitor` for the monitor check.
- `services/HyprlandData.qml`: how `activeWindow` is refreshed (events, polled `hyprctl`, debounce). A comment at `ActiveWindow.qml:17-19` already says the polled monitor reading lags.
- `shell-services/hyprland/` (Rust): if the shell reads Hyprland through it, the event handling there.

## Do

1. Reproduce it in the nested harness (`hyprshot.sh`): open two apps, move focus between them by keyboard, by click, across workspaces, by closing the focused window, and with a window that changes its title. Record the bar's app name against `hyprctl activewindow` inside the nested session after each step. Find the sequence that leaves it stale. `tests/wl_virtual_pointer.py` gives the nested session a pointer.
2. Fix the root cause, not a poll. Name it with file:line.
3. Test: the smallest nested test that fails on dev with the stale sequence and passes after.

## Overlap

J13 (launch feedback, unmerged, branch `worktree-agent-a7271d96bc79bf83f`) edits `ActiveWindow.qml` heavily. Put the fix in `HyprlandData.qml` or wherever the cause is. If the cause truly is in `ActiveWindow.qml`, keep that change as small as possible in its own commit and say so in the report; the lead lands it after J13.

## Files owned

`services/HyprlandData.qml`, `modules/koompi/bar/ActiveWindow.qml` (see Overlap), the Rust Hyprland crate if the cause is there, a new test.

## Acceptance

- The reproduction sequence and its before/after record.
- Before and after bar screenshots of the stale case.
- Full suite: no new failures.
