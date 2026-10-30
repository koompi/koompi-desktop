#!/usr/bin/env bash
# Run inside the live ISO by the QEMU install test (script= boot parameter).
# Installs onto /dev/vda the way the KOOMPI installer does: an answers file and
# `koompi-install --answers`, the engine the TUI runs. Then makes the installed
# system report its first boot on the serial line, and powers off.
#
# Next to this script on the test's HTTP server:
#   test.env         ref=, repo= (what the first boot installs from), apps=0 (first
#                    boot skips the application set, quicker), encrypt=1 (LUKS root,
#                    passphrase koompi)
#   mirrorlist       the host's, quicker than every mirror in the world
#   overlay.tar.gz   optional: the repo's engine, profile and first-boot files,
#                    unpacked over the live root first (an ISO older than them)

set -euo pipefail
exec > >(tee /dev/ttyS0) 2>&1
set -x
# a failed step powers off too, so the test reads the failure instead of waiting out its timeout
# shellcheck disable=SC2154  # rc is assigned inside the trap string
trap 'rc=$?; (( rc == 0 )) || { echo "KOOMPI-TEST-INSTALL-FAILED ($rc)"; sleep 2; systemctl poweroff; }' EXIT

ref=main repo=https://github.com/koompi/koompi-desktop.git apps=1 encrypt=0
script_url="$(tr ' ' '\n' </proc/cmdline | sed -n 's/^script=//p')"
base="${script_url%/*}"
curl -fsS "$base/test.env" -o /tmp/test.env
# shellcheck source=/dev/null
. /tmp/test.env
curl -fsS "$base/mirrorlist" -o /tmp/mirrorlist && mv /tmp/mirrorlist /etc/pacman.d/mirrorlist || true
if curl -fsS "$base/overlay.tar.gz" -o /tmp/overlay.tar.gz; then
    tar -xzf /tmp/overlay.tar.gz --no-same-owner -C /
    chmod 755 /usr/local/bin/koompi-install*
fi

luks=false
[[ $encrypt == 1 ]] && luks=true
mkdir -p /run/koompi
(umask 077; jq -n --argjson luks "$luks" '{
    version: 1, disk: "/dev/vda", encrypt: $luks, encryption_password: (if $luks then "koompi" else "" end),
    hostname: "koompi", full_name: "KOOMPI Test", username: "koompi", password: "koompi",
    timezone: "Asia/Phnom_Penh", keyboard: "us", locale: "en_US.UTF-8"
}' > /run/koompi/answers.json)

# --keep-mounted: the test-only changes below go into the new system before it is
# unmounted; the engine waits for pacman-init and the network itself
KOOMPI_REF="$ref" KOOMPI_REPO="$repo" koompi-install --answers /run/koompi/answers.json --keep-mounted

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
[[ ! -e /dev/mapper/root ]] || cryptsetup close root
echo "KOOMPI-TEST-INSTALL-DONE"
systemctl poweroff
