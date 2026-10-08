#!/usr/bin/env bash
# koompi-migrate's delivery and safety surface (J29): the Hyprland autoreload
# guard around the sync (set, restored, restored on rsync failure, skipped
# outside Hyprland), `refresh` (backup, diff, replace), `new` (skeleton in a
# checkout only), `notify` (waits for the notification server, sends an
# argv --exec through koompi-notify-send) and the unit's ExecStart.
# hyprctl, busctl, rsync, koompi-notify-send and wezterm are shimmed on PATH.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE="$ROOT/dots/.local/bin/koompi-migrate"
UNIT="$ROOT/dots/.config/systemd/user/koompi-migrate-notify.service"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

SHIMS="$TEST_ROOT/shims"; mkdir -p "$SHIMS"
HYPRCTL_LOG="$TEST_ROOT/hyprctl.log"; BUSCTL_LOG="$TEST_ROOT/busctl.log"; SENT="$TEST_ROOT/sent.txt"
REAL_RSYNC="$(command -v rsync)" || { echo "skip: rsync not installed"; exit 0; }
AUTORELOAD="$TEST_ROOT/autoreload"; WRITES="$TEST_ROOT/writes.log"
# Hyprland 0.56 on the Lua config: keyword prints that line and changes nothing, eval sets the option and answers ok
cat > "$SHIMS/hyprctl" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$HYPRCTL_LOG"
case "\${1:-}" in
    -j) echo "{\"option\": \"misc:disable_autoreload\", \"bool\": \$(cat "$AUTORELOAD"), \"set\": false}" ;;
    keyword) echo "keyword can't work with non-legacy parsers. Use eval." ;;
    eval)
        [[ -e "$TEST_ROOT/eval-fails" ]] && { echo "error: unknown config key 'misc.disable_autoreload'" >&2; exit 7; }
        case "\$2" in
            *'disable_autoreload = true'*) echo true > "$AUTORELOAD" ;;
            *'disable_autoreload = false'*) echo false > "$AUTORELOAD" ;;
            *) echo "error: unexpected eval: \$2" >&2; exit 7 ;;
        esac
        echo ok ;;
