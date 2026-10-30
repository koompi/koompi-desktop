# KOOMPI Hyprland: the archiso profile

The live/install ISO for **KOOMPI Hyprland**, built from Arch's `releng` profile
trimmed to what KOOMPI needs. Arch Linux only, x86_64.

## How an install goes

```
boot the ISO ─> tty1 starts koompi-installer, the KOOMPI installer (Zig, installer/):
                disk, encryption, account, timezone, keyboard, language
             ─> it writes the answers to /run/koompi/answers.json and runs
                koompi-install --answers, the engine: archinstall with KOOMPI's
                defaults (config.json), the whole disk in archinstall's default
                layout, and the KOOMPI Hyprland profile (koompi_hyprland.py)
             ─> first start of the new system: koompi-firstboot.service on tty1
                clones github.com/koompi/koompi-desktop (main) into the user's
                ~/.local/share/koompi-desktop and runs its install.sh, the same
                path as the one-line installer
             ─> the login screen (SDDM), the KOOMPI session
```

If the installer is left, tty1 has a root shell: `koompi-installer` starts it again,
`koompi-install` with no arguments opens archinstall's own menu with the same
defaults (any disk layout, the fallback).

So an ISO install and a `curl | bash` install end up the same machine, and both
update with `koompi update` from `main`. No `[koompi]` pacman repo is needed; it
stays commented out in `pacman.conf` until it is signed and published.

The first start needs the internet. Wi-Fi joined in the live session (`nmtui`) is
copied to the new system; without a connection the first start opens `nmtui`, or
skips to the login screen and asks again on the next start. A failed setup can be
retried on the spot and carries on where it stopped; its log is
`/var/log/koompi-firstboot.log`.

## Defaults (config.json)

GRUB, PipeWire, Bluetooth on, NetworkManager, zram swap, hostname `koompi`,
timezone Asia/Phnom_Penh, `en_US.UTF-8`, all open-source graphics drivers, SDDM.
The installer's answers replace the hostname, timezone, keyboard and language.

## The engine (`koompi-install --answers`)

The answers file is JSON, version 1 (the header of `koompi-install` has the
fields); the engine deletes it as soon as it has read it, and passwords go to
archinstall only through a `--creds` file under `/run`, deleted after. The disk is
wiped in archinstall's own default layout, as its menu makes it:

- UEFI: GPT, a 1 GiB FAT32 ESP on `/boot`; BIOS: MBR (archinstall partitions BIOS
  machines MBR), a 1 GiB FAT32 `/boot`, GRUB in the gap after the MBR
- the rest btrfs, `compress=zstd`, subvolumes `@` `/`, `@home`, `@log` `/var/log`,
  `@pkg` `/var/cache/pacman/pkg`; LUKS on that partition when encryption is asked
- one account with sudo (the first boot sets the desktop up as it); root is locked

It prints `@@koompi step N/8 ...`, `@@koompi done` or `@@koompi fail ...` lines for
the installer among archinstall's output, logs everything to
`/var/log/koompi-install.log` (copied into the new system), and exits 0 only when
the new system has its account, GRUB, fstab and first-boot step.
`--dry-run DIR` only writes archinstall's config into DIR (`tests/test_iso_engine.sh`).

## Files

| File | Purpose |
|------|---------|
| `profiledef.sh` | ISO identity (`koompi-hyprland-YYYY.MM.DD-x86_64.iso`), BIOS syslinux + UEFI systemd-boot, file modes. |
| `pacman.conf` | Build-time repos: stock Arch. `[koompi]` is commented out. |
| `packages.x86_64` | The live session: base, kernel, firmware, microcode, `archinstall`, network and disk tools. |
| `syslinux/`, `efiboot/loader/` | Boot menus, each with a safe-graphics (`nomodeset`) entry. |
| `airootfs/root/.automated_script.sh` | tty1: runs a `script=` boot parameter if given, else `koompi-installer` (or `koompi-install` without it). |
| `airootfs/usr/local/bin/koompi-install` | The engine (`--answers`), or archinstall's menu with the KOOMPI config (no arguments). |
| `airootfs/usr/local/bin/koompi-installer` | The installer TUI. Not in git: the workflow builds `installer/` and copies it here before mkarchiso. |
| `airootfs/usr/share/koompi/archinstall/` | `config.json` (defaults) and `koompi_hyprland.py` (the profile). |
| `airootfs/usr/share/koompi/firstboot/` | The first-boot script and unit the profile puts on the new system. |
| `airootfs/etc/...` | Live root autologin, NetworkManager, pacman keyring init, os-release. |

`KOOMPI_REF` and `KOOMPI_REPO`, set before `koompi-install`, change what the first
start installs (a test of a branch).

## Build

On GitHub: Actions > *Build & Release KOOMPI Hyprland ISO* > Run workflow.
`publish` off keeps the ISO as a workflow artifact for testing; on, it becomes a
GitHub Release with `SHA256SUMS`.

Locally (root, `archiso` and `zig` installed, internet):

```sh
(cd installer && zig build -Doptimize=ReleaseSafe)
install -Dm755 installer/zig-out/bin/koompi-installer sdata/dist-arch/iso/koompi/airootfs/usr/local/bin/koompi-installer
sudo mkarchiso -v -w /tmp/koompi-work -o /tmp/koompi-out sdata/dist-arch/iso/koompi/
```

## Test

`sdata/dist-arch/iso/test/qemu-install.sh ISO uefi|bios` installs the ISO onto a
blank QEMU disk unattended (`unattended.sh`, through `script=`: an answers file and
`koompi-install --answers`, as the installer does), boots the result, lets the
first start set up the desktop, and prints the report the new system writes on its
serial line. `KOOMPI_APPS=0` skips the application set for a quicker run;
`KOOMPI_TEST_OVERLAY=1` puts this checkout's engine, profile and first-boot files
over an older ISO's; `KOOMPI_TEST_ENCRYPT=1` installs with LUKS (passphrase
`koompi`), the install only for now. Needs KVM, `qemu`, `bsdtar`, and `edk2-ovmf`
for UEFI.

`sdata/dist-arch/iso/test/check-archinstall-config.py` loads a `--dry-run` config
through archinstall's own parser and partitioner on an image file (its header says
how to get archinstall's Python packages).

## Not yet

- The signed `[koompi]` repo, and installing the desktop from packages.
- Typing the LUKS passphrase in the QEMU test's first boot.
- Secure Boot, an offline install, branding art (the splash is still releng's).
- Pinning archinstall: the ISO takes Arch's current one. `config.json` is read by
  4.5; a format change shows up as the QEMU test failing.

[archiso]: https://gitlab.archlinux.org/archlinux/archiso
