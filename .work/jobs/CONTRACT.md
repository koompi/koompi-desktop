# Worker contract, every job

You are a Sonnet worker in your own git worktree of `koompi/koompi-desktop`, cut from `dev`.
The main checkout is `/home/userx/workspace/koompi/koompi-desktop`. Its `.work/` is gitignored, but the lead force-adds the campaign's files, so your worktree holds a copy as old as your base; read job files and tools by the main checkout's absolute path, which is current. Repo-wide greps should exclude `.work/`.

## Before you edit

1. Read `/home/userx/workspace/koompi/koompi-desktop/AGENTS.md`, `UPSTREAM.md`, `docs/navigation.md`, `docs/conventions.md`, and `/home/userx/workspace/koompi/koompi-desktop/.claude/skills/koompi/SKILL.md`.
2. Read the audit section your job cites in `docs/design/ux-audit-2026-10-07.md`.
3. Read every file you will change and everything that calls it.
4. Your worktree is cut from the main checkout's `HEAD`, which is `dev` (`worktree.baseRef: head`). Before anything else, confirm `git log --oneline -1` shows the base commit your dispatch prompt names. If it does not, stop and report both lines; do not move, reset or recreate the branch.
5. `git submodule update --init` in your worktree: `modules/common/widgets/shapes` is a submodule and the shell will not load without it.

## Rules

- Edit only the files your job owns. Need another file: stop and say which and why in the report.
- Never touch the live session: no `hyprctl` against the running Hyprland, no `qs -c koompi` IPC, no `killall`/`pkill`, no writes under `~/.config`, `~/.local`, or `/etc`. The live desktop is the founder's machine.
- QML caps: 400 lines per file, 60 per function (`tests/test_file_length.sh` enforces files). Bash and Lua caps are in `docs/conventions.md`.
- Comments: none by default. One short lowercase line only for a non-obvious why or an external constraint. Delete stale or narrative comments in lines you touch.
- User-facing strings go through `Translation.tr(...)`. Do not edit `translations/*.json`.
- Shell: `set -euo pipefail`, quote every expansion, `mktemp` for temp files.
- Hyprland reads Lua here. Every dispatch, from QML (`Hyprland.dispatch`) or a script (`hyprctl dispatch`), uses the Lua form: `hl.dsp.exec_cmd(cmd, { float = true, ... })`, `hl.dsp.focus({ window = "address:0x..." })`, and so on (`/usr/share/hypr/stubs/hl.meta.lua` lists them). A legacy string like `exec [float] kitty` or `focuswindow address:...` returns an error and does nothing, silently from QML. Prove a dispatch works in the nested harness, never by its exit code alone.
- Every behaviour change ships with the smallest test in `tests/` that fails without it. Prove it fails on the old code (stash or revert the fix, run, restore).
- Docs that describe the behaviour you change (`docs/navigation.md`, `docs/manual/*`, `docs/agents/*`) change in the same commit.

## Checks you run

Six workers share the founder's live 8-core machine (Jev: `swarm_concurrency six_with_heavy_lock p=0.91`). Run the full suite and every test that starts `kwin_wayland`, `Hyprland` or `qs` through the machine-wide lock: `/home/userx/workspace/koompi/koompi-desktop/.work/tools/heavy.sh <command>` (e.g. `heavy.sh env -u HYPRLAND_INSTANCE_SIGNATURE NO_COLOR=1 ./tests/run.sh`). `shellshot.sh`, `hyprshot.sh` and `measure_surfaces.sh` take the lock themselves. Waiting on it is normal; never bypass it. Each worktree holds one place in that line, and your other runs wait behind it. Hand-back: also copy your report to `/home/userx/.tmp/<JOB>-handoff/` (the main checkout's `.work/` may refuse your writes).

