#!/usr/bin/env bash
# The shell runs on Arch's quickshell. Nothing may depend on the retired
# koompi-quickshell-git, and a machine that still has it must have it removed.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/sdata/dist-arch"
failed=0

[[ ! -e "$DIST/koompi-quickshell-git" ]] || { echo 'FAIL: the koompi-quickshell package dir is back' >&2; failed=1; }

users="$(grep -ln 'koompi-quickshell-git' "$DIST"/*/PKGBUILD "$DIST/install-deps.sh" 2>/dev/null || true)"
for f in $users; do
    case "$f" in
        # koompi-hyprland replaces it too (test_shell_start.sh), so pacman -Syu
        # --noconfirm on a machine with only the meta installed swaps it out.
        */koompi-widgets/PKGBUILD|*/koompi-hyprland/PKGBUILD|*/install-deps.sh) ;;
        *) echo "FAIL: $f still names the retired package" >&2; failed=1 ;;
    esac
done

widgets="$DIST/koompi-widgets/PKGBUILD"
grep -qx 'conflicts=(koompi-quickshell-git)' "$widgets" && grep -qx 'replaces=(koompi-quickshell-git)' "$widgets" ||
    { echo 'FAIL: koompi-widgets must conflict with and replace the retired package' >&2; failed=1; }
grep -qx '  quickshell' "$widgets" ||
    { echo 'FAIL: koompi-widgets does not depend on quickshell' >&2; failed=1; }
grep -qx '        koompi-quickshell-git' "$DIST/install-deps.sh" ||
    { echo 'FAIL: install-deps.sh no longer removes an installed retired package' >&2; failed=1; }
exit "$failed"