esac
exit 0
SHIM
cat > "$SHIMS/busctl" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$BUSCTL_LOG"
[[ "\$*" == *NameHasOwner* ]] || { echo "shim: unexpected busctl call: \$*" >&2; exit 2; }
[[ -e "$TEST_ROOT/server-up" ]] && echo "b true" || echo "b false"
SHIM
cat > "$SHIMS/koompi-notify-send" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$SENT"
SHIM
cat > "$SHIMS/rsync" <<SHIM
#!/usr/bin/env bash
[[ "\$1" == -n* ]] || printf 'disable_autoreload=%s\n' "\$(cat "$AUTORELOAD")" >> "$WRITES"
if [[ -e "$TEST_ROOT/rsync-fail" && "\$1" != -n* ]]; then echo "rsync: simulated failure" >&2; exit 23; fi
exec "$REAL_RSYNC" "\$@"
SHIM
printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIMS/wezterm"
chmod +x "$SHIMS"/*
export PATH="$SHIMS:$PATH"

# A skel with a shipped hyprland/ tree and hypridle.conf, and a HOME whose
# copies of both have drifted.
export KOOMPI_MIGRATE_SKEL="$TEST_ROOT/skel" KOOMPI_MIGRATE_XDG="$TEST_ROOT/xdg"
export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
unset KOOMPI_STATE_DIR KOOMPI_CONFIG_FILE
export KOOMPI_MIGRATE_MIGRATIONS_DIR="$TEST_ROOT/migrations"
mkdir -p "$KOOMPI_MIGRATE_SKEL/.config/hypr/hyprland" "$KOOMPI_MIGRATE_MIGRATIONS_DIR"
printf 'shipped = 2\n' > "$KOOMPI_MIGRATE_SKEL/.config/hypr/hyprland/general.lua"
printf 'require("hyprland.general")\n' > "$KOOMPI_MIGRATE_SKEL/.config/hypr/hyprland.lua"
printf 'listener {\n    timeout = 300\n}\n' > "$KOOMPI_MIGRATE_SKEL/.config/hypr/hypridle.conf"
reset_home() {
    rm -rf "$HOME"; mkdir -p "$HOME"
    cp -r "$KOOMPI_MIGRATE_SKEL/.config" "$HOME/.config"
    printf 'shipped = 1\n' > "$HOME/.config/hypr/hyprland/general.lua"
    printf 'listener {\n    timeout = 60\n}\n' > "$HOME/.config/hypr/hypridle.conf"
    : > "$HYPRCTL_LOG"; : > "$WRITES"; echo false > "$AUTORELOAD"; rm -f "$TEST_ROOT/rsync-fail"
}
GET='-j getoption misc:disable_autoreload'
PAUSE='eval hl.config({ misc = { disable_autoreload = true } })'
RESUME='eval hl.config({ misc = { disable_autoreload = false } })'
written_paused() { [[ -s "$WRITES" ]] && ! grep -qvx 'disable_autoreload=true' "$WRITES"; }

# 1. Autoreload paused while the sync writes, reload issued, option restored after.
reset_home
HYPRLAND_INSTANCE_SIGNATURE=shim "$MIGRATE" --apply > "$TEST_ROOT/out" 2>&1 || fail "--apply failed: $(cat "$TEST_ROOT/out")"
written_paused || fail "the sync wrote while Hyprland's autoreload was on: $(cat "$WRITES")"
[[ "$(cat "$AUTORELOAD")" == false ]] || fail "the autoreload option was not put back: $(cat "$AUTORELOAD")"
expected="$GET"$'\n'"$PAUSE"$'\nreload\n'"$RESUME"
[[ "$(cat "$HYPRCTL_LOG")" == "$expected" ]] || fail "hyprctl sequence on success: $(cat "$HYPRCTL_LOG")"
[[ "$(cat "$HOME/.config/hypr/hyprland/general.lua")" == 'shipped = 2' ]] || fail "hyprland/ was not synced"

# 1b. KOOMPI_MIGRATE_NO_RELOAD: the guard stays, the reload and the restart advice go (koompi update reloads once, last).
reset_home
HYPRLAND_INSTANCE_SIGNATURE=shim KOOMPI_MIGRATE_NO_RELOAD=1 "$MIGRATE" --apply > "$TEST_ROOT/out" 2>&1 || fail "--apply failed under KOOMPI_MIGRATE_NO_RELOAD: $(cat "$TEST_ROOT/out")"
written_paused || fail "the sync wrote while Hyprland's autoreload was on, under KOOMPI_MIGRATE_NO_RELOAD: $(cat "$WRITES")"
[[ "$(cat "$AUTORELOAD")" == false ]] || fail "the autoreload option was not put back under KOOMPI_MIGRATE_NO_RELOAD: $(cat "$AUTORELOAD")"
expected="$GET"$'\n'"$PAUSE"$'\n'"$RESUME"
[[ "$(cat "$HYPRCTL_LOG")" == "$expected" ]] || fail "hyprctl sequence under KOOMPI_MIGRATE_NO_RELOAD: $(cat "$HYPRCTL_LOG")"
[[ "$(cat "$HOME/.config/hypr/hyprland/general.lua")" == 'shipped = 2' ]] || fail "hyprland/ was not synced under KOOMPI_MIGRATE_NO_RELOAD"
grep -q 'Restart the shell' "$TEST_ROOT/out" && fail "the closing line sends the user off to restart a shell the update restarts: $(cat "$TEST_ROOT/out")"
grep -q '^koompi-migrate: done\.$' "$TEST_ROOT/out" || fail "no plain closing line under KOOMPI_MIGRATE_NO_RELOAD: $(cat "$TEST_ROOT/out")"

# 1c. A user who runs with autoreload off gets it back off, not on.
reset_home; echo true > "$AUTORELOAD"
HYPRLAND_INSTANCE_SIGNATURE=shim "$MIGRATE" --apply > "$TEST_ROOT/out" 2>&1 || fail "--apply failed with autoreload already off: $(cat "$TEST_ROOT/out")"
[[ "$(cat "$AUTORELOAD")" == true ]] || fail "a user's disable_autoreload=true was turned back on: $(cat "$AUTORELOAD")"
expected="$GET"$'\n'"$PAUSE"$'\nreload\n'"$PAUSE"
[[ "$(cat "$HYPRCTL_LOG")" == "$expected" ]] || fail "hyprctl sequence with autoreload already off: $(cat "$HYPRCTL_LOG")"

# 1d. A pause that does not take stops the sync before it writes anything.
reset_home; touch "$TEST_ROOT/eval-fails"
if HYPRLAND_INSTANCE_SIGNATURE=shim "$MIGRATE" --apply > "$TEST_ROOT/out" 2>&1; then fail "--apply went on although hyprctl could not pause the autoreload"; fi
rm -f "$TEST_ROOT/eval-fails"
[[ ! -s "$WRITES" ]] || fail "the sync wrote although the autoreload could not be paused: $(cat "$WRITES")"
[[ "$(cat "$HOME/.config/hypr/hyprland/general.lua")" == 'shipped = 1' ]] || fail "hyprland/ was rewritten without the guard"
grep -q 'could not pause' "$TEST_ROOT/out" || fail "no word on why the sync stopped: $(cat "$TEST_ROOT/out")"

# 2. rsync fails mid-sync: the EXIT trap still restores the option, no reload.
reset_home; touch "$TEST_ROOT/rsync-fail"
if HYPRLAND_INSTANCE_SIGNATURE=shim "$MIGRATE" --apply > "$TEST_ROOT/out" 2>&1; then fail "--apply succeeded with a failing rsync"; fi
written_paused || fail "the failing sync attempt ran while Hyprland's autoreload was on: $(cat "$WRITES")"
[[ "$(cat "$AUTORELOAD")" == false ]] || fail "a failed sync left the autoreload option off: $(cat "$AUTORELOAD")"
expected="$GET"$'\n'"$PAUSE"$'\n'"$RESUME"
[[ "$(cat "$HYPRCTL_LOG")" == "$expected" ]] || fail "hyprctl sequence on rsync failure: $(cat "$HYPRCTL_LOG")"

# 3. Outside Hyprland: no hyprctl at all, and a line saying so.
reset_home
env -u HYPRLAND_INSTANCE_SIGNATURE "$MIGRATE" --apply > "$TEST_ROOT/out" 2>&1 || fail "--apply outside Hyprland failed"
grep -q 'autoreload guard skipped' "$TEST_ROOT/out" || fail "no skip line outside Hyprland"
[[ ! -s "$HYPRCTL_LOG" ]] || fail "hyprctl called outside Hyprland: $(cat "$HYPRCTL_LOG")"

# 4. refresh: backup in the sync's backup dir, unified diff, file replaced.
reset_home
"$MIGRATE" refresh .config/hypr/hypridle.conf > "$TEST_ROOT/out" 2>&1 || fail "refresh failed: $(cat "$TEST_ROOT/out")"
backup="$(find "$HOME/.local/state/koompi/backups" -name 'refresh-*-config_hypr_hypridle.conf' | head -1)"
[[ -n "$backup" ]] || fail "refresh wrote no backup: $(cat "$TEST_ROOT/out")"
grep -q 'timeout = 60' "$backup" || fail "backup does not hold the previous file"
grep -q '^--- .config/hypr/hypridle.conf (yours)' "$TEST_ROOT/out" || fail "no unified diff header"
{ grep -q '^-    timeout = 60' "$TEST_ROOT/out" && grep -q '^+    timeout = 300' "$TEST_ROOT/out"; } || fail "diff lacks the change"
cmp -s "$HOME/.config/hypr/hypridle.conf" "$KOOMPI_MIGRATE_SKEL/.config/hypr/hypridle.conf" || fail "refresh did not replace the file"
"$MIGRATE" refresh hypr/hypridle.conf | grep -q 'already matches' || fail "refresh shorthand or already-matches path broke"
if "$MIGRATE" refresh .config/hypr/nope.conf > "$TEST_ROOT/out" 2>&1; then fail "refresh accepted a path with no default"; fi
grep -q "defaults live in $KOOMPI_MIGRATE_SKEL" "$TEST_ROOT/out" || fail "unknown path error does not name where defaults live"
if "$MIGRATE" refresh ../etc/passwd >/dev/null 2>&1; then fail "refresh accepted a path escaping HOME"; fi

# 5. new: skeleton into a checkout's sdata/migrations, refused elsewhere.
CHECKOUT="$TEST_ROOT/checkout"
mkdir -p "$CHECKOUT/dots/.local/bin" "$CHECKOUT/dots/.local/share/koompi/libexec" "$CHECKOUT/sdata/migrations"
cp "$MIGRATE" "$CHECKOUT/dots/.local/bin/"; cp "$ROOT/dots/.local/share/koompi/libexec/migrate-lib.sh" "$CHECKOUT/dots/.local/share/koompi/libexec/"
if "$CHECKOUT/dots/.local/bin/koompi-migrate" new fix-thing >/dev/null 2>&1; then fail "new wrote outside a checkout (no .git)"; fi
: > "$CHECKOUT/.git"
before="$(date +%s)"
created="$("$CHECKOUT/dots/.local/bin/koompi-migrate" new fix-thing)"
[[ "$(basename "$created")" =~ ^[0-9]{10}-fix-thing\.sh$ ]] || fail "unexpected skeleton name: $created"
ts="${created##*/}"; ts="${ts%%-*}"; (( ts >= before )) || fail "skeleton timestamp is not current: $ts"
[[ "$(stat -c %a "$created")" == 644 ]] || fail "skeleton mode is $(stat -c %a "$created"), want 644"
{ grep -q 'shellcheck shell=bash' "$created" && grep -q 'docs/agents/migrations.md' "$created"; } || fail "skeleton body"
bash -euo pipefail "$created" || fail "the fresh skeleton does not run clean"
if "$CHECKOUT/dots/.local/bin/koompi-migrate" new 'Bad Slug' >/dev/null 2>&1; then fail "new accepted a bad slug"; fi

