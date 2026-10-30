# KOOMPI Hyprland: the archiso profile

The live/install ISO for **KOOMPI Hyprland**, built from Arch's `releng` profile
trimmed to what KOOMPI needs. Arch Linux only, x86_64.

## How an install goes

```
boot the ISO ─> tty1 starts koompi-install
             ─> archinstall with KOOMPI's defaults (config.json) and the
                KOOMPI Hyprland profile (koompi_hyprland.py): the user picks the
                disk and makes an account, then Install, then Reboot
             ─> first start of the new system: koompi-firstboot.service on tty1
                clones github.com/koompi/koompi-desktop (main) into the user's
                ~/.local/share/koompi-desktop and runs its install.sh, the same
                path as the one-line installer
             ─> the login screen (SDDM), the KOOMPI session
```

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
Every one can be changed in archinstall's menu before Install; the disk layout and
the account are always the user's choice. The best-effort layout with btrfs is the
one to pick.

## Files

| File | Purpose |
|------|---------|
| `profiledef.sh` | ISO identity (`koompi-hyprland-YYYY.MM.DD-x86_64.iso`), BIOS syslinux + UEFI systemd-boot, file modes. |
| `pacman.conf` | Build-time repos: stock Arch. `[koompi]` is commented out. |
| `packages.x86_64` | The live session: base, kernel, firmware, microcode, `archinstall`, network and disk tools. |
| `syslinux/`, `efiboot/loader/` | Boot menus, each with a safe-graphics (`nomodeset`) entry. |
| `airootfs/root/.automated_script.sh` | tty1: runs a `script=` boot parameter if given, else `koompi-install`. |
| `airootfs/usr/local/bin/koompi-install` | Banner, network check, then archinstall with the KOOMPI config. |
| `airootfs/usr/share/koompi/archinstall/` | `config.json` (defaults) and `koompi_hyprland.py` (the profile). |
| `airootfs/usr/share/koompi/firstboot/` | The first-boot script and unit the profile puts on the new system. |
| `airootfs/etc/...` | Live root autologin, NetworkManager, pacman keyring init, os-release. |

`KOOMPI_REF` and `KOOMPI_REPO`, set before `koompi-install`, change what the first
start installs (a test of a branch).

## Build

On GitHub: Actions > *Build & Release KOOMPI Hyprland ISO* > Run workflow.
`publish` off keeps the ISO as a workflow artifact for testing; on, it becomes a
GitHub Release with `SHA256SUMS`.

Locally (root, `archiso` installed, internet):

```sh
sudo mkarchiso -v -w /tmp/koompi-work -o /tmp/koompi-out sdata/dist-arch/iso/koompi/
```

## Test

`sdata/dist-arch/iso/test/qemu-install.sh ISO uefi|bios` installs the ISO onto a
blank QEMU disk unattended (`unattended.sh`, through `script=`), boots the result,
lets the first start set up the desktop, and prints the report the new system
writes on its serial line. `KOOMPI_APPS=0` skips the application set for a quicker
run. Needs KVM, `qemu`, `bsdtar`, and `edk2-ovmf` for UEFI.

## Not yet

- The signed `[koompi]` repo, and installing the desktop from packages.
- The Zig installer in `installer/` as the face of `koompi-install`.
- Secure Boot, an offline install, branding art (the splash is still releng's).
- Pinning archinstall: the ISO takes Arch's current one. `config.json` is read by
  4.5; a format change shows up as the QEMU test failing.

[archiso]: https://gitlab.archlinux.org/archlinux/archiso
