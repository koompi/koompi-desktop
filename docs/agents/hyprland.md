# Hyprland config bridge

`dots/.config/hypr/` is KOOMPI-original per `UPSTREAM.md` — the `hl.*` Lua bridge,
not inherited from end-4.

## The `hl.*` bridge

Hyprland config is normally a flat `.conf` file. KOOMPI's bridge (`hyprland/lib/`,
loaded by `hyprland.lua`) lets config live in Lua instead — `hl.config({...})`,
`hl.env(...)`, `hl.window_rule(...)`, `hl.bind(...)` — and it's what the inherited
shell's dispatch calls were ported onto. Search `hyprland/lib/` before assuming a
`hl.*` function doesn't exist; it likely does.

## `custom/` vs `hyprland/`

`dots/.config/hypr/hyprland.lua` is the entry point and `require`s both trees:

- `hyprland/*.lua` — package-owned. Resynced by `koompi-migrate` / `./setup`; any
  edit here is silently overwritten on the next install or update.
- `custom/*.lua` — user-owned. Listed in `sdata/install/files.sh`'s `KEEP_PATHS`:
  written once if absent, never clobbered afterward. Each `custom/*.lua` file is
  `require`d only `if is_file_exists(...)`, so an absent file is simply skipped, not
  an error.

If you're an agent asked to change Hyprland behavior for one user's machine, that's a
`custom/*.lua` edit. If you're changing the shipped default for everyone, that's
`hyprland/*.lua`, and it ships to every install on the next sync.

Kiri's voice binds are the concrete example already in the tree:
`dots/.config/hypr/custom/keybinds.lua` — see `docs/navigation.md`'s Kiri section.

## Session start-up and login items

`hyprland/execs.lua` imports the Wayland environment into the systemd user manager, then runs `systemctl --user start hyprland-session.target`.
The target ships in `dots/.config/systemd/user/`: `./setup` merges it into `~/.config/systemd/user/` and `/etc/skel` seeds new users with it.
The user manager reads that directory, so the first start loads it with no enable and no reload.
It binds `graphical-session.target`, which hypridle, the crash watcher, touch gestures, the migration notice and the portals hang off, and it wants `xdg-desktop-autostart.target`, which starts every login item.
`xdg-desktop-autostart.target` refuses a manual start, so a script must never `systemctl --user start` it; `tests/test_session_autostart.sh` fails on that.

## Options the shell holds

`hyprland/shellOverrides/main.lua` is written by the shell, never by hand, through
`services/HyprlandConfig.qml` and `scripts/hyprland/hyprconfigurator.py`. It is required last, so
what is in it wins over `hyprland/` and `custom/`, and removing a line hands the option back to
whatever those say.

Game mode and Reduce Motion both need `animations:enabled` off, so neither writes it.
`services/HyprlandModes.qml` is the one writer.
A mode is a flag there, its `holds` table names the options a mode forces and which modes want each, and an option is held while any mode that wants it is on and reset the moment none does.
Turning one mode off therefore never undoes another, and a mode's own toggle reads its own flag, never the shared option.
Game mode has no other store: it reads itself back from that file at start.
Reduce Motion lives in `config.json`, and the shell writes its hold when it starts.

The file survives an update.
`sdata/install/files.sh` and `koompi-migrate` both mirror `hyprland/`, and both leave the file alone once it exists (`SYNC_KEEP_PATHS` in the first, an `--exclude` on the hyprland pair in the second), writing the shipped stub only where it is missing.
`tests/test_hypr_overrides_survive_update.sh` runs both routes against a home that holds Game mode.

`HyprlandConfig` runs the script as a `Process` with argv, one run at a time: what is asked for while one runs is merged into the next run, the last word on a key winning.
A run that exits non-zero is logged with the script's stderr, and once the runs have drained `HyprlandModes` re-reads the file, so what it believes is applied is what is there.
The script needs no virtual environment, and exits non-zero with the reason on stderr when it cannot write.

A new mode (Reduce Transparency will hold `decoration:blur:enabled`) is one flag and one `by`
entry in `HyprlandModes.qml`. `tests/test_hypr_modes.sh` fails when a held option is named in any
other file of the shell.

Motion has two halves. The shell's is the `animation` roles and the duration ladder in
`modules/common/Appearance.qml`; Hyprland's is the leaves in `hyprland/general.lua`, where `speed`
is in tenths of a second. `tests/test_motion.sh` and `tests/test_motion_hypr.sh` hold both to the
budget in `docs/navigation.md`.

## Keybinds and the Super release-to-open mechanism

Don't restate it here — see `docs/navigation.md`'s "Super on its own" section for the
`quickshell:searchToggleReleaseInterrupt` wrapper and the two rules that follow it. Any
new `Super`-chord bind, in either `hyprland/keybinds.lua` or `custom/keybinds.lua`,
has to go through `hl.bind`'s wrapper or it breaks Search's release-to-open behavior.

## Screen capture

Screenshot, OCR, and screen-recording binds (`Print`, `Super+Shift+S/A/X/R`) are
plain Hyprland binds in `hyprland/keybinds.lua` dispatching to scripts under
`hyprland/scripts/` — there's no separate capture subsystem to document. See
`docs/navigation.md`'s Utilities keymap table for the full bind list.
