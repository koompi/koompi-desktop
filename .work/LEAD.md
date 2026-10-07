# Lead resume notes: UX 10x campaign

Saved 2026-10-07 before a reboot. Resume by reading this file, then `BACKLOG.md`, then `jobs/CONTRACT.md`.

## The ask

Founder, 2026-10-07: "start phase 0. Opus advisor and sonnet code. once done phase one. don't stop. continue to the next phases until done."
Plan: `docs/design/ux-audit-2026-10-07.md` (committed `9635a8657`). Lead is Opus and verifies; workers are Sonnet, one job each, two at a time, `isolation: worktree`.
Decisions: Jev lines D2-D6 in the plan's section 7; D1 (Qt) chosen by the founder: staged, xcb allowlist now, appmenu bridge in Phase 4.

## State on `dev`

- `9635a8657` the plan.
- `6855cde10`, `6533e4863` J02 (panel header shows the date, reload button gone; unread clears only after 1 s open). Verified by the lead: `tests/test_notification_read_state.sh` passes, screenshots `shots/j02-shots-badge/strip.png`, `shots/j02-shots-after/crop2.png`. Full suite on the merged tree not yet run by the lead (worker reported 102 passed, 3 skipped, 0 failed).
- `dev` is not pushed. Nothing has been deployed to the live seat; deploying needs the founder's word.

## Jobs in flight when stopped

| Job | Worktree | Branch | State |
| --- | --- | --- | --- |
| J01 | `.claude/worktrees/agent-a16af26948837457d` | `worktree-agent-a16af26948837457d` | Both commits in (`f5d430db1` popup clamp, `f5a81e150` badge leaves the panel button, opens a popup). Stopped before its full-suite run and report. Lead: review diff, run `tests/test_bar_keys.sh` and the suite, look at `tmp-backup/j01-*` shots, merge. |
| J03 | `.claude/worktrees/agent-a518972fffa5073ac` | `worktree-agent-a518972fffa5073ac` | Crash toast (`3459a75f3`) and Recent heading (`cb4d3b1d4`) committed. Media empty state uncommitted in the worktree (`MediaControls.qml` modified, `tests/test_media_empty_state.sh` untracked). Re-dispatch a Sonnet worker into that worktree to finish item 2, its test, the suite and the report. |

Worker scratch from `/tmp` (lost on reboot) is copied to `tmp-backup/`; measurements to `data/`; the audit's live screenshots to `shots/`.

## Next, in order

1. Finish Phase 0: verify and merge J01; finish J03; dispatch J04 + J05, then J06. One full `NO_COLOR=1 ./tests/run.sh` on `dev` after the merges; baseline is in `data/koompi-baseline.txt` (101 passed, 2 skipped, 1 failed `test_update_guards.sh`, J06 owns it).
2. Small lead fixes on `dev` after J02: `tests/file-length-allow.txt` row for `SidebarRightContent.qml` (532 listed, now 522); `docs/navigation.md` still says the right panel has "two tabs" (the code has sections and a drawer; tabs went in `cd507b835` and later left).
3. Phase 1: jobs J07-J13 are written (`jobs/`), waves in `BACKLOG.md`.
4. Phases 2-4: write job files from the plan when Phase 1 is merged. Phase 3 opens with three mockups for the founder to pick from (plan section 4, item 6), cursor included.

## Tools (all in `tools/`, safe: nothing reaches the live session)

- `shellshot.sh SHELL_ROOT OUT [WxH] -- steps`: shell in headless KWin.
- `hyprshot.sh REPO_ROOT OUT [WxH] -- steps`: the repo's Hyprland config + shell nested in headless KWin; use for search, overview, cheatsheet.
- `measure_surfaces.sh SHELL_ROOT OUT.tsv [names]`: PSS with loaders removed.
- `qt_menus.sh APP CLASS`: launch times and exported menus on the live seat (opens and closes real windows by pid).

## Lessons from this session

- Agent worktrees are cut from `main`, not `dev`: the contract now makes workers re-point first.
- zsh does not word-split `$var` in `for`/`set --`: run loops over pairs under `bash -c`.
- A launch helper in `$(...)` loses its globals; `qt_menus.sh` once left six windows open. Always check `hyprctl clients` after a live probe.
- hypridle locks the live seat after 5 minutes idle; a locked seat hides layers from `hyprctl layers`.
