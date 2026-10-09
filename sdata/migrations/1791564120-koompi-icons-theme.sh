# shellcheck shell=bash
# the icon theme moved from breeze-plus to koompi-icons; only a user still on the shipped value moves, any other pick stays
config="${XDG_CONFIG_HOME:-$HOME/.config}"

# without the theme on disk the move blanks every app icon; switchwall.sh moves the user at the next wallpaper or mode change once it lands
installed() {
    local dir
    local -a dirs
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${dirs[@]/%//icons}" "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons"; do
        [[ -f "$dir/$1/index.theme" ]] && return 0
    done
    return 1
}
if ! installed koompi-icons && ! installed koompi-icons-dark; then
    echo "koompi-icons is not installed; icon theme left as it is (run ./setup install --only-deps)"
    exit 0
fi

rewrite() {
    local file="$1" expr="$2"
    [[ -f "$file" ]] || return 0
    local tmp
    tmp="$(mktemp -- "$file.XXXXXX")"
    sed -E "$expr" "$file" > "$tmp"
    if cmp -s "$tmp" "$file"; then
        rm -f -- "$tmp"
        return 0
    fi
    cat "$tmp" > "$file"
    rm -f -- "$tmp"
    echo "${file/#$HOME/\~}: icon theme now koompi-icons"
}

rewrite "$config/kdeglobals" '/^\[Icons\]/,/^\[/ s/^Theme=breeze-plus(-dark)?[[:space:]]*$/Theme=koompi-icons\1/'
rewrite "$config/qt6ct/qt6ct.conf" 's/^icon_theme=breeze-plus(-dark)?[[:space:]]*$/icon_theme=koompi-icons\1/'
rewrite "$config/kde-material-you-colors/config.conf" 's/^(iconslight|iconsdark) = breeze-plus(-dark)?[[:space:]]*$/\1 = koompi-icons\2/'

if command -v gsettings >/dev/null 2>&1; then
    current="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)"
    case "$current" in
        "'breeze-plus'") gsettings set org.gnome.desktop.interface icon-theme 'koompi-icons' ;;
        "'breeze-plus-dark'") gsettings set org.gnome.desktop.interface icon-theme 'koompi-icons-dark' ;;
    esac
fi
