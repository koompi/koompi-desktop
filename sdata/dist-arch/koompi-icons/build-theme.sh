#!/usr/bin/env bash
# Turns an unpacked WhiteSur-icon-theme release into the koompi-icons and
# koompi-icons-dark themes, called by the PKGBUILD.
#   build-theme.sh <unpacked release dir> <icons dir to install into>
set -euo pipefail

src="${1:?usage: build-theme.sh SRC_DIR ICONS_DIR}"
icons="${2:?usage: build-theme.sh SRC_DIR ICONS_DIR}"

shim="$(mktemp -d)"
trap 'rm -rf "$shim"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$shim/gtk-update-icon-cache"
chmod +x "$shim/gtk-update-icon-cache"

mkdir -p "$icons"
# upstream names a variant <name>-green; the theme has to be called koompi-icons
# because otto matches icon themes on index.theme Name=, not on Inherits=
PATH="$shim:$PATH" "$src/install.sh" -d "$icons" -n koompi-icons -t green >/dev/null
rm -rf "$icons/koompi-icons-green-light" "$icons/koompi-icons" "$icons/koompi-icons-dark"
mv "$icons/koompi-icons-green" "$icons/koompi-icons"
mv "$icons/koompi-icons-green-dark" "$icons/koompi-icons-dark"

while IFS= read -r -d '' link; do
    target="$(readlink "$link")"
    ln -sfn "${target//koompi-icons-green/koompi-icons}" "$link"
done < <(find "$icons/koompi-icons" "$icons/koompi-icons-dark" -type l -lname '*koompi-icons-green*' -print0)

sed -i -e 's/^Name=.*/Name=koompi-icons/' -e 's/^Inherits=.*/Inherits=breeze,hicolor/' \
    "$icons/koompi-icons/index.theme"
sed -i -e 's/^Name=.*/Name=koompi-icons-dark/' -e 's/^Inherits=.*/Inherits=breeze-dark,breeze,hicolor/' \
    "$icons/koompi-icons-dark/index.theme"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    for theme in koompi-icons koompi-icons-dark; do
        gtk-update-icon-cache -f -t "$icons/$theme" >/dev/null
    done
fi
