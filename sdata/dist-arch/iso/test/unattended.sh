#!/usr/bin/env bash
# Run inside the live ISO by the QEMU install test (script= boot parameter).
# Partitions /dev/vda, runs koompi-install's archinstall config unattended, makes
# the installed system report its first boot on the serial line, powers off.
#
# test.env, next to this script on the test's HTTP server: ref=, repo= (what the
# first boot installs from), apps=0 (first boot skips the application set, quicker).

set -euo pipefail
exec > >(tee /dev/ttyS0) 2>&1
set -x

ref=main repo=https://github.com/koompi/koompi-desktop.git apps=1
script_url="$(tr ' ' '\n' </proc/cmdline | sed -n 's/^script=//p')"
curl -fsS "${script_url%/*}/test.env" -o /tmp/test.env
# shellcheck source=/dev/null
. /tmp/test.env
curl -fsS "${script_url%/*}/mirrorlist" -o /tmp/mirrorlist && mv /tmp/mirrorlist /etc/pacman.d/mirrorlist || true
disk=/dev/vda
share=/usr/share/koompi/archinstall

until systemctl is-active --quiet pacman-init.service; do sleep 2; done

firmware=bios
[[ -d /sys/firmware/efi ]] && firmware=uefi

sgdisk --zap-all "$disk"
if [[ $firmware == uefi ]]; then
    sgdisk -n1:0:+1G -t1:ef00 -n2:0:0 -t2:8300 "$disk"
else
    sgdisk -n1:0:+1M -t1:ef02 -n2:0:0 -t2:8300 "$disk"
fi
partprobe "$disk"; udevadm settle
root="${disk}2"
mkfs.btrfs -f -L koompi "$root"
mount -t btrfs "$root" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
mount -t btrfs -o subvol=@,compress=zstd "$root" /mnt
mkdir -p /mnt/home
mount -t btrfs -o subvol=@home,compress=zstd "$root" /mnt/home
if [[ $firmware == uefi ]]; then
    mkfs.fat -F32 "${disk}1"
    mkdir -p /mnt/boot
    # by type: right after mkfs, blkid may not know it yet, and vfat is a module not yet loaded
    mount -t vfat "${disk}1" /mnt/boot
fi

jq --arg pw koompi '. + {
    disk_config: {config_type: "pre_mounted_config", mountpoint: "/mnt"},
    users: [{username: "koompi", "!password": $pw, sudo: true}],
    "!root-password": $pw
}' "$share/config.json" > /tmp/test-config.json

KOOMPI_REF="$ref" KOOMPI_REPO="$repo" archinstall --config /tmp/test-config.json --silent

# test only: the first boot speaks on the serial line, and a report follows it
grep -q KOOMPI_USER /mnt/etc/koompi/firstboot.conf
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&console=tty0 console=ttyS0,115200 /' /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
mkdir -p /mnt/etc/systemd/system/koompi-firstboot.service.d
cat > /mnt/etc/systemd/system/koompi-firstboot.service.d/test.conf <<'EOF'
[Unit]
Before=serial-getty@ttyS0.service
[Service]
TTYPath=/dev/ttyS0
EOF
if [[ $apps == 0 ]]; then
    # ./setup install takes its flags through install.sh; the test drops the application set
    # shellcheck disable=SC2016  # $DEST is the firstboot script's own, matched literally
    sed -i 's|exec bash "\$DEST/install.sh" -y|exec bash "$DEST/install.sh" -y --no-apps|' /mnt/usr/local/lib/koompi/firstboot
fi
cat > /mnt/usr/local/lib/koompi/test-report <<'EOF'
#!/usr/bin/env bash
# QEMU install test: what the first boot left behind, then power off.
{
    echo "KOOMPI-TEST-REPORT-BEGIN"
    check() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; fi; }
    check firstboot-done '[[ -e /etc/koompi/firstboot.conf.done && ! -e /etc/koompi/firstboot.conf ]]'
    check sudoers-removed '[[ ! -e /etc/sudoers.d/90-koompi-firstboot ]]'
    check checkout '[[ -d /home/koompi/.local/share/koompi-desktop/.git ]]'
    check shell-tree '[[ -f /home/koompi/.config/quickshell/koompi/shell.qml ]]'
    check hypr-config '[[ -d /home/koompi/.config/hypr/hyprland ]]'
    check session-entry 'ls /usr/share/wayland-sessions/ | grep -qi koompi'
    check quickshell 'command -v qs || command -v quickshell'
    check display-manager 'systemctl is-enabled display-manager.service'
    check koompi-cli '[[ -x /home/koompi/.local/bin/koompi ]]'
    systemctl --failed --no-legend
    echo "KOOMPI-TEST-REPORT-END"
} > /dev/ttyS0 2>&1
systemctl poweroff
EOF
chmod 755 /mnt/usr/local/lib/koompi/test-report
cat > /mnt/etc/systemd/system/koompi-test-report.service <<'EOF'
[Unit]
Description=KOOMPI QEMU install test report
After=koompi-firstboot.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/lib/koompi/test-report

[Install]
WantedBy=multi-user.target
EOF
arch-chroot /mnt systemctl enable koompi-test-report.service

sync
umount -R /mnt
echo "KOOMPI-TEST-INSTALL-DONE"
systemctl poweroff
