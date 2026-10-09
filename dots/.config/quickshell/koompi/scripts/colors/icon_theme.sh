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
