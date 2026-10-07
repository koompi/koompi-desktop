# shellcheck shell=bash
# shellcheck disable=SC2016  # the lines to match hold a literal $HOME
# hypr/custom/keybinds.lua is user-owned and never synced; reword shipped lines there, exact matches only
conf="$HOME/.config/hypr/custom/keybinds.lua"
[[ -f "$conf" ]] || exit 0
conf="$(readlink -f -- "$conf")"

shipped=()
reworded=()
reword() {
    shipped+=("$1")
    reworded+=("$2")
}

reword 'hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )' \
       'hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Shell: Edit user keybinds"} )'

reword 'hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation (AI key + Alt)" })' \
       'hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation" })'
reword 'hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription (AI key)" })' \
       'hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription" })'
reword 'hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" })' \
       'hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation" })'
reword 'hl.bind("SUPER + Escape", hl.dsp.exec_cmd("kiri cancel"), { description = "Kiri: Cancel dictation (Super+Esc)" })' \
       'hl.bind("SUPER + Escape", hl.dsp.exec_cmd("kiri cancel"), { description = "Kiri: Cancel dictation" })'

# the first release called kiri through $HOME/.local/bin
reword 'hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation (AI key + Alt)" })' \
       'hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation" })'
reword 'hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice"), { description = "Kiri: Voice transcription (AI key)" })' \
       'hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice"), { description = "Kiri: Voice transcription" })'
reword 'hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" })' \
       'hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation" })'
reword 'hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.local/bin/kiri cancel"), { description = "Kiri: Cancel dictation (Super+Esc)" })' \
       'hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.local/bin/kiri cancel"), { description = "Kiri: Cancel dictation" })'

rewritten=""
changed=0
while IFS= read -r line || [[ -n "$line" ]]; do
    for i in "${!shipped[@]}"; do
        if [[ "$line" == "${shipped[i]}" ]]; then
            line="${reworded[i]}"
            changed=$((changed + 1))
            break
        fi
    done
    rewritten+="$line"$'\n'
done < "$conf"
(( changed )) || exit 0
[[ -z "$(tail -c1 -- "$conf")" ]] || rewritten="${rewritten%$'\n'}"

tmp="$(mktemp -- "$conf.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
backups="${KOOMPI_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/koompi}/backups"
mkdir -p -- "$backups"
backup="$backups/migrate-$(date +%Y%m%d-%H%M%S)-config_hypr_custom_keybinds.lua"
cp -p -- "$conf" "$backup"
printf '%s' "$rewritten" > "$tmp"
chmod --reference="$conf" -- "$tmp"
mv -f -- "$tmp" "$conf"
echo "hypr/custom/keybinds.lua: reworded $changed shipped line(s); backup ${backup/#$HOME/\~}"
