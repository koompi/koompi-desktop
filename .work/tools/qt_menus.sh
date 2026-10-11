#!/usr/bin/env bash
# Per Qt app: launch-to-window time on xcb and wayland, and whether its menubar reaches the AppMenu registrar.
#   qt_menus.sh APP_BINARY CLASS_SUBSTRING
# Kills only the pid Hyprland reports for the window it timed.
set -uo pipefail
app=$1; cls=$2

window_pid() {
    hyprctl clients -j | jq -r --arg c "$cls" \
        '[.[] | select(.class | ascii_downcase | contains($c | ascii_downcase))][0].pid // empty'
}

wpid=""; elapsed=""
launch() { # platform -> sets $elapsed and $wpid
    local platform=$1 start end
    start=$(date +%s.%N)
    env QT_QPA_PLATFORM="$platform" setsid -f "$app" >/dev/null 2>&1
    wpid=""
    for _ in $(seq 1 300); do wpid=$(window_pid); [[ -n $wpid ]] && break; sleep 0.05; done
    end=$(date +%s.%N)
    [[ -n $wpid ]] || return 1
    elapsed=$(echo "$end - $start" | bc)
}

menu_items() { # pid -> top-level dbusmenu item labels registered for that pid
    local id bus path owner
    while read -r id bus path; do
        owner=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
            GetConnectionUnixProcessID s "$bus" 2>/dev/null | awk '{print $2}')
        [[ $owner == "$1" ]] || continue
        busctl --user --json=short call "$bus" "$path" com.canonical.dbusmenu GetLayout iias 0 1 1 label 2>/dev/null \
            | jq -r '[.data[1][2][] | .data[1].label.data // empty] | map(gsub("&"; "")) | join(",")'
        return 0
    done < <(busctl --user --json=short call com.canonical.AppMenu.Registrar /com/canonical/AppMenu/Registrar \
        com.canonical.AppMenu.Registrar GetMenus | jq -r '.data[0][] | "\(.[0]) \(.[1]) \(.[2])"')
    echo "-"
}

[[ -n $cls && -z $(window_pid) ]] || { echo "$app: class empty or a $cls window is already open; skipped"; exit 2; }
for platform in xcb wayland; do
    launch "$platform" || { echo "$app $platform TIMEOUT"; continue; }
    sleep 2
    menus="n/a"
    [[ $platform == xcb ]] && menus=$(menu_items "$wpid")
    printf '%s\t%s\t%.2fs\tmenus=%s\n' "$app" "$platform" "$elapsed" "$menus"
    kill "$wpid" 2>/dev/null; sleep 1.5
done
