#!/usr/bin/env bash
# Builds the koompi-icons package in a temp dir (nothing is installed) and checks
# the built tree: otto matches icon themes on index.theme Name=, so it has to equal
# the directory name.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/sdata/dist-arch/koompi-icons"

command -v makepkg >/dev/null 2>&1 || { echo "skipping: no makepkg"; exit 0; }
command -v gtk-update-icon-cache >/dev/null 2>&1 || { echo "skipping: no gtk-update-icon-cache"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tag="$(grep -oP '^_tag=\K.+' "$PKG/PKGBUILD")"
cp -- "$PKG/PKGBUILD" "$PKG/build-theme.sh" "$TMP/"
tarball="${KOOMPI_ICONS_TARBALL:-}"
if [[ -n "$tarball" && -f "$tarball" ]]; then
    cp -- "$tarball" "$TMP/WhiteSur-icon-theme-$tag.tar.gz"
else
    curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/WhiteSur-icon-theme-$tag.tar.gz" \
        "https://github.com/vinceliuice/WhiteSur-icon-theme/archive/refs/tags/$tag.tar.gz" \
        || { echo "skipping: cannot fetch the upstream release"; exit 0; }
fi

(cd "$TMP" && makepkg -f --nodeps --noconfirm >"$TMP/makepkg.log" 2>&1) \
    || { tail -20 "$TMP/makepkg.log" >&2; fail "makepkg failed"; }

icons="$TMP/pkg/koompi-icons/usr/share/icons"
for d in koompi-icons koompi-icons-dark; do
    [[ -f "$icons/$d/index.theme" ]] || fail "$d has no index.theme"
    name="$(grep -oP '^Name=\K.+' "$icons/$d/index.theme")"
    [[ "$name" == "$d" ]] || fail "$d/index.theme says Name=$name"
    grep -q '^Inherits=.*breeze' "$icons/$d/index.theme" || fail "$d does not inherit breeze"
done
[[ ! -e "$icons/koompi-icons-green" ]] || fail "an upstream -green directory was left behind"
[[ -z "$(find "$icons" -xtype l -print -quit)" ]] || fail "dangling symlink: $(find "$icons" -xtype l -print -quit)"
grep -rq WhiteSur "$icons"/*/index.theme && fail "index.theme still names WhiteSur"
[[ -f "$TMP/pkg/koompi-icons/usr/share/licenses/koompi-icons/COPYING" ]] || fail "license file not installed"

echo "ok"
