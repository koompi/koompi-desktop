# Worker contract, every job

You are a Sonnet worker in your own git worktree of `koompi/koompi-desktop`, cut from `dev`.
The main checkout is `/home/userx/workspace/koompi/koompi-desktop`; its `.work/` is gitignored, so read job files and tools by that absolute path.

## Before you edit

1. Read `/home/userx/workspace/koompi/koompi-desktop/AGENTS.md`, `UPSTREAM.md`, `docs/navigation.md`, `docs/conventions.md`, and `/home/userx/workspace/koompi/koompi-desktop/.claude/skills/koompi/SKILL.md`.
2. Read the audit section your job cites in `docs/design/ux-audit-2026-10-07.md`.
3. Read every file you will change and everything that calls it.
4. Your worktree may be cut from `main`. Before anything else: `git checkout -B "$(git branch --show-current)" dev` (clean tree), then confirm `git log --oneline -1` matches `git log --oneline -1 dev`.
5. `git submodule update --init` in your worktree: `modules/common/widgets/shapes` is a submodule and the shell will not load without it.

## Rules

- Edit only the files your job owns. Need another file: stop and say which and why in the report.
- Never touch the live session: no `hyprctl` against the running Hyprland, no `qs -c koompi` IPC, no `killall`/`pkill`, no writes under `~/.config`, `~/.local`, or `/etc`. The live desktop is the founder's machine.
- QML caps: 400 lines per file, 60 per function (`tests/test_file_length.sh` enforces files). Bash and Lua caps are in `docs/conventions.md`.
- Comments: none by default. One short lowercase line only for a non-obvious why or an external constraint. Delete stale or narrative comments in lines you touch.
- User-facing strings go through `Translation.tr(...)`. Do not edit `translations/*.json`.
- Shell: `set -euo pipefail`, quote every expansion, `mktemp` for temp files.
- Every behaviour change ships with the smallest test in `tests/` that fails without it. Prove it fails on the old code (stash or revert the fix, run, restore).
- Docs that describe the behaviour you change (`docs/navigation.md`, `docs/manual/*`, `docs/agents/*`) change in the same commit.

## Checks you run

- The tests you touched or added, then `NO_COLOR=1 ./tests/run.sh` once at the end. Baseline is 101 passed, 2 skipped, 1 failed (`test_update_guards.sh`, pre-existing unless your job is J06).
- For any QML change: run the changed surface headless and look at it:
  `/home/userx/workspace/koompi/koompi-desktop/.work/tools/shellshot.sh dots/.config/quickshell/koompi /tmp/<job>-shots -- shot:before ...`
  then read the PNGs. Check `qs.log` in the out dir for `TypeError`, `ReferenceError`, `Binding loop`, `Cannot assign`.
- Surfaces that need Hyprland (search, overview, cheatsheet binds, anything reading `HyprlandData`): the repo's own Hyprland config and shell, nested in headless KWin, isolated HOME and runtime dir:
  `/home/userx/workspace/koompi/koompi-desktop/.work/tools/hyprshot.sh <your worktree root> /tmp/<job>-hypr 1920x1200 -- "ipc:search open" sleep:1 shot:search`
  Steps: `ipc:<target> <fn>` (qs IPC inside the nested session), `hypr:<lua dispatch>` (e.g. `hypr:hl.dsp.exec_cmd("kitty")`), `run:<cmd>`, `sleep:<s>`, `shot:<name>`. Logs: `hyprland-run.log`, `qs.qslog` (`strings` it), `run.log`.
  Both tools are safe: nothing they start can reach the live session.
- `qmlformat` exit codes and `qmllint` prove nothing on this tree (see the gotchas in AGENTS.md's vault); do not cite them.

## Landing

- Atomic commits on your worktree branch; the message says why, in the repo's style (`git log --oneline -15`). Never add a co-author trailer or "Generated with" line. Never `--no-verify`.
- Write your report to `/home/userx/workspace/koompi/koompi-desktop/.work/<JOB>-report.md`: what changed and why (file:line), the test that fails without the fix and its before/after output, the full-suite tail, the screenshots you looked at and what you saw, anything you could not do and the exact reason.
- Your "done" is a claim. The lead re-runs every check.
