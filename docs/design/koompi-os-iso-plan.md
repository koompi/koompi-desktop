# KOOMPI OS ISO: plan

Status (2026-10-30): **the shortcut route is built on the `iso` branch.** The live USB opens the Zig installer (`installer/`), which writes the answers and runs `koompi-install --answers`: archinstall with the KOOMPI profile does the disk, and the new system's first boot runs the one-line installer from `main`. No `[koompi]` repo and no edition packages are involved. The rest of this file is the original plan (decided 2026-10-12); where it disagrees, the code and `sdata/dist-arch/iso/koompi/README.md` win.
Goal: a person downloads one ISO, boots it, installs KOOMPI OS, and keeps getting updates.

## Decision

- **Installer A first:** a KOOMPI profile for `archinstall`, Arch's own text installer.
  It is the fastest route to an installable ISO and stays the fallback for good.
- **Installer C next:** finish the Zig TUI in `installer/` as KOOMPI's own face.
  Its design (`installer/README.md`, `installer/docs/ui-ux.md`) already uses `archinstall` as the engine.
  So C reuses everything A builds: the edition packages, the config A feeds to `archinstall`, and `post_install.sh`.
  C replaces only the screens.
- **Not chosen:** Calamares (B). Revisit only if a graphical installer becomes a requirement.

## What exists today

| Piece | Where | State |
|---|---|---|
| `koompi-*` packages (32) | `sdata/dist-arch/koompi-*/PKGBUILD` | Written. Not built or published anywhere. |
| Edition metapackages | `koompi-desktop-hyprland`, `koompi-desktop-kde` | Written. These are what an install pulls. |
| Desktop for new users | `koompi-hyprland-config` puts the desktop in `/etc/skel` | Written. |
| Archiso profile | `sdata/dist-arch/iso/koompi/` | Boots BIOS and UEFI to a root shell with `archinstall`. It is stock Arch, and `[koompi]` is commented out in its `pacman.conf`. |
| ISO workflow | `.github/workflows/build-iso.yml` (manual dispatch) | Works. Published `iso-koompi-2026.08.25-x86_64`. |
| Repo build | `sdata/dist-arch/repo/build-repo.sh`, `.github/workflows/build-packages.yml` | Skeleton. No key, no host. |
| Zig installer (C) | `installer/` | The live USB's installer: screens only, it runs `koompi-install --answers`. `post_install.sh` (snapper `@baseline`, grub-btrfs, firewall, hibernation) is not run by anything yet. |
| Updates for git installs | `koompi update` following `main` | Works (tests `test_update_follow_main`, `test_update_from_git`). |

## Decisions needed before Phase 1

1. **Where `[koompi]` is hosted.** GitHub Releases is free and enough to start. A koompi.org mirror can come later; the `Server=` line is the only thing that changes.
2. **Who holds the signing key**, and where its backup lives. CI signs with a subkey kept as a GitHub secret.
3. **The product name on the ISO.** Docs say "KOOMPI OS — Naga", releases say "KOOMPI HD". Pick one before a public download.

## Phase 1: the signed `[koompi]` repo (about 3–5 days)

Everything after this depends on it.

- [ ] Generate the key. Ship the public half as a new `koompi-keyring` package (pacman-key populate hook), and pull it into the ISO.
- [ ] `build-repo.sh`: build every `koompi-*` PKGBUILD in a clean chroot (`makechrootpkg`), sign each package, and run `repo-add --sign`.
- [ ] Build the AUR dependencies into `[koompi]` too. Known: `qt6-avif-image-plugin`. List the rest from `sdata/deps-info.md` and the PKGBUILD `depends`.
- [ ] `build-packages.yml`: build, sign and publish on a tag or a manual run. Uncomment the sign and publish steps.
- [ ] A weekly CI run that rebuilds against current Arch. Arch rolls, so a break must show up here before a user hits it.

**Done when** a clean Arch VM can add `[koompi]`, `pacman -S koompi-desktop-hyprland`, reboot and log into the KOOMPI desktop.

## Phase 2: the ISO with installer A (about 1–1.5 weeks)

- [ ] `iso/koompi/pacman.conf`: enable `[koompi]`. `packages.x86_64`: add `koompi-keyring`, branding and a pinned `archinstall`.
- [ ] A KOOMPI `archinstall` profile that installs the edition metapackage (Hyprland by default, KDE as an option). It runs `post_install.sh` (snapper, the `@baseline` snapshot, hardware quirks) in the chroot.
- [ ] Defaults that fit KOOMPI:
  - btrfs with snapshots;
  - LUKS offered;
  - timezone Asia/Phnom_Penh;
  - keyboard layouts us and kh;
  - NetworkManager;
  - PipeWire;
  - the greeter the editions expect.
- [ ] The live ISO greets you on tty1 with a short KOOMPI banner and a single `koompi-install` command that starts `archinstall` with the profile. No hunting for menus.
- [ ] Hardware fallbacks: NVIDIA (open driver as a package choice), Broadcom Wi-Fi firmware, and a `nomodeset` boot entry.
- [ ] `build-iso.yml`: build with `[koompi]` enabled, and publish the ISO, `SHA256SUMS` and a GPG signature of the sums.

**Done when** each of these installs, reboots into KOOMPI and passes `koompi update`:
- a UEFI VM;
- a BIOS VM;
- a KOOMPI laptop;
- a dual-boot next to Windows;
- a LUKS install.

**Shortcut if Phase 1 decisions stall:** the profile can install plain Arch and Hyprland, then run the git route (`install.sh`, the same path `koompi update` uses) at first login. It ships sooner, but every user then updates through git rather than pacman, so treat it as a stopgap only.

## Phase 3: release (about 1 week, then ongoing)

- [ ] A download page with the checksum and signature, and short install steps (Secure Boot off, how to boot from USB).
- [ ] A test matrix kept in `tests/`: an ISO boot test in QEMU (BIOS and UEFI) that runs on every ISO build.
- [ ] Choose the update story for installed users: `pacman -Syu` brings `koompi-*` from `[koompi]`. `koompi update` stays for git installs, and later becomes a wrapper over pacman.
- [ ] A monthly ISO rebuild, so a fresh install is never months behind.

## Phase 4: installer C, the Zig TUI (about 3–4 weeks, after A ships)

- [ ] Wire `installer/src/archinstall.zig` to emit the same `archinstall` config A uses. That config is already proven, so C changes no install logic.
  Generate it from the pinned `archinstall`'s own schema; its JSON drifts between releases.
- [ ] Build the 10 screens in `installer/docs/ui-ux.md`, with one destructive confirm gate.
- [ ] Run the progress screen off `archinstall`'s output.
- [ ] Autostart C on tty1 in place of the `koompi-install` banner. Keep `koompi-install` (A) one keystroke away as the fallback.
- [ ] The same matrix as Phase 2 passes through C.

## Later, not in v1

- Secure Boot (shim, or signing our own keys).
- A graphical installer (Calamares) if users coming from Mac and Windows need it.
- An offline install, with packages cached on the ISO.
- ARM.

## Risks

- **Arch rolls weekly.** A broken `koompi-*` build reaches every new install. The weekly CI rebuild (Phase 1) is the guard, and someone must own reading it.
- **`archinstall` changes its config format between releases.** Pin the version on the ISO and bump it deliberately with a VM install test.
- **Key loss.** Keep an offline backup of the primary key. CI holds only a subkey, which can be revoked.
