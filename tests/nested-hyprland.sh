#!/usr/bin/env bash
# sourced from the session script a headless KWin runs; aquamarine 0.15.1 never flushes a new output's requests
# unless KWin sends the client one more event, so a start with no output is redone (hyprwm/aquamarine#415)

nested_hyprland_locate() {
    local pid=$1 lock lock_pid socket
    for lock in "$XDG_RUNTIME_DIR"/hypr/*/hyprland.lock; do
        [[ -f $lock ]] || continue
        { read -r lock_pid; read -r socket; } < "$lock"
        [[ $lock_pid == "$pid" && -n $socket ]] || continue
        printf '%s %s\n' "$(basename -- "$(dirname -- "$lock")")" "$socket"
        return 0
    done
    return 1
}

nested_hyprland_has_output() {
    HYPRLAND_INSTANCE_SIGNATURE=$1 hyprctl monitors -j 2> /dev/null | jq -e 'length > 0' > /dev/null 2>&1
}

nested_hyprland_wait_gone() {
    local _ pid alive
    for _ in $(seq 1 50); do
        alive=0
        for pid in "$@"; do kill -0 "$pid" 2> /dev/null && alive=1; done
        (( alive )) || return 0
        sleep 0.1
    done
    return 1
}

# its children go first: a shell the hook started in it must not outlive it and answer the next one's ipc
nested_hyprland_stop() {
    local pid=$1 signature=$2 children=() child
    mapfile -t children < <(pgrep -P "$pid")
    for child in "${children[@]}"; do kill "$child" 2> /dev/null; done
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl dispatch 'hl.dsp.exit()' > /dev/null 2>&1
    nested_hyprland_wait_gone "$pid" "${children[@]}" && return 0
    kill "$pid" 2> /dev/null
    nested_hyprland_wait_gone "$pid" "${children[@]}" && return 0
    kill -9 "$pid" "${children[@]}" 2> /dev/null
}

# sets hypr_pid; once the new Hyprland lists an output, exports its HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY
nested_hyprland_start() {
    local config=$1 log=$2 polls=${NESTED_HYPRLAND_OUTPUT_POLLS:-50} attempts=10 attempt found signature socket _
    if ! grep -q 'no_update_news = true' "$config" || ! grep -q 'no_donation_nag = true' "$config"; then
        echo "nested Hyprland: $config must set ecosystem no_update_news and no_donation_nag, or a second start runs the update screen and crashes" >&2
        return 2
    fi
    unset HYPRLAND_INSTANCE_SIGNATURE
    for attempt in $(seq 1 "$attempts"); do
        printf -- '--- nested Hyprland start %s ---\n' "$attempt" >> "$log"
        Hyprland -c "$config" >> "$log" 2>&1 &
        hypr_pid=$!
        found=""
        for _ in $(seq 1 300); do
            found="$(nested_hyprland_locate "$hypr_pid")" && break
            kill -0 "$hypr_pid" 2> /dev/null || { echo "nested Hyprland: exited before it was ready, see $log" >&2; return 1; }
            sleep 0.1
        done
        [[ -n $found ]] || { kill "$hypr_pid" 2> /dev/null; echo "nested Hyprland: not ready after 30 s, see $log" >&2; return 1; }
        read -r signature socket <<< "$found"
        for _ in $(seq 1 "$polls"); do
            if nested_hyprland_has_output "$signature"; then
                export HYPRLAND_INSTANCE_SIGNATURE=$signature WAYLAND_DISPLAY=$socket
                return 0
            fi
            kill -0 "$hypr_pid" 2> /dev/null || { echo "nested Hyprland: exited while it had no output, see $log" >&2; return 1; }
            sleep 0.1
        done
        echo "nested Hyprland: no output $((polls / 10)).$((polls % 10)) s after start $attempt of $attempts" >&2
        nested_hyprland_stop "$hypr_pid" "$signature"
    done
    echo "nested Hyprland: giving up after $attempts starts without an output, see $log" >&2
    return 1
}
