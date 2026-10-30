#!/usr/bin/env bash
# shellcheck disable=SC2054  # qemu takes comma-separated suboptions inside one argument
# QEMU install test for the KOOMPI Hyprland ISO: installs it unattended onto a
# blank disk, boots the result, lets the first boot set up the desktop, and reads
# the report the installed system prints on the serial line.
#
#   qemu-install.sh ISO uefi|bios [WORKDIR]
#
# KOOMPI_REF / KOOMPI_REPO: what the first boot installs (default: main on GitHub).
# KOOMPI_APPS=0: skip the application set on first boot (quicker).
# KOOMPI_TEST_APPEND: extra live kernel parameters.
# Needs qemu-system-x86_64, bsdtar, python3, KVM; OVMF for uefi.

set -euo pipefail

iso="$(realpath "${1:?usage: qemu-install.sh ISO uefi|bios [WORKDIR]}")"
firmware="${2:?uefi or bios}"
work="${3:-$(mktemp -d)}"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ref="${KOOMPI_REF:-main}"
repo="${KOOMPI_REPO:-https://github.com/koompi/koompi-desktop.git}"
apps="${KOOMPI_APPS:-1}"
port="${KOOMPI_TEST_PORT:-8719}"
mem="${KOOMPI_TEST_MEM:-6G}"

mkdir -p "$work"
disk="$work/disk-$firmware.qcow2"
qemu-img create -q -f qcow2 "$disk" 60G

fw=()
if [[ $firmware == uefi ]]; then
    cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$work/vars.fd"
    fw=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd
        -drive "if=pflash,format=raw,file=$work/vars.fd")
fi

# The live kernel is booted directly so the test can add script= and console=.
bsdtar -xf "$iso" -C "$work" koompi/boot/x86_64/vmlinuz-linux koompi/boot/x86_64/initramfs-linux.img
# the ISO's own boot entries find it by its UUID (archisosearchuuid), so the test does too
uuid="$(blkid -p -o value -s UUID "$iso")"
[[ -n "$uuid" ]] || { echo "no filesystem UUID on $iso" >&2; exit 1; }

cp "$here/unattended.sh" "$work/unattended.sh"
# what the first boot installs; unattended.sh fetches it from here
printf 'ref=%q\nrepo=%q\napps=%q\n' "$ref" "$repo" "$apps" > "$work/test.env"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work" >/dev/null 2>&1 &
http=$!
trap 'kill $http 2>/dev/null || true' EXIT

# q35: the CD sits on AHCI, built into the kernel. On the default i440fx it is an
# IDE CD behind ata_piix, which the live initramfs often never sees.
common=(-machine q35 -enable-kvm -cpu host -smp 4 -m "$mem" "${fw[@]}"
        -drive "file=$disk,if=virtio,format=qcow2"
        -nic user,model=virtio-net-pci
        -display none -serial "file:$work/serial-$firmware-PHASE.log" -no-reboot)

echo "== install ($firmware) -> $work/serial-$firmware-install.log"
qemu-system-x86_64 "${common[@]/PHASE/install}" -cdrom "$iso" \
    -kernel "$work/koompi/boot/x86_64/vmlinuz-linux" \
    -initrd "$work/koompi/boot/x86_64/initramfs-linux.img" \
    -append "archisobasedir=koompi archisosearchuuid=$uuid console=ttyS0,115200 script=http://10.0.2.2:$port/unattended.sh ${KOOMPI_TEST_APPEND:-}"
grep -q KOOMPI-TEST-INSTALL-DONE "$work/serial-$firmware-install.log" \
    || { echo "FAIL: the install did not finish; see $work/serial-$firmware-install.log" >&2; exit 1; }

echo "== first boot ($firmware) -> $work/serial-$firmware-firstboot.log"
qemu-system-x86_64 "${common[@]/PHASE/firstboot}"
log="$work/serial-$firmware-firstboot.log"
sed -n '/KOOMPI-TEST-REPORT-BEGIN/,/KOOMPI-TEST-REPORT-END/p' "$log"
grep -q KOOMPI-TEST-REPORT-END "$log" || { echo "FAIL: no report; see $log" >&2; exit 1; }
! sed -n '/KOOMPI-TEST-REPORT-BEGIN/,/KOOMPI-TEST-REPORT-END/p' "$log" | grep -q '^FAIL' \
    || { echo "FAIL: see the report above" >&2; exit 1; }
echo "PASS: $firmware install boots and sets up the desktop"