- The tests you touched or added, then `NO_COLOR=1 env -u HYPRLAND_INSTANCE_SIGNATURE ./tests/run.sh` once at the end (with the signature set, `test_bar_keys.sh` reads the live compositor's binds; unset it for every test you run). Baseline on `dev` after J01: see `/home/userx/workspace/koompi/koompi-desktop/.work/BACKLOG.md`; name any failure and say whether it fails on `dev` too.
- For any QML change: run the changed surface headless and look at it:
  `/home/userx/workspace/koompi/koompi-desktop/.work/tools/shellshot.sh dots/.config/quickshell/koompi /tmp/<job>-shots -- shot:before ...`
  then read the PNGs. Check `qs.log` in the out dir for `TypeError`, `ReferenceError`, `Binding loop`, `Cannot assign`.
- Surfaces that need Hyprland (search, overview, cheatsheet binds, anything reading `HyprlandData`): the repo's own Hyprland config and shell, nested in headless KWin, isolated HOME and runtime dir:
  `/home/userx/workspace/koompi/koompi-desktop/.work/tools/hyprshot.sh <your worktree root> /tmp/<job>-hypr 1920x1200 -- "ipc:search open" sleep:1 shot:search`
  Steps: `ipc:<target> <fn>` (qs IPC inside the nested session), `hypr:<lua dispatch>` (e.g. `hypr:hl.dsp.exec_cmd("kitty")`), `run:<cmd>`, `sleep:<s>`, `shot:<name>`. Logs: `hyprland-run.log`, `qs.qslog` (`strings` it), `run.log`.
  Both tools are safe: nothing they start can reach the live session.
  Delete only the exact paths your own runs printed, one by one. Never `rm` a glob in a shared temp location (`/tmp/*`, `~/.tmp/*`, `/tmp/hr.*`, `tmp.*`): other workers' live runs and the lead's kept evidence live there, and two workers have already wiped them that way.
- Every private bus is `dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- ...` (no service directories). The stock config auto-starts the host's portals: the Hyprland one segfaults and the founder's desktop toasts a crash for each, and a private document portal on the real `XDG_RUNTIME_DIR` unmounts the live one. `tests/test_private_bus.sh` fails a test that skips it. Every headless session also gets its own `XDG_RUNTIME_DIR` (`mktemp -d`, `chmod 700`).
- Every nested Hyprland config you write sets `ecosystem = { no_update_news = true, no_donation_nag = true }`. A second Hyprland start in one data home (a retried session) runs `hyprland-update-screen`, which segfaults there, and every coredump under uid 1000 is a crash toast on the founder's desktop. `tests/test_nested_hyprland_quiet.sh` fails a test that skips it. Never run a probe you expect to crash an app; if one must, say so in the report. An app still open when a nested compositor exits can crash too (Dolphin did, six times): close what you started before the session ends; `hyprshot.sh` closes its own steps' windows.
- No GUI process (`qml`, `qml6`, `qs`, an app, a dialog) ever runs with the founder's real `HOME`, `XDG_RUNTIME_DIR` (`/run/user/1000`) or `WAYLAND_DISPLAY`: its window lands on their screen and its crash toasts their desktop. Render with `shellshot.sh`/`hyprshot.sh`, or `QT_QPA_PLATFORM=offscreen` with `env -u WAYLAND_DISPLAY -u DISPLAY` and a `mktemp -d` HOME and runtime dir.
- `qmlformat` exit codes and `qmllint` prove nothing on this tree (see the gotchas in AGENTS.md's vault); do not cite them.

## Landing

- Atomic commits on your worktree branch; the message says why, in the repo's style (`git log --oneline -15`). Never add a co-author trailer or "Generated with" line. Never `--no-verify`.
- Write your report to `/home/userx/workspace/koompi/koompi-desktop/.work/<JOB>-report.md`: what changed and why (file:line), the test that fails without the fix and its before/after output, the full-suite tail, the screenshots you looked at and what you saw, anything you could not do and the exact reason.
- Your "done" is a claim. The lead re-runs every check.
