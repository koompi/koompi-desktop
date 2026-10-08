# shellcheck shell=bash
# skel seeds new users only and the sync skips systemd/user and autostart, so existing homes lack both
config="${XDG_CONFIG_HOME:-$HOME/.config}"
[[ -f "$config/hypr/hyprland/execs.lua" ]] || exit 0
backups="${KOOMPI_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/koompi}/backups"
tmp=""
trap '[[ -z "$tmp" ]] || rm -f -- "$tmp"' EXIT

place() {
    local mode="$1" rel="$2" path="$config/$2" content backup=""
    content="$(cat)"
    if [[ -e "$path" || -L "$path" ]]; then
        [[ "$mode" == replace ]] || return 0
        if cmp -s <(printf '%s\n' "$content") "$path"; then
            return 0
        fi
        mkdir -p -- "$backups"
        backup="$backups/migrate-$(date +%Y%m%d-%H%M%S)-config_${rel//\//_}"
        cp -a -- "$path" "$backup"
    else
        mkdir -p -- "$(dirname -- "$path")"
    fi
    tmp="$(mktemp -- "$path.XXXXXX")"
    printf '%s\n' "$content" > "$tmp"
    chmod 644 -- "$tmp"
    mv -fT -- "$tmp" "$path"
    tmp=""
    if [[ -n "$backup" ]]; then
        echo "$rel: replaced; yours is at ${backup/#$HOME/\~}"
    else
        echo "$rel: written"
    fi
}

place replace systemd/user/hyprland-session.target <<'UNIT'
[Unit]
Description=Hyprland compositor session
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
# login items: xdg-desktop-autostart.target refuses a manual start, so the session wants it
Wants=xdg-desktop-autostart.target
UNIT

place keep autostart/nm-applet.desktop <<'DESKTOP'
[Desktop Entry]
# hidden: the shell has its own network panel; Hidden=false starts the applet at login
Type=Application
Name=NetworkManager Applet
Exec=nm-applet
Hidden=true
DESKTOP

place keep autostart/geoclue-demo-agent.desktop <<'DESKTOP'
[Desktop Entry]
# hidden: Weather starts the agent when it needs a location; Hidden=false starts it at login
Type=Application
Name=Geoclue Demo agent
Exec=/usr/lib/geoclue-2.0/demos/agent
Hidden=true
DESKTOP

place keep autostart/org.kde.kdeconnect.daemon.desktop <<'DESKTOP'
[Desktop Entry]
# hidden: kdeconnectd starts when KDE Connect opens; Hidden=false starts it at login
Type=Application
Name=KDE Connect
Exec=/usr/bin/kdeconnectd
Hidden=true
DESKTOP
