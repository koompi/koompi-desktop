# shellcheck shell=bash
# the shipped theme may be absent (--no-deps, a failed build or fetch); naming it then blanks every app icon
icon_theme_for() {
    local want="koompi-icons" fallback="breeze-plus" dir
    [[ "$1" == dark ]] && { want="koompi-icons-dark"; fallback="breeze-plus-dark"; }
    local -a dirs
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${dirs[@]/%//icons}" "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons"; do
        [[ -f "$dir/$want/index.theme" ]] && { printf '%s\n' "$want"; return 0; }
    done
    printf '%s\n' "$fallback"
}

# the theme the shell draws from: its Qt reads qt6ct.conf when qt6ct is the platform theme (env.lua), else kdeglobals
active_icon_theme() {
    local config="${XDG_CONFIG_HOME:-$HOME/.config}" theme="${QS_ICON_THEME:-}"
    if [[ -z "$theme" && "${QT_QPA_PLATFORMTHEME:-}" == qt6ct* ]]; then
        theme="$(awk -F= '/^\[/ { s = $0 } s == "[Appearance]" && $1 == "icon_theme" { print $2 }' "$config/qt6ct/qt6ct.conf" 2> /dev/null)"
    fi
    [[ -n "$theme" ]] || theme="$(awk -F= '/^\[/ { s = $0 } s == "[Icons]" && $1 == "Theme" { print $2 }' "$config/kdeglobals" 2> /dev/null)"
    printf '%s\n' "$theme"
}
