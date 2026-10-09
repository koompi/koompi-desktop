#!/usr/bin/env bash
# The icon theme is named in several files that cannot read each other. When they
# drift the session shows two icon sets, or the dock blanks because otto matches
# themes on index.theme Name= and not on Inherits=.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SWITCH="$ROOT/dots/.config/quickshell/koompi/scripts/colors/switchwall.sh"
CONF="$ROOT/dots/.config/kde-material-you-colors/config.conf"
PKG="$ROOT/sdata/dist-arch/koompi-icons"
FROM_SOURCE="$ROOT/sdata/lib/from-source.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

light=koompi-icons
dark=koompi-icons-dark

grep -qF "want=\"$light\"" "$SWITCH" || fail "switchwall.sh light icon_theme_for is not $light"
grep -qF "want=\"$dark\"" "$SWITCH" || fail "switchwall.sh dark icon_theme_for is not $dark"
grep -qx "iconslight = $light" "$CONF" || fail "kde-material-you-colors iconslight is not $light"
grep -qx "iconsdark = $dark" "$CONF" || fail "kde-material-you-colors iconsdark is not $dark"
if grep -n "breeze-plus" "$CONF" >/dev/null; then fail "a breeze-plus name is left in config.conf"; fi

# the theme directories the build script lays down are the names above
grep -qF "Name=$light/" "$PKG/build-theme.sh" || fail "build-theme.sh does not set Name=$light"
grep -qF "Name=$dark/" "$PKG/build-theme.sh" || fail "build-theme.sh does not set Name=$dark"

# every install route installs it
grep -qx '    koompi-icons' "$ROOT/sdata/dist-arch/install-deps.sh" || fail "install-deps.sh does not build koompi-icons"
grep -qx '  koompi-icons' "$ROOT/sdata/dist-arch/koompi-base/PKGBUILD" || fail "koompi-base does not depend on koompi-icons"
grep -qx 'install_koompi_icons' "$ROOT/sdata/dist-debian/install-deps.sh" || fail "the Debian recipe does not install koompi-icons"
grep -qx 'install_koompi_icons' "$ROOT/sdata/dist-fedora/install-deps.sh" || fail "the Fedora recipe does not install koompi-icons"
grep -qF "| \`koompi-icons\` |" "$ROOT/sdata/dist-debian/README.md" || fail "the Debian README has no koompi-icons row"

# one pinned release for every route
pkg_tag="$(grep -oP '^_tag=\K.+' "$PKG/PKGBUILD")"
pkg_sha="$(grep -oP "^sha256sums=\('\K[0-9a-f]{64}" "$PKG/PKGBUILD")"
src_tag="$(grep -oP '^KOOMPI_ICONS_TAG=\K.+' "$FROM_SOURCE")"
src_sha="$(grep -oP '^KOOMPI_ICONS_SHA256=\K.+' "$FROM_SOURCE")"
[[ -n "$pkg_tag" && "$pkg_tag" == "$src_tag" ]] || fail "PKGBUILD pins $pkg_tag but from-source.sh pins $src_tag"
[[ -n "$pkg_sha" && "$pkg_sha" == "$src_sha" ]] || fail "PKGBUILD and from-source.sh pin different checksums"

echo "ok"
