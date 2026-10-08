#!/usr/bin/env bash
# every koompi update route says what the packages delivered; the packaged one syncs the code trees, then each runs koompi-migrate once, before the one reload
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$ROOT/dots/.local/share/koompi/libexec/update"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.local/state/koompi" "$T/runtime"
chmod 700 "$T/runtime"

cat > "$T/bin/pacman" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "-Qq" && "\${2:-}" == koompi-* ]]; then [[ -e "$T/not-packaged" ]] && exit 1; exit 0; fi
if [[ "\$1" == "-Qq" ]]; then cat "$T/versions"; exit 0; fi
if [[ "\$1" == "-Syu" ]]; then
    touch "$T/syu-ran"
    echo "pacman -Syu" >> "$T/order"
    [[ -e "$T/versions-static" ]] && exit 0
    echo "koompi-shell 9.9-1" >> "$T/versions"
    sort -o "$T/versions" "$T/versions"
    exit 0
fi
exit 0
STUB
printf 'koompi-shell 1.1-1\nkoompi-hyprland-config 1.0-2\n' > "$T/versions"

cat > "$T/bin/pacman-conf" <<STUB
#!/usr/bin/env bash
if [[ "\${1:-}" == "--repo-list" ]]; then cat "$T/repos"; exit 0; fi
exit 0
STUB
printf 'core\nextra\nmultilib\n' > "$T/repos"

cat > "$T/bin/koompi-migrate" <<STUB
#!/usr/bin/env bash
printf 'koompi-migrate %s\\n' "\$*" >> "$T/order"
case "\${1:-}" in
    --pending) echo 1000-shim.sh; exit 0 ;;
    --apply)
        printf 'apply no-reload=%s\\n' "\${KOOMPI_MIGRATE_NO_RELOAD:-}" >> "$T/order"
        echo "koompi-migrate shim: apply"
        [[ -e "$T/apply-fails" ]] || exit 0
        echo "koompi-migrate: rsync required" >&2
        exit 1 ;;
    run)
        echo "koompi-migrate shim: run"
        [[ -e "$T/migrate-fails" ]] || exit 0
        echo "koompi-migrate: FAILED 1000-shim.sh; stopping, later migrations left pending" >&2
        exit 1 ;;
esac
exit 0
STUB

printf '#!/usr/bin/env bash\nexec "$@"\n' > "$T/bin/sudo"
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "$T/aur-ran" > "$T/bin/paru"
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "$T/aur-ran" > "$T/bin/yay"
cat > "$T/bin/koompi-hook" <<STUB
#!/usr/bin/env bash
echo "hook \$KOOMPI_HOOK_UPDATE_METHOD" >> "$T/hook"
exit 0
STUB
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/koompi-snapshot"
printf '#!/usr/bin/env bash\nexit 2\n' > "$T/bin/fwupdmgr"
printf '#!/usr/bin/env bash\nwhile [[ "${1:-}" == --* ]]; do shift; done\nexec "$@"\n' > "$T/bin/systemd-inhibit"
# no sessions and no lock screen unless a scenario locks one, so the real seat's lock state never decides a route
cat > "$T/bin/loginctl" <<STUB
#!/usr/bin/env bash
[[ -e "$T/locked" ]] || exit 0
case "\${1:-}" in
    list-sessions) printf '3 %s %s seat0 2188 user tty1 no -\\n' "$(id -u)" "$(id -un)" ;;
    show-session)  echo yes ;;
esac
STUB
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pidof"
cat > "$T/bin/hyprctl" <<STUB
#!/usr/bin/env bash
printf 'hyprctl %s\\n' "\$*" >> "$T/hyprctl.log"
case "\${1:-}" in
    -j) echo '{"option": "misc:disable_autoreload", "bool": false, "set": false}' ;;
    keyword) echo "keyword can't work with non-legacy parsers. Use eval." ;;
    eval) echo ok ;;
esac
exit 0
STUB
# recorders: whatever order reload_session takes, a shell restart lands here and not on the real shell
printf '#!/usr/bin/env bash\nprintf "qs %%s\\n" "$*" >> "%s"\nexit 0\n' "$T/shell-touched.log" > "$T/bin/qs"
printf '#!/usr/bin/env bash\nprintf "killall %%s\\n" "$*" >> "%s"\nexit 0\n' "$T/shell-touched.log" > "$T/bin/killall"

