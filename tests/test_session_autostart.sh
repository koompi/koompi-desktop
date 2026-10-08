#!/usr/bin/env bash
# The session opts into XDG autostart. hyprland-session.target ships in dots/ and
# wants xdg-desktop-autostart.target, which refuses a manual start, so nothing in the
# tree may start it by hand. Three login items KOOMPI does not want are hidden by
# same-named overrides in ~/.config/autostart that survive an update, and existing
# homes get all four files from a migration. Offline: the systemd generator writes
# into temp dirs and nothing here talks to a user manager.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/dots/.config/systemd/user/hyprland-session.target"
AUTOSTART="$ROOT/dots/.config/autostart"
GENERATOR=/usr/lib/systemd/user-generators/systemd-xdg-autostart-generator
HIDDEN=(nm-applet geoclue-demo-agent org.kde.kdeconnect.daemon)

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

T="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT

unit_values() {
    awk -F= -v key="$2" '
        /^\[/ { in_unit = ($0 == "[Unit]") }
        { name = $1; gsub(/[ \t]/, "", name) }
        in_unit && name == key { sub(/^[^=]*=/, ""); n = split($0, v, " "); for (i = 1; i <= n; i++) print v[i] }
    ' "$1"
}
has_value() { unit_values "$1" "$2" | grep -qxF -- "$3"; }

# --- the session target ---
[[ -f "$TARGET" ]] || fail "dots/.config/systemd/user/hyprland-session.target is not shipped; a fresh install cannot start it, so graphical-session.target never activates and hypridle, the crash watcher and the portals never start"
has_value "$TARGET" BindsTo graphical-session.target || fail "the session target does not bind graphical-session.target"
has_value "$TARGET" Wants graphical-session-pre.target || fail "the session target does not want graphical-session-pre.target"
has_value "$TARGET" After graphical-session-pre.target || fail "the session target is not ordered after graphical-session-pre.target"
has_value "$TARGET" Wants xdg-desktop-autostart.target || fail "the session target does not want xdg-desktop-autostart.target, so no login item starts"
echo "ok   static: the session target binds graphical-session.target and wants xdg-desktop-autostart.target"

if command -v systemd-analyze > /dev/null 2>&1; then
    mkdir -p "$T/verify/home" "$T/verify/config" "$T/verify/data" "$T/verify/run"
    chmod 700 "$T/verify/run"
    verify_out="$(env -i PATH="$PATH" HOME="$T/verify/home" XDG_CONFIG_HOME="$T/verify/config" \
        XDG_DATA_HOME="$T/verify/data" XDG_RUNTIME_DIR="$T/verify/run" XDG_CONFIG_DIRS=/etc/xdg \
        systemd-analyze --user verify "$TARGET" 2>&1)" \
        || fail "systemd-analyze --user verify rejects the session target: $verify_out"
    [[ -z "$verify_out" ]] \
        || fail "systemd-analyze --user verify has something to say about the session target (it exits 0 on a typo like Wantz=, so any output fails): $verify_out"
    echo "ok   systemd-analyze --user verify: the session target loads without a word"
else
    echo "skip: systemd-analyze is not installed; the session target's syntax was not verified"
fi

hand_start="$(git -C "$ROOT" grep --no-color -nIE 'systemctl[^&|;]*(start|restart|isolate)[^&|;]*xdg-desktop-autostart' \
    -- . ':(exclude)tests' ':(exclude)docs' ':(exclude).work' 2>&1)"
(( $? <= 1 )) || fail "git grep failed: $hand_start"
[[ -z "$hand_start" ]] || fail "something starts xdg-desktop-autostart.target by hand; it has RefuseManualStart=yes, so the start is refused and the session target has to want it instead:
$hand_start"
echo "ok   static: nothing in the tree starts xdg-desktop-autostart.target by hand"

# --- the overrides that hide three login items ---
for f in "$AUTOSTART"/*; do
    [[ -e "$f" ]] || continue
    printf '%s\n' "${HIDDEN[@]/%/.desktop}" | grep -qxF -- "${f##*/}" \
        || fail "dots/.config/autostart/${f##*/} is not one of the hidden login items; a shipped entry that is not hidden starts for everyone, so add it to HIDDEN here on purpose"
done
for name in "${HIDDEN[@]}"; do
    entry="$AUTOSTART/$name.desktop"
    [[ -f "$entry" ]] || fail "dots/.config/autostart/$name.desktop is not shipped, so $name starts at login"
    grep -qx '\[Desktop Entry\]' "$entry" || fail "$entry has no [Desktop Entry] group"
    grep -qx 'Hidden=true' "$entry" || fail "$entry is not Hidden=true"
    grep -qE '^Exec=.' "$entry" || fail "$entry has no Exec=; it replaces the system entry rather than merging with it, so a user who flips it to Hidden=false needs the whole entry"
done
echo "ok   static: ${#HIDDEN[@]} overrides, each a complete entry with Hidden=true"

# --- the install route: written once, an edit survives an update ---
if ! command -v rsync > /dev/null 2>&1; then
    echo "skip: rsync not installed; the install route was not run"
else
    REPO="$T/repo"
    mkdir -p "$REPO/dots/.config/systemd/user" "$REPO/dots/.local/bin" "$REPO/dots/.local/share/koompi"
    cp -a -- "$TARGET" "$REPO/dots/.config/systemd/user/"
    cp -a -- "$AUTOSTART" "$REPO/dots/.config/autostart"
    touch "$REPO/dots/.local/bin/koompi-x" "$REPO/dots/.local/share/koompi/x"

    install_into() {
        (
            export HOME="$1" DRY_RUN=false ASSUME_YES=true NO_COLOR=1 SKIP_BACKUP=false REPO_ROOT="$REPO"
            unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_BIN_HOME XDG_CACHE_HOME BACKUP_ROOT KOOMPI_STATE_DIR
            source "$ROOT/sdata/lib/common.sh"
            source "$ROOT/sdata/install/files.sh"
            install_files
        ) > "$T/install.out" 2>&1 || fail "install_files failed: $(tail -5 "$T/install.out")"
    }
    snapshot() { (cd -- "$1/.config" && find . -type f -exec md5sum {} + | sort -k2); }

    H="$T/home-install"
    mkdir -p "$H"
    install_into "$H"
    cmp -s -- "$H/.config/systemd/user/hyprland-session.target" "$TARGET" || fail "setup does not install the session target"
    for name in "${HIDDEN[@]}"; do
        cmp -s -- "$H/.config/autostart/$name.desktop" "$AUTOSTART/$name.desktop" || fail "setup does not install the $name override"
        grep -qxF -- "$H/.config/autostart/$name.desktop" "$H/.local/state/koompi/installed-files" \
            || fail "the $name override is not in the manifest, so uninstall would leave it"
    done
    echo "ok   setup: a fresh home gets the session target and the overrides, and the manifest records them"

    for name in "${HIDDEN[@]}"; do
        printf '[Desktop Entry]\n# mine\nType=Application\nName=%s\nExec=true\nHidden=false\n' "$name" > "$H/.config/autostart/$name.desktop"
    done
    before="$(snapshot "$H")"
    install_into "$H"
    for name in "${HIDDEN[@]}"; do
        grep -qx 'Hidden=false' "$H/.config/autostart/$name.desktop" \
            || fail "an update rewrote the edited $name override; it is not in KEEP_PATHS (sdata/install/files.sh)"
        grep -q "keeping your .config/autostart/$name.desktop" "$T/install.out" || fail "the install did not say it kept the edited $name override"
    done
    [[ "$(snapshot "$H")" == "$before" ]] || fail "an update changed a home whose overrides were edited"
    echo "ok   setup: an edited override survives an update, and a second update changes nothing"

    rm -- "$H/.config/autostart/${HIDDEN[0]}.desktop"
    install_into "$H"
    cmp -s -- "$H/.config/autostart/${HIDDEN[0]}.desktop" "$AUTOSTART/${HIDDEN[0]}.desktop" \
        || fail "a deleted override is not written again; the docs say to edit it, not delete it, because it comes back"
    echo "ok   setup: a deleted override comes back, which is why the docs say to edit it"
fi

# --- the generator: what the user manager would start at login ---
if [[ ! -x "$GENERATOR" ]]; then
    echo "skip: $GENERATOR is not installed; the login items were not generated"
else
    generate() { # <XDG_CONFIG_HOME> <system dir> <out dir>
        mkdir -p "$1" "$3/normal" "$3/early" "$3/late" "$3/home"
        env -i PATH="$PATH" HOME="$3/home" XDG_CONFIG_HOME="$1" XDG_CONFIG_DIRS="$2" \
            "$GENERATOR" "$3/normal" "$3/early" "$3/late" > "$3/generator.log" 2>&1 \
            || fail "the generator failed: $(cat "$3/generator.log")"
    }
    generated() { # <out dir>: the desktop files that got a unit
        find "$1" -name 'app-*@autostart.service' -type f -exec sed -n 's|^SourcePath=.*/||p' {} + | LC_ALL=C sort
    }

    SYS="$T/system-xdg"
    mkdir -p "$SYS/autostart"
    fixture() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=/usr/bin/true\n%s' "$2" "$3" > "$SYS/autostart/$1.desktop"; }
    fixture nm-applet "NetworkManager Applet" $'NotShowIn=KDE;GNOME;\n'
    fixture geoclue-demo-agent "Geoclue Demo agent" $'NotShowIn=GNOME;\n'
    fixture org.kde.kdeconnect.daemon "KDE Connect" ''
    fixture org.fcitx.Fcitx5 "Fcitx 5" ''

    generate "$T/cfg-none" "$SYS" "$T/gen-control"
    [[ "$(generated "$T/gen-control")" == $'geoclue-demo-agent.desktop\nnm-applet.desktop\norg.fcitx.Fcitx5.desktop\norg.kde.kdeconnect.daemon.desktop' ]] \
        || fail "the control run did not generate a unit for each of the four fixture entries, so the checks below prove nothing: $(generated "$T/gen-control" | tr '\n' ' ')"

    mkdir -p "$T/cfg-kept"
    cp -a -- "$AUTOSTART" "$T/cfg-kept/autostart"
    generate "$T/cfg-kept" "$SYS" "$T/gen-kept"
    [[ "$(generated "$T/gen-kept")" == org.fcitx.Fcitx5.desktop ]] \
        || fail "with the shipped overrides the generator should leave only org.fcitx.Fcitx5.desktop, got: $(generated "$T/gen-kept" | tr '\n' ' ')"
    [[ -L "$T/gen-kept/late/xdg-desktop-autostart.target.wants/app-org.fcitx.Fcitx5@autostart.service" ]] \
        || fail "the fcitx unit is not wanted by xdg-desktop-autostart.target, so starting the target would not start it"
    echo "ok   generator: the three hidden entries get no unit, and the input method does"

    mkdir -p "$T/cfg-restored"
    cp -a -- "$AUTOSTART" "$T/cfg-restored/autostart"
    sed -i 's/^Hidden=true$/Hidden=false/' "$T/cfg-restored/autostart/nm-applet.desktop"
    generate "$T/cfg-restored" "$SYS" "$T/gen-restored"
    [[ "$(generated "$T/gen-restored")" == $'nm-applet.desktop\norg.fcitx.Fcitx5.desktop' ]] \
        || fail "setting one override to Hidden=false should bring back only that unit, got: $(generated "$T/gen-restored" | tr '\n' ' ')"
    echo "ok   generator: Hidden=false in one override brings back that login item only"

    if [[ -d /etc/xdg/autostart ]]; then
        generate "$T/cfg-none" /etc/xdg "$T/gen-host-control"
        generate "$T/cfg-kept" /etc/xdg "$T/gen-host-kept"
        for name in "${HIDDEN[@]}"; do
            if generated "$T/gen-host-control" | grep -qxF "$name.desktop"; then
                generated "$T/gen-host-kept" | grep -qxF "$name.desktop" \
                    && fail "this host's /etc/xdg/autostart/$name.desktop still gets a unit with the override in place; the override's file name no longer matches"
                echo "ok   generator: this host's /etc/xdg/autostart/$name.desktop gets a unit without the override and none with it"
            else
                echo "note: this host's /etc/xdg/autostart has no live $name.desktop to hide"
            fi
        done
    fi
fi

# --- the migration: existing homes get the target and the overrides ---
shopt -s nullglob
found=("$ROOT"/sdata/migrations/*-session-target-autostart.sh)
shopt -u nullglob
[[ ${#found[@]} -eq 1 ]] || fail "expected one session-target-autostart migration under sdata/migrations, found ${#found[@]}"
MIGRATION="${found[0]}"
[[ ! -x "$MIGRATION" ]] || fail "the migration is executable; the runner calls bash on it, and docs/agents/migrations.md wants it without the bit"

MH="$T/home-migrate"
BACKUPS="$MH/.local/state/koompi/backups"
migrate() {
    (
        export HOME="$MH"
        unset XDG_CONFIG_HOME XDG_STATE_HOME KOOMPI_STATE_DIR
        bash -euo pipefail "$MIGRATION"
    ) > "$T/migration.log" 2>&1 || { cat "$T/migration.log" >&2; fail "the migration exited non-zero"; }
}
fresh_migrate_home() {
    rm -rf -- "${MH:?}"
    mkdir -p "$MH/.config/hypr/hyprland"
    : > "$MH/.config/hypr/hyprland/execs.lua"
}
tree_state() {
    (cd -- "$MH" && find . -mindepth 1 -printf '%p %y %i %T@ %m\n' | sort && find . -type f -exec md5sum {} + | sort -k2)
}
backup_count() { local files=("$BACKUPS"/*); [[ -e "${files[0]}" ]] && echo "${#files[@]}" || echo 0; }
printf '[Unit]\nDescription=Hyprland compositor session\nBindsTo=graphical-session.target\nWants=graphical-session-pre.target\nAfter=graphical-session-pre.target\n' > "$T/old-target"

rm -rf -- "${MH:?}"
mkdir -p "$MH"
migrate
[[ -z "$(ls -A "$MH")" ]] || fail "a home without KOOMPI's Hyprland config gained files: $(ls -A "$MH")"
echo "ok   migrate: a home with no Hyprland session is left alone"

fresh_migrate_home
migrate
cmp -s -- "$MH/.config/systemd/user/hyprland-session.target" "$TARGET" || fail "the migration did not write the shipped session target"
for name in "${HIDDEN[@]}"; do
    cmp -s -- "$MH/.config/autostart/$name.desktop" "$AUTOSTART/$name.desktop" || fail "the migration did not write the shipped $name override"
done
[[ "$(stat -c %a "$MH/.config/systemd/user/hyprland-session.target")" == 644 ]] || fail "the written target is not mode 644"
[[ "$(ls -A "$MH/.config/systemd/user")" == hyprland-session.target ]] || fail "systemd/user holds more than the target after the migration: $(ls -A "$MH/.config/systemd/user" | tr '\n' ' ')"
[[ "$(ls -A "$MH/.config/autostart" | sort)" == "$(printf '%s\n' "${HIDDEN[@]/%/.desktop}" | sort)" ]] || fail "autostart holds something other than the three overrides after the migration: $(ls -A "$MH/.config/autostart" | tr '\n' ' ')"
[[ "$(backup_count)" -eq 0 ]] || fail "the migration backed up files on a home that had none to lose"
echo "ok   migrate: a home with a Hyprland session gets the target and the three overrides, as shipped"

settled="$(tree_state)"
migrate
[[ "$settled" == "$(tree_state)" ]] || fail "a second run changed the home"
echo "ok   migrate: a second run changes nothing"

printf '[Desktop Entry]\n# mine\nType=Application\nName=nm\nExec=true\nHidden=false\n' > "$MH/.config/autostart/nm-applet.desktop"
rm -- "$MH/.config/autostart/geoclue-demo-agent.desktop"
migrate
grep -qx 'Hidden=false' "$MH/.config/autostart/nm-applet.desktop" || fail "the migration rewrote an override the user had edited"
cmp -s -- "$MH/.config/autostart/geoclue-demo-agent.desktop" "$AUTOSTART/geoclue-demo-agent.desktop" || fail "the migration did not write back an absent override"
[[ "$(backup_count)" -eq 0 ]] || fail "an edited override was backed up as if it had been replaced"
echo "ok   migrate: an edited override survives, an absent one is written"

fresh_migrate_home
mkdir -p "$MH/.config/systemd/user"
cp -- "$T/old-target" "$MH/.config/systemd/user/hyprland-session.target"
migrate
cmp -s -- "$MH/.config/systemd/user/hyprland-session.target" "$TARGET" || fail "a differing session target was not replaced"
[[ "$(backup_count)" -eq 1 ]] || fail "expected one backup of the differing target, found $(backup_count)"
backup=("$BACKUPS"/*)
cmp -s -- "$T/old-target" "${backup[0]}" || fail "the backup is not the target as it was"
settled="$(tree_state)"
migrate
[[ "$settled" == "$(tree_state)" && "$(backup_count)" -eq 1 ]] || fail "a second run after a replacement changed the home or wrote another backup"
echo "ok   migrate: a differing target is backed up, then replaced, and the next run leaves it"

fresh_migrate_home
mkdir -p "$MH/.config/systemd/user" "$MH/dotfiles"
cp -- "$T/old-target" "$MH/dotfiles/hyprland-session.target"
ln -s "$MH/dotfiles/hyprland-session.target" "$MH/.config/systemd/user/hyprland-session.target"
migrate
cmp -s -- "$MH/.config/systemd/user/hyprland-session.target" "$TARGET" || fail "a symlinked session target was not replaced"
cmp -s -- "$T/old-target" "$MH/dotfiles/hyprland-session.target" || fail "the file a symlinked target pointed at was written through"
[[ "$(backup_count)" -eq 1 ]] || fail "a replaced symlink was not backed up"
echo "ok   migrate: a symlinked target is replaced and the file it pointed at is not touched"

fresh_migrate_home
mkdir -p "$MH/dotfiles"
cp -- "$TARGET" "$MH/dotfiles/hyprland-session.target"
mkdir -p "$MH/.config/systemd/user"
ln -s "$MH/dotfiles/hyprland-session.target" "$MH/.config/systemd/user/hyprland-session.target"
migrate
[[ -L "$MH/.config/systemd/user/hyprland-session.target" ]] || fail "a symlink that already holds the shipped target was replaced"
echo "ok   migrate: a symlink that already holds the shipped target stays a symlink"

fresh_migrate_home
if ( export HOME="$MH"; unset XDG_CONFIG_HOME XDG_STATE_HOME KOOMPI_STATE_DIR
     KOOMPI_MIGRATE_MIGRATIONS_DIR="$ROOT/sdata/migrations" "$ROOT/dots/.local/bin/koompi-migrate" run ) > "$T/run.log" 2>&1; then
    [[ -e "$MH/.local/state/koompi/migrations/${MIGRATION##*/}" ]] || fail "koompi-migrate run did not mark the migration done"
    cmp -s -- "$MH/.config/systemd/user/hyprland-session.target" "$TARGET" || fail "koompi-migrate run did not write the session target"
else
    cat "$T/run.log" >&2
    fail "koompi-migrate run over the shipped migrations failed"
fi
echo "ok   migrate: koompi-migrate run finds the migration, applies it and marks it done"

echo "session autostart tests passed"
