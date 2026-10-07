#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

shopt -s nullglob
found=("$ROOT"/sdata/migrations/*-custom-keybind-descriptions.sh)
[[ ${#found[@]} -eq 1 ]] || { echo "expected one custom-keybind-descriptions migration, found ${#found[@]}" >&2; exit 1; }
MIGRATION="${found[0]}"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
unset XDG_CONFIG_HOME XDG_STATE_HOME KOOMPI_STATE_DIR
CONF="$HOME/.config/hypr/custom/keybinds.lua"
BACKUPS="$HOME/.local/state/koompi/backups"

fail() { echo "FAIL: $*" >&2; exit 1; }

expect_same() {
    diff -u -- "$1" "$2" >&2 || fail "$3"
}

fresh_home() {
    rm -rf -- "${TEST_ROOT:?}/home"
    mkdir -p "$HOME/.config/hypr/custom"
}

migrate() {
    local log="$TEST_ROOT/migration.log"
    bash -euo pipefail "$MIGRATION" > "$log" 2>&1 || { cat "$log" >&2; fail "the migration exited non-zero"; }
}

backup_count() {
    local files=("$BACKUPS"/*)
    echo "${#files[@]}"
}

as_shipped_before() {
    cat <<'LUA'
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Shell: Edit user keybinds"} )

-- Bare name on purpose: koompi-session prepends ~/.local/bin, so a hand-built kiri
-- wins over the koompi-kiri package in /usr/bin.
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation (AI key + Alt)" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription (AI key)" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("kiri cancel"), { description = "Kiri: Cancel dictation (Super+Esc)" })
-- kiri-gui is the Tauri settings app. koompi-kiri does not build it (see that
-- PKGBUILD); this bind only works where kiri-gui was installed by hand.
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("kiri-gui"), { description = "Kiri: Settings" })
LUA
}

as_shipped_after() {
    cat <<'LUA'
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Shell: Edit user keybinds"} )

-- Bare name on purpose: koompi-session prepends ~/.local/bin, so a hand-built kiri
-- wins over the koompi-kiri package in /usr/bin.
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("kiri cancel"), { description = "Kiri: Cancel dictation" })
-- kiri-gui is the Tauri settings app. koompi-kiri does not build it (see that
-- PKGBUILD); this bind only works where kiri-gui was installed by hand.
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("kiri-gui"), { description = "Kiri: Settings" })
LUA
}

as_first_release_before() {
    cat <<'LUA'
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Kiri voice dictation on the AI/Copilot key (Super+Shift+F23, code:201).
-- Plain AI key = English; add Alt for Khmer. Press once to start, again to
-- stop. The "Kiri: ..." descriptions group these in the cheatsheet.
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation (AI key + Alt)" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice"), { description = "Kiri: Voice transcription (AI key)" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.local/bin/kiri cancel"), { description = "Kiri: Cancel dictation (Super+Esc)" })
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri-gui"), { description = "Kiri: Settings" })
LUA
}

as_first_release_after() {
    cat <<'LUA'
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Shell: Edit user keybinds"} )

-- Kiri voice dictation on the AI/Copilot key (Super+Shift+F23, code:201).
-- Plain AI key = English; add Alt for Khmer. Press once to start, again to
-- stop. The "Kiri: ..." descriptions group these in the cheatsheet.
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice"), { description = "Kiri: Voice transcription" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.local/bin/kiri cancel"), { description = "Kiri: Cancel dictation" })
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri-gui"), { description = "Kiri: Settings" })
LUA
}

as_edited_by_the_user_before() {
    cat <<'LUA'
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- mine
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), {description = "Kiri: Khmer dictation (AI key + Alt)" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription (AI key)" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" }) -- Khmer
hl.bind("SUPER + CTRL + K", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription (AI key)" })
LUA
}

as_edited_by_the_user_after() {
    cat <<'LUA'
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Shell: Edit user keybinds"} )

-- mine
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), {description = "Kiri: Khmer dictation (AI key + Alt)" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" }) -- Khmer
hl.bind("SUPER + CTRL + K", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription (AI key)" })
LUA
}

fresh_home
as_shipped_before > "$CONF"
chmod 640 "$CONF"
cp -p -- "$CONF" "$TEST_ROOT/original"
migrate
as_shipped_after > "$TEST_ROOT/expected"
expect_same "$TEST_ROOT/expected" "$CONF" "the shipped lines were not reworded"
[[ "$(stat -c %a "$CONF")" == 640 ]] || fail "the file's mode changed"
[[ "$(backup_count)" -eq 1 ]] || fail "expected one backup, found $(backup_count)"
backup=("$BACKUPS"/*)
cmp -s -- "$TEST_ROOT/original" "${backup[0]}" || fail "the backup is not the file as it was"

settled="$(stat -c '%i %y' "$CONF"; sha256sum < "$CONF"; ls -1 "$BACKUPS")"
migrate
[[ "$settled" == "$(stat -c '%i %y' "$CONF"; sha256sum < "$CONF"; ls -1 "$BACKUPS")" ]] \
    || fail "a second run changed the file or the backups"

fresh_home
as_first_release_before > "$CONF"
migrate
as_first_release_after > "$TEST_ROOT/expected"
expect_same "$TEST_ROOT/expected" "$CONF" "the first release's lines were not reworded"

fresh_home
as_edited_by_the_user_before > "$CONF"
migrate
as_edited_by_the_user_after > "$TEST_ROOT/expected"
expect_same "$TEST_ROOT/expected" "$CONF" "an edited, deleted or added line was touched"

fresh_home
as_shipped_after > "$CONF"
migrate
expect_same <(as_shipped_after) "$CONF" "a file with nothing to reword changed"
[[ ! -e "$BACKUPS" ]] || fail "a backup was written with nothing to reword"

fresh_home
mkdir -p "$TEST_ROOT/dotfiles"
as_shipped_before > "$TEST_ROOT/dotfiles/keybinds.lua"
ln -s "$TEST_ROOT/dotfiles/keybinds.lua" "$CONF"
migrate
[[ -L "$CONF" ]] || fail "a symlinked file was replaced by a regular file"
as_shipped_after > "$TEST_ROOT/expected"
expect_same "$TEST_ROOT/expected" "$TEST_ROOT/dotfiles/keybinds.lua" "the symlink target was not reworded"

fresh_home
printf '%s' "$(as_shipped_before)" > "$CONF"
migrate
[[ -n "$(tail -c1 "$CONF")" ]] || fail "a file with no final newline gained one"
printf '%s' "$(as_shipped_after)" > "$TEST_ROOT/expected"
expect_same "$TEST_ROOT/expected" "$CONF" "a file with no final newline was not reworded"

rm -rf -- "${TEST_ROOT:?}/home"
mkdir -p "$HOME"
migrate
[[ -z "$(ls -A "$HOME")" ]] || fail "a home without the file gained files: $(ls -A "$HOME")"

printf 'migrate custom keybind descriptions tests passed\n'
