#!/usr/bin/env bash
# AppIconBodies.qml: the theme the shell draws from on the first line, then the app and device icons that theme draws itself
source "$(dirname -- "${BASH_SOURCE[0]}")/icon_theme.sh"

theme="$(active_icon_theme)"
echo "$theme"
[[ -n $theme ]] || exit 0
IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for base in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons" "${dirs[@]/%//icons}"; do
    [[ -d $base/$theme ]] || continue
    for category in apps devices; do ls -1 "$base/$theme/$category/scalable" 2> /dev/null; done | sed 's/\.[^.]*$//'
    break
done
