# What `./setup` writes outside the repository

For an agent changing the installer, or auditing what a git install leaves on a machine.
Read from `setup` and `sdata/` as they are; if a step changes, change this page with it.

`install.sh` is only a bootstrap: it clones the repo to `~/.local/share/koompi-desktop` (`KOOMPI_DEST`) and runs `./setup install`.
`./setup` runs as a normal user and refuses root; it calls `sudo` only for the rows marked system.
Order in `setup`: deps, apps, `run_setups`, files, then the global-menu build, `setup_services`, `reload_session`, `record_repo_path`.
`--no-deps`, `--no-apps`, `--no-setups`, `--no-files` and the `--only-*` forms skip or pick steps; `-n` prints and changes nothing.

## Packages

| Step | Source | What lands |
|---|---|---|
| deps (Arch) | `sdata/dist-arch/install-deps.sh` | `pacman -Syu`, then paru built from the AUR source if it is missing, then these metapackages (`quickshell` itself comes from Arch's [extra] through `koompi-widgets`) from `sdata/dist-arch/<name>/PKGBUILD`, in order: `koompi-basic`, `koompi-audio`, `koompi-backlight`, `ttf-koompi-star`, `koompi-fonts-themes`, `koompi-kde`, `koompi-portal`, `koompi-python`, `koompi-screencapture`, `koompi-toolkit`, `koompi-widgets`, `koompi-hyprland`, `koompi-microtex-git`, `koompi-bibata-modern-classic-bin`. Each PKGBUILD's `depends` is the package list. It first removes the superseded `illogical-impulse-*` and `*-git` names listed in `arch_drop_deprecated`. Asks about `plasma-browser-integration`. |
| deps (Fedora, Debian, Ubuntu) | `sdata/dist-<group>/install-deps.sh` with `packages*.list` | The lists beside the recipe. Debian and Ubuntu also build from source what the distro does not package (`sdata/lib/from-source.sh`); Fedora needs none. |
| apps | `sdata/dist-<group>/install-apps.sh` | Arch: `koompi-kiri` (Kiri, built from github.com/koompiai/kiri at the commit pinned in its PKGBUILD; not in the repos or the AUR) then the `koompi-apps` metapackage (`ARCH_APP_PKGBUILDS`), and `mpvpaper` if you say yes. Asked once, skipped when `APP_CMDS` and `AGENT_CMDS` in `setup` are all present. |
| agent tools | `sdata/install/agents.sh` | `codex` and `pi` through `npm install --global --prefix ~/.local/share/koompi/npm`, symlinked into `~/.local/bin`; Claude Code from `https://claude.ai/install.sh`; Herdr from `https://herdr.dev/install.sh`. |
| python | `sdata/install/setups/python.sh` | `uv venv --system-site-packages ~/.local/state/quickshell/.venv`, then `sdata/uv/requirements.txt` into it. |
| local ai | `sdata/install/setups/ai.sh` | `uv tool install litert-lm`; the 2.6 GB model only if you say yes; a loopback SearXNG container (docker, else podman) named `searxng` on `127.0.0.1:8888`. |
| firewall, zram | `sdata/install/setups/system.sh` | `ufw` and `zram-generator` if missing. |

Build toolchains the setups look for and warn about, never install: zig 0.16.0 or newer, cargo 1.87 or newer, `uv`.
Without them the matching binary below is skipped with a warning and the shell falls back where it can.

## Built into `~/.local/bin` (from the checkout or a clone)

| Binary | Built by | Needs |
|---|---|---|
| `koompi` | `setup_koompi_cli`, `cli/` | zig |
| `koompi-global-menu-daemon` | `setup_globalmenu_rs`, `globalmenu/` | cargo |
| `koompi-shelld` | `setup_shell_services`, `shell-services/` | cargo |
| `koompi-agent-memd` | `setup_agent_memory`; source from the sibling `../koompi-agent-memd`, else cloned into `~/.cache/koompi/src/koompi-agent-memd` | cargo, git |
| `global-menu-daemon` (zig fallback) | `setup_global_menu`, into `~/.config/quickshell/koompi/scripts/global-menu/zig-out/bin`, where the QML resolves it | zig |

Build output goes to `~/.cache/koompi/build/` and `~/.cache/zig`, never into the checkout.

## Files under `$HOME`

`install_files` copies `dots/` in, three ways (`sdata/install/files.sh`):

- Mirrored with `--delete`: `~/.config/hypr/hyprland`, `~/.config/hypr/hyprlock`, `~/.config/quickshell/koompi`, `~/.config/quickshell/koompi-quicklook`. `~/.config/hypr/hyprland/shellOverrides/main.lua` is kept once present.
- Merged without deleting: the rest of `dots/.config`, `dots/.local/share` and `dots/.local/bin` into `~/.config`, `~/.local/share`, `~/.local/bin`.
- Seeded once, never overwritten (`KEEP_PATHS`): `~/.config/hypr/custom/{env,execs,general,keybinds,rules,variables}.lua`, `~/.config/wezterm/wezterm.lua`, `~/.config/easyeffects/db/easyeffectsrc`, and three `~/.config/autostart/*.desktop`.

Also written:

- `~/.koompi-dots-backup/<timestamp>/`: a copy of every file this run will change, made first (`--no-backup` skips it).
- `~/.local/state/koompi/installed-files`: the manifest `./setup uninstall` removes by. `installed-system-files` is the system equivalent.
- `~/.local/state/koompi/repo-path`: where `koompi update` finds the checkout.
- `~/.local/state/koompi/migrations/`: markers for `workspace-app-icons-v1`, `quick-toggles-v1` and every file in `sdata/migrations`.
- `~/.local/state/koompi/config-defaults.json`: the baseline for the next config merge (written by `update`).
- `~/.config/koompi/config.json.bak-<timestamp>`: before a defaults merge or a legacy-setting fix.
- `~/.litert-lm/config.json`, once, with the backend and thread count chosen for this machine.
- `~/.config/searxng/settings.yml`, once.
- `~/.local/share/wayland-sessions/koompi.desktop`, its `Exec=` rewritten to `~/.local/bin/koompi-session` when `/usr/bin/koompi-session` is absent.
- `~/.claude/skills/koompi`, `~/.codex/skills/koompi`, `~/.pi/agent/skills/koompi`: symlinks to `docs/agents`, only where that harness's directory already exists.
- A cursor default and GTK settings through `gsettings` and `update-desktop-database` (`setups/desktop.sh`).
- The old `xdg-desktop-portal.service.d/koompi-remotedesktop.conf` drop-in is removed if it still carries the `XDG_DESKTOP_PORTAL_DIR` override.

## System paths (sudo)

| Path | Step | Why |
|---|---|---|
| `/etc/modules-load.d/koompi.conf` (`i2c-dev`, `uinput`) | `setup_groups_and_modules` | ddcutil and ydotool |
| `/etc/udev/rules.d/99-koompi-uinput.rules` | same | uinput group access |
| groups `video`, `input`, `i2c` for the user (`i2c` created if absent, not on Fedora) | same | needs a new login |
| `/usr/lib/systemd/system-sleep/koompi-btintel-pcie` | `setup_suspend_hook` | drops `btintel_pcie` around suspend; a no-op where the module is not loaded |
| whatever `dots/.local/share/koompi/libexec/apply-hardware` decides from `sdata/hardware/` (DMI-gated quirks, log in `/var/log/koompi/hardware.log`) | `setup_hardware_quirks` | per-machine fixes |
| `/usr/local/lib/...` copies of `sdata/dist-arch/koompi-sysdefaults/files/usr/lib` (zram, oomd, 5 s stop timeout) | `setup_low_ram_defaults` | low-RAM survival |
| the output of `libexec/hibernation-setup` (btrfs swapfile, resume hook, kernel command line) | `setup_hibernation` | refuses with exit 0 off btrfs or without mkinitcpio |
| ufw rules: deny incoming, allow 1714-1764 tcp and udp, 53317 tcp and udp, ssh if sshd is active | `setup_firewall_defaults` | skipped if firewalld is active |
| `/usr/local/bin/koompi-session`, `/usr/share/wayland-sessions/koompi.desktop`, `/usr/share/koompi/wayland-sessions/koompi.desktop` (symlink), `/etc/sddm.conf.d/20-koompi-session.conf` | `setup_system_session` | login entry; never overwrites a file that is not KOOMPI-managed; `/usr/bin/koompi-session` from the package wins |
| `/usr/lib/systemd/user/ydotool.service` symlink to the system unit, when the distro has only the system one | `setup_services` | |

Every row that needs systemd checks `/run/systemd/system` first and skips with a message in a container or chroot.

## systemd units enabled

System: `systemd-oomd.service` (enabled and restarted), `systemd-zram-setup@zram0.service` (started when no zram swap exists), `ufw.service`, `bluetooth.service` (`--now`), `fwupd-refresh.timer`.

User: `ydotool` (`--now`), `touch-gestures` (needs python-evdev), `hypridle`, `koompi-migrate-notify`, `koompi-snapshot-notify`, `koompi-crash-watch`, `litert-lm.socket`; `litert-lm.service` and `litert-lm-watchdog.service` are disabled on purpose.
`touch-gestures`, `koompi-migrate-notify`, `koompi-snapshot-notify`, `koompi-crash-watch` and the `litert-lm` units ship from `dots/.config/systemd/user/`; `ydotool` and `hypridle` come from the distro. They are enabled without `--now` and start with the next graphical session.
Each user unit is skipped with a warning when there is no user manager.

## Migrations

`sdata/migrations/<unix-ts>-<slug>.sh`, run per user by `koompi-migrate run`; the file name is the marker.
`./setup install` and `./setup update` do not run them: `koompi update` does, and `koompi-migrate-notify` offers any left pending at login.
Rules and the runner are in `docs/agents/migrations.md`.

| Migration | What it repairs |
|---|---|
| `1787576768-noop-mechanism-check.sh` | nothing; proves the runner works |
| `1791394815-custom-keybind-descriptions.sh` | rewords shipped lines in the user-owned `~/.config/hypr/custom/keybinds.lua`, exact matches only |
| `1791425575-session-target-autostart.sh` | gives existing homes the systemd user unit and autostart entries that the sync skips and `/etc/skel` seeds only for new users |

`install_files` also runs two inline one-time config fixes, `migrate_workspace_app_icons` and `migrate_quick_toggles`, each guarded by a marker under `~/.local/state/koompi/migrations/`.

## Update and uninstall

`./setup update` pulls the checkout (`git pull --ff-only`, skipped on a detached HEAD or a dirty tree), then reruns deps, setups and files, merges config defaults, records the repo path and reloads the session.
It never re-offers the application set.
`./setup uninstall` removes the manifest's files and empty parent directories, offers to remove the venv and the system session files, and leaves every package, the backups and the build cache.
