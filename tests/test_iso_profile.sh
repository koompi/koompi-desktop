#!/usr/bin/env bash
# The KOOMPI Hyprland archiso profile, read the way mkarchiso reads it.
#
# profiledef.sh once said `declare -A file_permissions=(...)`. mkarchiso declares
# that array itself and sources the profile inside a function, so the `declare`
# made a local copy it never saw: the ISO shipped /root/.automated_script.sh not
# executable, ~/.zlogin got "permission denied", and the installer never started.
# The live root also lacked /etc/localtime, so systemd's first-boot setup stopped
# the boot at a timezone prompt.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="$REPO_ROOT/sdata/dist-arch/iso/koompi"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

# mkarchiso: a global associative array, then the profile sourced in a function
declare -A file_permissions=()
read_profile() {
    # shellcheck source=/dev/null
    . "$PROFILE/profiledef.sh"
}
read_profile

for want in /root/.automated_script.sh /usr/local/bin/koompi-install /usr/share/koompi/firstboot/firstboot; do
    [[ "${file_permissions[$want]:-}" == "0:0:755" ]] \
        || fail "mkarchiso does not see $want as 0:0:755 (got '${file_permissions[$want]:-}')"
done
for path in "${!file_permissions[@]}"; do
    [[ -e "$PROFILE/airootfs$path" ]] || fail "file_permissions names $path, which airootfs does not have"
done

# systemd-firstboot asks for whatever the live root does not set
[[ -L "$PROFILE/airootfs/etc/localtime" ]] || fail "the live root has no /etc/localtime; its boot stops at a timezone prompt"
for f in hostname locale.conf vconsole.conf; do
    [[ -s "$PROFILE/airootfs/etc/$f" ]] || fail "the live root has no /etc/$f; its boot stops to ask for it"
done

[[ $failed -eq 0 ]] && echo "PASS: test_iso_profile"
exit "$failed"
