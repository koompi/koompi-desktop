#!/usr/bin/env bash
# The icon theme is named in several files that cannot read each other. When they
# drift the session shows two icon sets, or the dock blanks because otto matches
# themes on index.theme Name= and not on Inherits=.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/dots/.config/kde-material-you-colors/config.conf"
ICONFN="$ROOT/dots/.config/quickshell/koompi/scripts/colors/icon_theme.sh"
PKG="$ROOT/sdata/dist-arch/koompi-icons"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

light=koompi-icons
dark=koompi-icons-dark

grep -qF "want=\"$light\"" "$ICONFN" || fail "icon_theme.sh light icon_theme_for is not $light"
grep -qF "want=\"$dark\"" "$ICONFN" || fail "icon_theme.sh dark icon_theme_for is not $dark"
grep -qx "iconslight = $light" "$CONF" || fail "kde-material-you-colors iconslight is not $light"
grep -qx "iconsdark = $dark" "$CONF" || fail "kde-material-you-colors iconsdark is not $dark"
if grep -n "breeze-plus" "$CONF" >/dev/null; then fail "a breeze-plus name is left in config.conf"; fi

# the theme directories the build script lays down are the names above
grep -qF "Name=$light/" "$PKG/build-theme.sh" || fail "build-theme.sh does not set Name=$light"
grep -qF "Name=$dark/" "$PKG/build-theme.sh" || fail "build-theme.sh does not set Name=$dark"

# the install installs it, from git and from packages
grep -qx '    koompi-icons' "$ROOT/sdata/dist-arch/install-deps.sh" || fail "install-deps.sh does not build koompi-icons"
grep -qx '  koompi-icons' "$ROOT/sdata/dist-arch/koompi-base/PKGBUILD" || fail "koompi-base does not depend on koompi-icons"

# one pinned, checksummed release
grep -qP '^_tag=.+' "$PKG/PKGBUILD" || fail "the koompi-icons PKGBUILD pins no release"
grep -qP "^sha256sums=\('[0-9a-f]{64}" "$PKG/PKGBUILD" || fail "the koompi-icons PKGBUILD has no checksum"

echo "ok"