# 6. notify: nothing pending is silent; pending waits for the server, then
#    sends --exec as argv (terminal, then this script's own path).
rm -f "$SENT" "$TEST_ROOT/server-up"; : > "$BUSCTL_LOG"
"$MIGRATE" notify || fail "notify with nothing pending should exit 0"
[[ ! -e "$SENT" ]] || fail "notify sent a toast with nothing pending"
printf 'true\n' > "$KOOMPI_MIGRATE_MIGRATIONS_DIR/1000-a.sh"
if KOOMPI_MIGRATE_NOTIFY_WAIT=1 "$MIGRATE" notify > "$TEST_ROOT/out" 2>&1; then fail "notify claimed success with no notification server"; fi
grep -q 'no notification server after 1s' "$TEST_ROOT/out" || fail "no bounded-wait error: $(cat "$TEST_ROOT/out")"
[[ ! -e "$SENT" ]] || fail "notify sent without a server"
( sleep 0.3; touch "$TEST_ROOT/server-up" ) &
KOOMPI_MIGRATE_NOTIFY_WAIT=5 "$MIGRATE" notify || fail "notify failed with a server present"
wait
grep -q 'NameHasOwner s org.freedesktop.Notifications' "$BUSCTL_LOG" || fail "notify did not poll NameHasOwner"
mapfile -t sent < "$SENT"
[[ "${sent[*]:0:5}" == "-a KOOMPI -u critical Desktop update pending" ]] || fail "toast header: ${sent[*]}"
[[ "${sent[5]}" == *"1 pending migration"* ]] || fail "toast body: ${sent[5]}"
[[ "${sent[*]:6}" == "--exec wezterm start -- $MIGRATE run --hold" ]] || fail "toast --exec argv: ${sent[*]:6}"

