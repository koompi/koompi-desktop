#!/usr/bin/env bash
# PSS of a headless shell with each KoompiFamily loader removed in turn.
#   measure_surfaces.sh SHELL_ROOT OUT.tsv [LOADER_NAME...]
# No names: full shell, resident-only (Bar Background NotificationPopup OnScreenDisplay Lock), then each loader alone removed.
set -euo pipefail
[[ -n ${KOOMPI_HEAVY_LOCKED:-} ]] || exec "$(dirname -- "${BASH_SOURCE[0]}")/heavy.sh" "${BASH_SOURCE[0]}" "$@"

root=$(realpath "$1"); out=$(realpath -m "$2"); shift 2
family="$root/panelFamilies/KoompiFamily.qml"
mapfile -t all < <(grep -oP 'component: \K[A-Za-z]+' "$family")
resident=(Bar Background NotificationPopup OnScreenDisplay Lock)

run_variant() { # label, names to drop...
    local label=$1; shift
    local work tree pss
    work=$(mktemp -d)
    tree="$work/shell"
    mkdir -p "$tree/panelFamilies" "$work/xdg/config/koompi" "$work/xdg/state/quickshell/user" "$work/xdg/cache" "$work/xdg/data" "$work/bin" "$work/home" "$work/rt"
    chmod 700 "$work/rt"
    if [[ -d $HOME/.local/share/fonts ]]; then ln -s "$HOME/.local/share/fonts" "$work/xdg/data/fonts"; fi
    for entry in "$root"/*; do
        [[ $(basename -- "$entry") == panelFamilies ]] && continue
        ln -s "$entry" "$tree/$(basename -- "$entry")"
    done
    for entry in "$root"/panelFamilies/*; do ln -s "$entry" "$tree/panelFamilies/$(basename -- "$entry")"; done
    rm "$tree/panelFamilies/KoompiFamily.qml"
    local pattern=""
    for name in "$@"; do pattern+="${pattern:+|}component: $name \\{"; done
    if [[ -n $pattern ]]; then grep -vE "$pattern" "$family" > "$tree/panelFamilies/KoompiFamily.qml"
    else cp "$family" "$tree/panelFamilies/KoompiFamily.qml"; fi
    echo greeted > "$work/xdg/state/quickshell/user/first_run.txt"
    echo '{"windows": {"workspaceHelp": false}}' > "$work/xdg/config/koompi/config.json"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$work/bin/koompi-shelld"; chmod +x "$work/bin/koompi-shelld"
    cat > "$work/inner.sh" <<SH
#!/usr/bin/env bash
unset HYPRLAND_INSTANCE_SIGNATURE
setsid qs -p "$tree" > "$work/qs.log" 2>&1 &
pid=\$!
sleep 25
awk '/^Pss:/ {print \$2}' /proc/\$pid/smaps_rollup > "$work/pss"
kill -- -\$pid 2>/dev/null || kill \$pid
sleep 1
SH
    chmod +x "$work/inner.sh"
    env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY \
        PATH="$work/bin:$PATH" KOOMPI_SHELLD="$work/bin/koompi-shelld" QT_QPA_PLATFORM=wayland HOME="$work/home" XDG_RUNTIME_DIR="$work/rt" \
        XDG_CONFIG_HOME="$work/xdg/config" XDG_STATE_HOME="$work/xdg/state" XDG_CACHE_HOME="$work/xdg/cache" XDG_DATA_HOME="$work/xdg/data" \
        timeout 90 dbus-run-session --config-file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/tests/private-bus.conf" -- kwin_wayland --virtual --width 1920 --height 1200 \
            --no-lockscreen --no-global-shortcuts --exit-with-session "$work/inner.sh" > "$work/kwin.log" 2>&1 || true
    pss=$(cat "$work/pss" 2>/dev/null || echo NA)
    printf '%s\t%s\n' "$label" "$pss" | tee -a "$out"
    if [[ $pss == NA ]]; then echo "kept $work" >&2; else rm -rf "$work" 2>/dev/null || true; fi
}

: > "$out"
if (( $# )); then run_variant "drop:$*" "$@"; exit 0; fi
run_variant full
lazy=()
for name in "${all[@]}"; do
    [[ " ${resident[*]} " == *" $name "* ]] || lazy+=("$name")
done
run_variant resident-only "${lazy[@]}"
for name in "${lazy[@]}"; do run_variant "drop:$name" "$name"; done
