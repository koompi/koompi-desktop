# KOOMPI Desktop

The KOOMPI desktop: Hyprland plus a Quickshell shell.
Based on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (illogical-impulse).

Install it on Arch Linux, or a distribution built on it (EndeavourOS, CachyOS, Manjaro):

```sh
curl -fsSL https://raw.githubusercontent.com/koompi/koompi-desktop/main/install.sh | bash
```

That clones the repository to `~/.local/share/koompi-desktop` and hands over to `./setup install`.
It asks before each stage, and refuses to run as root.
Prefer to read it first? Clone and run the same thing by hand:

```sh
git clone --recursive https://github.com/koompi/koompi-desktop.git
cd koompi-desktop
./setup install
```

A new machine, or one you are ready to wipe? Download the **KOOMPI Hyprland** ISO from
[Releases](https://github.com/koompi/koompi-desktop/releases), check it against
`SHA256SUMS`, write it to a USB stick, and boot it with Secure Boot off. It starts the
installer: pick the disk, make your account, Install, Reboot. The first start of the
new system sets up this same desktop from `main` (it needs the internet, 15-40
minutes), so an ISO install updates exactly like a `curl` install.
See [`sdata/dist-arch/iso/koompi/`](sdata/dist-arch/iso/koompi/README.md).

Then log out and pick **KOOMPI** at your display manager. It is installed as
an additional Hyprland-based session; existing KDE Plasma and GNOME sessions
stay installed and selectable.

New to it? Read [`docs/manual/`](docs/manual/README.md), which starts with
coming from Mac or Windows. The keyboard map, the gestures, and which panel owns
what are specified in [`docs/navigation.md`](docs/navigation.md). `Super+/` shows
the same bindings from inside the session.

## What `./setup` does

Four steps, each skippable:

1. **Dependencies** - installs the packages the session cannot start without,
   using the Arch recipe (`sdata/dist-arch`): the `koompi-*` metapackages,
   built with `makepkg`, plus the AUR helper they need.
2. **Applications** - the opinionated set the shipped config is written around:
   WezTerm, Konsole, Zed, Chrome, Brave, Dolphin's viewers and thumbnailers,
   LibreOffice, btop, KDE Connect, Neovim, a modern CLI toolkit, and the
   KOOMPI Workbench with Claude Code, Codex, Pi and Herdr. Asked for
   separately; `--no-apps` skips it.
   See [Applications](#applications).
3. **Setups** - creates the Python virtualenv the colour pipeline runs in,
   builds the global-menu daemon with cargo (without cargo the bar shows no
   app menus), adds you to `video`/`input`/`i2c`, loads the
   `uinput` and `i2c-dev` modules, enables `ydotool`, and registers the KOOMPI
   session system-wide so GDM and SDDM can show it before login.
4. **Files** - copies `dots/` into `$HOME`, backing up anything it overwrites to
   `~/.koompi-dots-backup/<timestamp>/`.

Every file it writes is recorded in `~/.local/state/koompi/installed-files`, so
`./setup uninstall` removes exactly that set and leaves your own files alone.

```sh
./setup install --dry-run     # show what would happen, change nothing
./setup install --no-deps     # you manage packages yourself
./setup install --no-apps     # keep the applications you already have
./setup install --only-apps   # add the application set to an existing install
./setup install --only-files  # just refresh the config after a git pull
./setup update                # already running KOOMPI? pull and re-apply
./setup doctor                # what is detected, what is missing
./setup uninstall             # undo an install
```

The one-liner passes its arguments straight through, so this works too:

```sh
curl -fsSL https://raw.githubusercontent.com/koompi/koompi-desktop/main/install.sh | bash -s -- --no-apps
```

## Updating

On a machine that already runs KOOMPI, one command, from anywhere:

```sh
koompi update
```

`koompi-update` remains as a compatibility name. For an older install that
predates the CLI, send the bootstrap
one-liner again. It refreshes (or recreates) the managed checkout from `main`,
installs new dependencies, reapplies the desktop files, and keeps the existing
application choices:

```sh
curl -fsSL https://raw.githubusercontent.com/koompi/koompi-desktop/main/install.sh | bash -s -- --no-apps --yes
```

It works out how this machine got its desktop.
On KOOMPI OS, where the desktop comes from packages, that is a `pacman -Syu`.
On an install from a checkout it is a `git pull` followed by `./setup update`,
which re-applies the config, leaves your `~/.config/hypr/custom/` overrides
alone, and reloads the running session so you do not have to log out.

## KOOMPI command line

The desktop ships one native Zig command as the front door to its maintenance
and tools:

```sh
koompi --help
koompi update
koompi doctor
koompi settings
koompi theme mode dark
koompi wallpaper status
koompi reload
```

It also exposes display arrangement, tiling/stacking mode, Quick Look,
Workbench, signature capture, packaged-default migration, installation paths,
version information, and completions for bash, zsh and fish. The subcommands
delegate to the focused `koompi-*` tools, so those tools remain independently
scriptable while users only need to remember `koompi`.

## Applications

Each role is dispatched through `launch_first_available.sh`, which runs the
first program on `PATH` from a preference list in
`dots/.config/hypr/hyprland/variables.lua`.
The application step installs what makes those lists resolve the way KOOMPI
intends:

| Role | KOOMPI's choice |
|---|---|
| Terminal | WezTerm, with Konsole for the KDE apps that ask KIO for one |
| File manager | Dolphin, plus `ark`, `kio-admin` and the KDE thumbnailers |
| Browser | Google Chrome, then Brave |
| Editor | Zed |
| Documents | Okular for PDFs, Loupe for images, mpv for video |
| Office | LibreOffice |
| System | btop, GNOME System Monitor, `nm-connection-editor` |
| Phone | KDE Connect |
| Agent workbench | Herdr orchestrating Claude Code, Codex and Pi; Neovim available directly |
| CLI toolkit | Git/GitHub CLI, ripgrep, fd, fzf, jq, bat, eza, zoxide, direnv, ShellCheck, shfmt and just |

Launch **KOOMPI Workbench** to open Herdr in
the preferred terminal. The agent installers are user-local and authentication
is deliberately left to each user; KOOMPI does not copy or manage credentials.

None of it is load-bearing.
Install something else and it wins as soon as it is earlier in the list, or set your own order in `~/.config/hypr/custom/variables.lua`.

Kitty remains a shell dependency and a fallback for machines without WezTerm;
the terminal keybind and both terminal scratchpads use WezTerm.

On Arch this set is the `koompi-apps` metapackage, so KOOMPI OS images get the same programs through `koompi-desktop-experience`.
Chrome and Brave come from the AUR.

Your personal overrides live in `~/.config/hypr/custom/*.lua`.
Those files are written once and never overwritten again, so an update cannot lose them.

## Distro support

| Distro | Status |
|---|---|
| Arch Linux | Supported. This is what KOOMPI OS itself is built on. |
| EndeavourOS, CachyOS, Manjaro and other Arch-based | Supported, through their `ID_LIKE=arch`. Their own repositories can lag Arch's. |
| Anything else | Not supported. The installer says so and changes nothing. |

The package list is the Arch recipe, `sdata/dist-arch/install-deps.sh`, with
per-package notes in [`sdata/deps-info.md`](sdata/deps-info.md).

## KOOMPI OS

KOOMPI OS itself does not use `./setup`.
The desktop is packaged into `/etc/skel` (`sdata/dist-arch/koompi-hyprland-config/`) so a freshly installed user inherits it on first login.
The OS build chain - signed `[koompi]` repo, archiso profile, installer - lives
under [`sdata/dist-arch/`](sdata/dist-arch/): the `koompi-*` PKGBUILDs, `repo/`
for the signed repository, and `iso/koompi/` for the archiso profile.

## Status

Where the project stands, so a reader or a new session starts from here rather than from the commit log.
Update this section when a stage changes hands, not per commit.

| Area | State |
|---|---|
| Desktop (`./setup`) | Shipping. Installs on Arch and Arch-based distributions; `koompi update` keeps it current. |
| `koompi` CLI | Shipping. Zig front door over the `koompi-*` tools: update, doctor, settings, theme, wallpaper, reload, hooks, webapps, plugins, snapshots. |
| Boot look | Done. Plymouth splash with logo and progress bar, GRUB theme, both wired into `koompi-branding`. |
| Login screen | Done. SDDM theme is a frosted-glass card over the blurred wallpaper (`sdata/dist-arch/koompi-branding/files/sddm/theme/Main.qml`). |
| Live ISO | KOOMPI Hyprland: the live session starts `koompi-installer`, the Zig TUI in `installer/`, over `koompi-install` (archinstall with KOOMPI's defaults and profile), and the new system sets up the desktop from `main` on its first start, the one-line installer's path. Built and released by `build-iso.yml` (manual dispatch); `sdata/dist-arch/iso/test/qemu-install.sh` installs it in QEMU and checks the first start, locally or on a runner (`iso-install-test.yml`). |
| Signed `[koompi]` repo | Skeleton only (`build-packages.yml`). Signing key and publish target are not decided, so the sign and publish steps stay commented out. |
| Installer | archinstall drives ISO installs today. The Zig TUI renders with the ANSI theme and is not wired in yet. |
| Quickshell package | Done. Arch's `quickshell` from [extra], pulled in by `koompi-hyprland`; Arch rebuilds it with every Qt bump, so `pacman -Syu` upgrades both together. `koompi-widgets` carries the extra Qt and KDE runtime packages the shell loads; both replace the old `koompi-quickshell-git`. |
| Quickwork drawer | Not built. `Super+O` is reserved; the left sidebar still carries the inherited AI and translator tabs. |

Blocked on decisions: the `[koompi]` repo signing key and where the repo is hosted.
Installing and updating the desktop from pacman packages waits on it; the ISO does not.