# 7. run --hold: runs, prints the hold prompt, propagates the exit status.
"$MIGRATE" run --hold < /dev/null > "$TEST_ROOT/out" || fail "run --hold failed"
grep -q 'Press Enter' "$TEST_ROOT/out" || fail "run --hold shows no hold prompt"
printf 'exit 1\n' > "$KOOMPI_MIGRATE_MIGRATIONS_DIR/2000-b.sh"
if "$MIGRATE" run --hold < /dev/null > /dev/null 2>&1; then fail "run --hold swallowed a failing migration"; fi

# 8. The unit runs a command that exists, after the target, never before it.
exec_line="$(grep '^ExecStart=' "$UNIT")" || fail "unit has no ExecStart"
exec_line="${exec_line#ExecStart=}"; exec_line="${exec_line//%h/$ROOT/dots}"
read -r exe sub <<<"$exec_line"
[[ -x "$exe" ]] || fail "unit ExecStart '$exe' is not an executable in the dots tree"
[[ "$sub" == notify ]] || fail "unit runs '$sub', expected notify"
grep -q '^After=graphical-session.target' "$UNIT" || fail "unit is not ordered after graphical-session.target"
! grep -q '^Before=' "$UNIT" || fail "unit must not hold graphical-session.target open"

printf 'migrate delivery tests passed\n'
