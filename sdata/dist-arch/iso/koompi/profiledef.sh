#!/usr/bin/env bash
# shellcheck disable=SC2034
# KOOMPI Hyprland archiso profile. Arch's `releng` trimmed to the minimum KOOMPI
# needs, sourced by mkarchiso. The live session starts koompi-installer (the TUI),
# which runs koompi-install (archinstall with KOOMPI's defaults); the installed
# system sets up the desktop on first boot.

iso_name="koompi-hyprland"              # base name of the output .iso file
# Volume label burned into the ISO9660 filesystem: the edition + YYYYMM
# so each monthly snapshot is distinguishable.  Keep <= 32 chars, [A-Z0-9_] only.
iso_label="KOOMPI_HYPR_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="KOOMPI <https://koompi.org>"   # appears in ISO metadata
iso_application="KOOMPI Hyprland live/install"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="koompi"                    # in-ISO dir holding the squashfs + kernels
buildmodes=('iso')                      # produce a bootable ISO (not netboot)
# BIOS via syslinux, UEFI via systemd-boot, each with its config dir shipped here.
# systemd-boot is fine for the LIVE ISO; the installed target uses GRUB, because
# grub-btrfs needs it. That is the installer's job, not this profile's.
bootmodes=(
  'bios.syslinux.mbr'                   # legacy BIOS, isohybrid MBR
  'bios.syslinux.eltorito'              # legacy BIOS, El Torito
  'uefi-x64.systemd-boot.esp'           # UEFI, systemd-boot from the ESP
  'uefi-x64.systemd-boot.eltorito'      # UEFI, systemd-boot via El Torito
)
arch="x86_64"                           # only target (spec: Arch x86_64 only)
pacman_conf="pacman.conf"               # the pacman.conf in THIS dir (injects [koompi])
airootfs_image_type="squashfs"          # live root filesystem image format
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '-19')

# File permissions/ownership applied to airootfs paths. mkarchiso declares the
# array and sources this file inside a function: a `declare -A` here would make a
# local copy it never sees (the live ISO then shipped .automated_script.sh not
# executable, and the installer never started).
# Format:  ["/path"]="UID:GID:MODE"  (octal MODE).  Paths absent here keep the
# permissions they have on disk in airootfs/.
file_permissions=(
  ["/root"]="0:0:750"                                   # private root home
  ["/root/.automated_script.sh"]="0:0:755"              # live-session autostart (run by ~/.zlogin)
  ["/etc/shadow"]="0:0:0400"
  ["/usr/local/bin/koompi-install"]="0:0:755"
  # the TUI: built by CI (zig build in installer/) and copied in before mkarchiso;
  # not in git. Static, so the live session needs no zig.
  ["/usr/local/bin/koompi-installer"]="0:0:755"
  ["/usr/share/koompi/firstboot/firstboot"]="0:0:755"
)
