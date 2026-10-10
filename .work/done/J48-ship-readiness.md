# J48: install from the repository into a clean machine, and close the stale ship items

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Source: `~/.config/koompi/TODO.md`, section "Ship". The founder asked for it on 2026-10-09.

## State the lead found

- "Replace machine-specific values... `general.lua:334` binds the touchscreen to `eDP-1`": done; `dots/.config/hypr/hyprland/general.lua:205-216` reads the panel from `/sys/class/drm`. Sweep the shipped tree (`dots/`, `setup`, `sdata/`, `cli/`, `shell-services/` outside tests) for any other machine-specific value: output names, the founder's username or home path, device ids, hardware-only module names. List each with file:line and replace it with a portable default, or say why it is right as is.
- "Add install/update steps and a rollback path": `install.sh` (bootstrap) hands to `./setup install`; `docs/manual/10-updates-and-going-back.md` documents `koompi update` and going back. Check that the doc matches what `setup` and `cli/` actually do today (every command and flag it names must exist), fix the doc where it does not, and say whether a rollback path really exists end to end.
- "Record live-only paths, services, dependencies and migration steps": write it as `docs/agents/install.md` (or extend the existing agent doc that covers install, if there is one): every path outside the repo the install writes, every systemd unit it enables, every package it installs, every migration in `sdata/migrations`. Read it from the code, not from memory.

## The clean install

- In a rootless podman container from the official `archlinux` image (podman is at `/usr/bin/podman`), as a normal user with sudo, run `./setup install` from a copy of your worktree, non-interactively. Never mount the founder's home, `/run/user/1000`, the Wayland or D-Bus sockets, or the repo read-write into it; copy the tree in.
- Record every failure, fix the ones in the repo, and run it again until it installs clean. A failure that is the container's (no systemd as PID 1, no GPU) is not a fix target: list it, and say what a real machine would do there.
- Then run `./tests/run.sh` inside the container against the installed tree, and compare with the same suite on the host's dev. Every difference gets a reason.
- If the container route cannot reach a meaningful install, stop and report the options (a systemd-nspawn boot, a QEMU VM with the repo's `installer/`), each with what it would prove. Do not build a VM image yourself.
- Remove the container and image you created when you are done, by their exact names.

## Files owned

`setup` and what it sources, `install.sh`, `docs/manual/10-updates-and-going-back.md`, `docs/agents/install.md` (new) or the existing install doc, and any file holding a machine-specific value you replace (name each).

## Acceptance

- The container install log, first failing run and final clean run.
- The suite in the container vs the host, with a reason for each difference.
- Full suite on the host: no new failures.
