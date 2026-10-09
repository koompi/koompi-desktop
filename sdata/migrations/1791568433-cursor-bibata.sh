# shellcheck shell=bash
# the cursor moved from Adwaita to Bibata-Modern-Classic; only a user still on the shipped value moves, any other pick stays
theme=Bibata-Modern-Classic

# naming a missing cursor theme makes every toolkit pick its own stand-in; hyprland/env.lua keeps Adwaita until it lands
installed() {
    local dir
    local -a dirs
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${dirs[@]/%//icons}" "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons"; do
        [[ -f "$dir/$1/index.theme" ]] && return 0
    done
    return 1
}
if ! installed "$theme"; then
    echo "$theme is not installed; cursor left as it is (run ./setup install --only-deps)"
    exit 0
fi

current=""
if command -v gsettings >/dev/null 2>&1; then
    current="$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true)"
fi

# the fallback X11 clients with no theme of their own follow; a packaged install has only the system copy, which is Adwaita
index="$HOME/.icons/default/index.theme"
if [[ -f "$index" ]]; then
    if grep -qx 'Inherits=Adwaita' "$index"; then
        tmp="$(mktemp -- "$index.XXXXXX")"
        sed 's/^Inherits=Adwaita$/Inherits='"$theme"'/' "$index" > "$tmp"
        cat "$tmp" > "$index"
        rm -f -- "$tmp"
        echo "~/.icons/default: cursor fallback now $theme"
    fi
elif [[ "$current" == "'Adwaita'" ]]; then
    mkdir -p "$HOME/.icons/default"
    printf '[Icon Theme]\nInherits=%s\n' "$theme" > "$index"
    echo "~/.icons/default: cursor fallback now $theme"
fi

if [[ "$current" == "'Adwaita'" ]]; then
    gsettings set org.gnome.desktop.interface cursor-theme "$theme"
    echo "gsettings: cursor theme now $theme"
fi
