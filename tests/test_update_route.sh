#!/usr/bin/env bash
# every koompi update route says what the packages delivered, runs koompi-migrate once before the reload, and fails on a failed migration
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
# no sessions and no lock screen, so the real seat's lock state never decides a route
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/loginctl"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pidof"
printf '#!/usr/bin/env bash\nprintf "hyprctl %%s\\n" "$*" >> "%s"\nexit 0\n' "$T/hyprctl.log" > "$T/bin/hyprctl"

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

rm -f "$T/setup-called" "$T/syu-ran"
: > "$T/order"
printf 'core\nextra\nkoompi\n' > "$T/repos"
out="$(run_update --dry-run)"
grep -q 'packages up to date (route: packaged)' <<<"$out" \
    || fail "a configured [koompi] repo should end as a packaged update: $out"
[[ -e "$T/setup-called" ]] && fail "the git route ran although the repo is configured"
grep -q '^koompi-migrate run' "$T/order" && fail "a dry run ran the migrations on the packaged route"

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

: > "$T/order"
touch "$T/not-packaged"
out="$(run_update --yes)"
ran_once || fail "the from-git route did not run koompi-migrate run exactly once: $(cat "$T/order")"
before "$T/order" '^setup update --yes' '^koompi-migrate run$' || fail "the migrations ran before ./setup update: $(cat "$T/order")"
grep -qx 'setup update --yes \[no-reload=1\]' "$T/order" || fail "the engine let ./setup update reload before the migrations ran: $(cat "$T/order")"
printf '%s\n' "$out" > "$T/out"
before "$T/out" 'koompi-migrate shim: run' "$RELOADED" || fail "the from-git route reloaded before it ran the migrations: $out"

: > "$T/order"
out="$(run_update --yes --no-reload)"
grep -q 'not reloading' <<<"$out" || fail "--no-reload is not honoured on the from-git route: $out"
ran_once || fail "--no-reload skipped the migrations: $(cat "$T/order")"

rm -f "$T/not-packaged" "$T/versions-static"
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
out="$(PATH="$T/empty" "$BASH" -c 'source "$1"; run_migrations' _ "$ROOT/dots/.local/share/koompi/libexec/update-lib.sh" 2>&1)"
rc=$?
[[ $rc -eq 1 ]] || fail "a missing koompi-migrate must fail the update's migration step (rc=$rc): $out"
grep -q 'koompi-migrate is not on PATH' <<<"$out" || fail "a missing koompi-migrate is not reported: $out"

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
