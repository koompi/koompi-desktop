# Working on koompi-desktop

For an AI agent editing this repo. Read `UPSTREAM.md` and `CONTEXT.md` first; they're
not restated here.

## Decision tree

**Is it a stock `koompi <cmd>`?**
Check `cli/src/main.zig`'s `commands` array before writing a new script — it's the
canonical list, and `koompi help` / `koompi <cmd> --help` print straight from it. There
is no `omarchy commands`-style introspection here; the array *is* the registry. If the
capability fits an existing command's helper script, extend that script rather than
adding a new top-level command.

**Is it a per-user tweak to Hyprland behavior?**
Edit `~/.config/hypr/custom/*.lua`, never `dots/.config/hypr/hyprland/*.lua`. `custom/`
is user-owned and `koompi-migrate` never touches it; `hyprland/` is package-owned and
gets resynced on every install/update, so an edit there is silently overwritten. See
`docs/agents/hyprland.md`.

**Is it a color/theme change?**
Use `koompi theme {regenerate,mode,scheme,color}` — don't hand-edit generated color
files or call `matugen`/`switchwall.sh` directly from a new script. See
`docs/agents/theming.md`.

**Is it a reaction to a lifecycle event (theme change, post-update)?**
Planned, not yet implemented — see `docs/agents/hooks.md`. Until it lands, don't invent
a hook call site; the event you want probably needs a real feature request instead.

**Is it a fix for state an existing user already has (a renamed path, a stale file)?**
A default change reaches only new users. Read `docs/agents/migrations.md` before writing
one under `sdata/migrations/`; `koompi-migrate new <slug>` writes the skeleton.

**Is it a self-contained extension someone shouldn't have to fork the shell for?**
Check `docs/agents/plugins.md` — there's a real (unrelated) Hyprland gesture plugin
tree at `plugins/`, and a separate, not-yet-built shell-widget plugin convention.

**Is it a port of an upstream (end-4) fix?**
See `docs/agents/contributing.md` for the manual port workflow — there's no
`git merge` path.

**None of the above?**
Read `docs/navigation.md` and `docs/conventions.md` before adding a new surface or
naming something — they fix the shell's UX and naming model, and disagreeing with them
without updating them first is a defect, not a variant.

## Which branch a machine follows

Installed machines track `main`; day-to-day work happens on `dev` and lands on `main` by PR.
`install.sh` clones `main`, and `KOOMPI_REF` picks another branch.
A re-run of the one-liner repoints an existing checkout at the tracked branch, fetch refspec included.

`prod-hd`, the old release line, is retired.
`./setup update` moves a *managed* checkout off it onto `main`: a clean tree on `prod-hd`, an `origin` that is the KOOMPI repo, and no commit `origin/main` does not already have.
Anything else, such as a dirty tree, one local commit or a fork, is left exactly where it is, with the reason on one line.
A checkout already on `main` loses any leftover `prod-hd` fetch refspec, which would fail every fetch once the branch is deleted.
The name lives in one place, `RETIRED_BRANCH` in `sdata/install/update.sh`.
A machine on `prod-hd` runs its old updater first, which only pulls `prod-hd`; the move happens in the re-exec from the pulled tree.
So `prod-hd` is fast-forwarded to a `main` that carries this code and kept until the field has updated; delete it before then and those machines can only recover by re-running the one-liner.

An update also re-runs itself once from the tree it just pulled, so a change to installer
logic takes effect on the run that pulls it rather than the one after. If you are writing
something that must not happen twice in one update, `KOOMPI_UPDATE_REEXEC=1` is set in the
second pass.

## Ownership quick reference

| Path | Owner | Never edit if |
| --- | --- | --- |
| `dots/.config/hypr/custom/**` | user | — (this is the user's slot) |
| `dots/.config/hypr/hyprland/**` | package | you want a change to survive an update |
| `dots/.config/quickshell/koompi/**` | package (KOOMPI fork of end-4) | you're not porting an upstream change or making a deliberate KOOMPI edit — see `UPSTREAM.md` |
| `cli/src/main.zig` | KOOMPI-original | never — this is the one place new commands register |
| `installer/`, `sdata/dist-arch/` | KOOMPI-original | — |

## Ground truth over convention

Where any doc under `docs/agents/` disagrees with the code, the code is the defect —
same rule as `docs/navigation.md`. Grep before you claim something exists.