mkdir -p "$T/repo"
cat > "$T/repo/setup" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$T/setup-called"
printf 'setup %s [no-reload=%s]\\n' "\$*" "\${KOOMPI_SETUP_NO_RELOAD:-}" >> "$T/order"
exit 0
STUB
chmod +x "$T"/bin/* "$T/repo/setup"
echo "$T/repo" > "$T/home/.local/state/koompi/repo-path"

export PATH="$T/bin:$PATH"
export HOME="$T/home"
export XDG_STATE_HOME="$T/home/.local/state"
export XDG_RUNTIME_DIR="$T/runtime"
# the real koompi-migrate runs below: nothing it reads may point outside the scratch home
export XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share"
unset KOOMPI_STATE_DIR KOOMPI_CONFIG_FILE
export KOOMPI_UPDATE_MODULES_DIR="$T/modules"
unset HYPRLAND_INSTANCE_SIGNATURE   # keep reload_session away from the live session
export NO_COLOR=1

run_update() { bash "$UPDATE" "$@" 2>&1 < /dev/null; }
line_of() { grep -n -- "$1" "$2" | head -1 | cut -d: -f1; }
before() {
    local first second
    first="$(line_of "$2" "$1")"
    second="$(line_of "$3" "$1")"
    [[ -n "$first" && -n "$second" ]] && (( first < second ))
}
ran_once() { [[ "$(grep -c '^koompi-migrate run$' "$T/order")" -eq 1 ]]; }
applied_once() { [[ "$(grep -c '^koompi-migrate --apply$' "$T/order")" -eq 1 ]]; }
never_applied() { ! grep -q '^koompi-migrate --apply$' "$T/order"; }
RELOADED='the update applies at your next login'

: > "$T/order"
out="$(run_update --dry-run)"
grep -q 'delivered nothing of ours' <<<"$out" \
    || fail "the honesty line is missing: $out"
[[ "$(tail -1 "$T/setup-called" 2>/dev/null)" == "update --dry-run" ]] \
    || fail "the git fallback did not run ./setup update --dry-run"
grep -qi 'falling back to the git route' <<<"$out" \
    || fail "the output does not name the route that ran"
grep -q 'packages up to date' <<<"$out" \
    && fail "'packages up to date' must not stand when nothing was delivered"
grep -qx 'koompi-migrate --pending' "$T/order" || fail "a dry run did not ask koompi-migrate what is pending"
grep -q '^koompi-migrate run' "$T/order" && fail "a dry run ran the migrations"
grep -q 'would run: 1000-shim.sh' <<<"$out" || fail "a dry run did not list the pending migration: $out"
never_applied || fail "the git fallback applied the code-tree sync, which ./setup update already does: $(cat "$T/order")"

rm -f "$T/setup-called" "$T/syu-ran"
: > "$T/order"
printf 'core\nextra\nkoompi\n' > "$T/repos"
out="$(run_update --dry-run)"
grep -q 'packages up to date (route: packaged)' <<<"$out" \
    || fail "a configured [koompi] repo should end as a packaged update: $out"
[[ -e "$T/setup-called" ]] && fail "the git route ran although the repo is configured"
grep -q '^koompi-migrate run' "$T/order" && fail "a dry run ran the migrations on the packaged route"
never_applied || fail "a dry run applied the code-tree sync: $(cat "$T/order")"
grep -q 'would copy the packaged shell and Hyprland trees' <<<"$out" || fail "a dry run does not say it would sync the code trees: $out"

rm -f "$T/setup-called"
: > "$T/order"
printf 'core\nextra\nmultilib\n' > "$T/repos"
out="$(run_update --yes)"
grep -q 'packages up to date (route: packaged)' <<<"$out" \
    || fail "moved koompi-* packages mean the packaged route delivered: $out"
[[ -e "$T/setup-called" ]] && fail "the git route ran although a package moved"
ran_once || fail "the packaged route did not run koompi-migrate run exactly once: $(cat "$T/order")"
before "$T/order" '^pacman -Syu' '^koompi-migrate run$' || fail "the migrations ran before the packages were upgraded: $(cat "$T/order")"
printf '%s\n' "$out" > "$T/out"
before "$T/out" 'koompi-migrate shim: run' "$RELOADED" || fail "the packaged route reloaded before it ran the migrations: $out"
applied_once || fail "the packaged route did not apply the code-tree sync exactly once: $(cat "$T/order")"
before "$T/order" '^pacman -Syu' '^koompi-migrate --apply$' || fail "the sync ran before the packages were upgraded: $(cat "$T/order")"
before "$T/order" '^koompi-migrate --apply$' '^koompi-migrate run$' || fail "the migrations ran before the code-tree sync: $(cat "$T/order")"
grep -qx 'apply no-reload=1' "$T/order" || fail "the sync was not told to leave the reload to the update: $(cat "$T/order")"

rm -f "$T/setup-called"
: > "$T/order"
touch "$T/versions-static"
out="$(run_update --yes)"
grep -qi 'falling back to the git route' <<<"$out" || fail "static packages must fall back to the git route: $out"
ran_once || fail "the git fallback did not run koompi-migrate run exactly once: $(cat "$T/order")"
before "$T/order" '^setup update --yes' '^koompi-migrate run$' || fail "the migrations ran before ./setup update: $(cat "$T/order")"
grep -qx 'setup update --yes \[no-reload=1\]' "$T/order" || fail "the engine let ./setup update reload before the migrations ran: $(cat "$T/order")"
printf '%s\n' "$out" > "$T/out"
before "$T/out" 'koompi-migrate shim: run' "$RELOADED" || fail "the git fallback reloaded before it ran the migrations: $out"
never_applied || fail "the git fallback applied the code-tree sync, which ./setup update already does: $(cat "$T/order")"

: > "$T/order"
touch "$T/not-packaged"
out="$(run_update --yes)"
ran_once || fail "the from-git route did not run koompi-migrate run exactly once: $(cat "$T/order")"
before "$T/order" '^setup update --yes' '^koompi-migrate run$' || fail "the migrations ran before ./setup update: $(cat "$T/order")"
grep -qx 'setup update --yes \[no-reload=1\]' "$T/order" || fail "the engine let ./setup update reload before the migrations ran: $(cat "$T/order")"
printf '%s\n' "$out" > "$T/out"
before "$T/out" 'koompi-migrate shim: run' "$RELOADED" || fail "the from-git route reloaded before it ran the migrations: $out"
never_applied || fail "the from-git route applied the code-tree sync, which ./setup update already does: $(cat "$T/order")"

: > "$T/order"
out="$(run_update --yes --no-reload)"
grep -q 'not reloading' <<<"$out" || fail "--no-reload is not honoured on the from-git route: $out"
ran_once || fail "--no-reload skipped the migrations: $(cat "$T/order")"
never_applied || fail "the from-git route applied the code-tree sync under --no-reload: $(cat "$T/order")"

rm -f "$T/not-packaged" "$T/versions-static"
: > "$T/order"
: > "$T/hyprctl.log"
out="$(run_update --yes --no-reload)"
grep -q 'not reloading' <<<"$out" || fail "--no-reload is not honoured on the packaged route: $out"
applied_once || fail "--no-reload skipped the code-tree sync: $(cat "$T/order")"
grep -qx 'apply no-reload=1' "$T/order" || fail "--no-reload let the sync reload Hyprland itself: $(cat "$T/order")"
ran_once || fail "--no-reload skipped the migrations: $(cat "$T/order")"
[[ -s "$T/hyprctl.log" ]] && fail "--no-reload reloaded Hyprland: $(cat "$T/hyprctl.log")"

: > "$T/order"
touch "$T/apply-fails"
hooks="$(wc -l < "$T/hook")"
out="$(run_update --yes)"
rc=$?
[[ $rc -eq 1 ]] || fail "a failed code-tree sync must fail the update (rc=$rc): $out"
applied_once || fail "the failed sync was not the one call: $(cat "$T/order")"
grep -q 'koompi-migrate --apply failed' <<<"$out" || fail "the update does not say the sync failed: $out"
grep -q '^koompi-migrate run' "$T/order" && fail "a failed sync still ran the migrations: $(cat "$T/order")"
grep -q "$RELOADED" <<<"$out" && fail "a failed sync still reached the reload: $out"
[[ "$(wc -l < "$T/hook")" -eq "$hooks" ]] || fail "a failed sync still fired the post-update hook"
rm -f "$T/apply-fails"

: > "$T/order"
touch "$T/migrate-fails"
hooks="$(wc -l < "$T/hook")"
out="$(run_update --yes)"
rc=$?
[[ $rc -eq 1 ]] || fail "a failed migration must fail the update (rc=$rc): $out"
grep -q 'FAILED 1000-shim.sh' <<<"$out" || fail "the failed migration's own report is missing: $out"
grep -q 'a migration failed' <<<"$out" || fail "the update does not say a migration failed: $out"
grep -q "$RELOADED" <<<"$out" || fail "a failed migration stopped the reload: $out"
[[ "$(wc -l < "$T/hook")" -gt "$hooks" ]] || fail "a failed migration skipped the post-update hook"
grep -q 'KOOMPI is up to date' <<<"$out" && fail "an update with a failed migration claims to be up to date: $out"
rm -f "$T/migrate-fails"

mkdir -p "$T/empty"
for fn in run_migrations sync_code_trees; do
    out="$("$BASH" -c 'source "$1"; PATH="$3"; "$2"' _ "$ROOT/dots/.local/share/koompi/libexec/update-lib.sh" "$fn" "$T/empty" 2>&1)"
    rc=$?
    [[ $rc -eq 1 ]] || fail "a missing koompi-migrate must fail $fn (rc=$rc): $out"
    grep -q 'koompi-migrate is not on PATH' <<<"$out" || fail "a missing koompi-migrate is not reported by $fn: $out"
done

if command -v rsync > /dev/null 2>&1; then
    mkdir -p "$T/skel/.config/hypr/hyprland" "$T/migs" "$T/home/.config/hypr/hyprland"
    printf 'shipped = 2\n' > "$T/skel/.config/hypr/hyprland/general.lua"
    mv "$T/bin/koompi-migrate" "$T/koompi-migrate.shim"
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$ROOT/dots/.local/bin/koompi-migrate" > "$T/bin/koompi-migrate"
    chmod +x "$T/bin/koompi-migrate"
    touch "$T/locked"
    for flag in "" --no-reload; do
        printf 'shipped = 1\n' > "$T/home/.config/hypr/hyprland/general.lua"
        : > "$T/hyprctl.log"
        out="$(KOOMPI_MIGRATE_SKEL="$T/skel" KOOMPI_MIGRATE_XDG="$T/no-xdg" KOOMPI_MIGRATE_MIGRATIONS_DIR="$T/migs" \
            HYPRLAND_INSTANCE_SIGNATURE=test-session run_update --yes ${flag:+"$flag"})" || fail "the update with the real koompi-migrate failed: $out"
        [[ "$(cat "$T/home/.config/hypr/hyprland/general.lua")" == 'shipped = 2' ]] || fail "the real sync did not copy the Hyprland tree: $out"
        expected=$'hyprctl -j getoption misc:disable_autoreload\nhyprctl eval hl.config({ misc = { disable_autoreload = true } })\nhyprctl eval hl.config({ misc = { disable_autoreload = false } })'
        [[ -n "$flag" ]] || expected+=$'\nhyprctl reload'
        [[ "$(cat "$T/hyprctl.log")" == "$expected" ]] \
            || fail "with the real koompi-migrate ${flag:-and no flag} Hyprland should reload once, last, and not under --no-reload: $(cat "$T/hyprctl.log")"
    done
    rm -f "$T/locked"
    mv "$T/koompi-migrate.shim" "$T/bin/koompi-migrate"
fi

for var in "" KOOMPI_SETUP_NO_RELOAD=1; do
    : > "$T/hyprctl.log"
    env HYPRLAND_INSTANCE_SIGNATURE=test-session ${var:+"$var"} bash -c '
        source "$1/sdata/lib/common.sh"
        have() { [[ "$1" != qs ]] && command -v "$1" > /dev/null 2>&1; }
        reload_session' _ "$ROOT" > /dev/null 2>&1
    if [[ -z "$var" ]]; then
        grep -qx 'hyprctl reload' "$T/hyprctl.log" || fail "the control failed: ./setup does not reload when nothing says otherwise"
    else
        [[ -s "$T/hyprctl.log" ]] && fail "./setup reloaded although koompi update told it not to: $(cat "$T/hyprctl.log")"
    fi
done
[[ -s "$T/shell-touched.log" ]] && fail "a reload reached for the shell: $(cat "$T/shell-touched.log")"

rm -f "$T/syu-ran"
cat > "$T/bin/koompi-snapshot" <<'STUB'
#!/usr/bin/env bash
echo "koompi-snapshot: simulated failure" >&2
exit 1
STUB
chmod +x "$T/bin/koompi-snapshot"
out="$(run_update)"
rc=$?
[[ $rc -ne 0 ]] || fail "a missing snapshot must fail the update without --yes"
grep -q 'refusing to upgrade' <<<"$out" \
    || fail "a failed snapshot must stop the upgrade without --yes: $out"
[[ -e "$T/syu-ran" ]] && fail "the upgrade ran although no snapshot was created"
out="$(run_update --yes)"
rc=$?
[[ $rc -eq 0 ]] || fail "--yes should accept the risk and finish: $out"
grep -q 'continuing (--yes)' <<<"$out" \
    || fail "--yes must be allowed to accept the missing snapshot: $out"
[[ -e "$T/syu-ran" ]] || fail "--yes accepted the risk but no upgrade ran"

exit 0
