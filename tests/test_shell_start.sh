#!/usr/bin/env bash
# On 2026-09-30 the locally built koompi-quickshell-git, pinned to the exact Qt
# it linked, blocked a Qt upgrade and was removed to get past it; every login
# after the next boot came up with no shell and no word why. Checked here:
#   - the shell comes from Arch's quickshell (rebuilt by Arch with each Qt
#     bump) and no local quickshell build is back;
#   - start_shell.sh raises a compositor alert when qs is missing or dies at
#     once. qs and hyprctl are PATH shims.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/sdata/dist-arch"
START="$ROOT/dots/.config/hypr/hyprland/scripts/start_shell.sh"
EXECS="$ROOT/dots/.config/hypr/hyprland/execs.lua"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# --- packaging ------------------------------------------------------------
[[ -e "$DIST/koompi-quickshell-git" ]] && fail "a local quickshell build is back in sdata/dist-arch"
hypr_deps="$(source "$DIST/koompi-hyprland/PKGBUILD"; printf '%s\n' "${depends[@]}")"
grep -qx quickshell <<< "$hypr_deps" || fail "koompi-hyprland does not pull in Arch's quickshell"
hypr_replaces="$(source "$DIST/koompi-hyprland/PKGBUILD"; printf '%s\n' "${replaces[@]}")"
grep -qx koompi-quickshell-git <<< "$hypr_replaces" \
    || fail "koompi-hyprland does not replace koompi-quickshell-git, so pacman -Syu --noconfirm aborts on the conflict"
for dir in "$DIST"/*/; do
    [[ -f "$dir/PKGBUILD" ]] || continue
    deps="$(source "$dir/PKGBUILD" 2>/dev/null; printf '%s\n' "${depends[@]}")"
    grep -qx koompi-quickshell-git <<< "$deps" && fail "$(basename "$dir") still depends on koompi-quickshell-git"
done
grep -q 'koompi-quickshell-git' <(sed -n '/^arch_drop_deprecated()/,/^}/p' "$DIST/install-deps.sh") \
    || fail "install-deps.sh does not drop an installed koompi-quickshell-git"

# --- wiring ---------------------------------------------------------------
[[ -x "$START" ]] || fail "start_shell.sh missing or not executable"
grep -q 'hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_shell.sh")' "$EXECS" \
    || fail "execs.lua does not start the shell through start_shell.sh"
grep -q 'hl.exec_cmd(".*qs -c \$qsConfig")' "$EXECS" \
    && fail "execs.lua starts qs directly again, bypassing the alert"

# --- start_shell.sh -------------------------------------------------------
mkdir -p "$T/bin"
ln -s "$(command -v bash)" "$T/bin/bash"
cat > "$T/bin/hyprctl" <<STUB
#!$(command -v bash)
printf '%s\n' "\$*" >> "$T/notify"
STUB
chmod +x "$T/bin/hyprctl"

run_start() { rm -f "$T/notify"; PATH="$T/bin" qsConfig=koompi "$START"; }

run_start; rc=$?
(( rc == 1 )) || fail "missing qs: expected exit 1, got $rc"
grep -q '^notify 3 .*quickshell is not installed' "$T/notify" 2>/dev/null \
    || fail "missing qs raised no alert"

cat > "$T/bin/qs" <<STUB
#!$(command -v bash)
printf '%s|%s\n' "\$QT_QPA_PLATFORM" "\$*" > "$T/qs-args"
exit 127
STUB
chmod +x "$T/bin/qs"
run_start; rc=$?
(( rc == 127 )) || fail "qs dying at start: expected its status 127, got $rc"
[[ "$(cat "$T/qs-args")" == "wayland|-c koompi" ]] \
    || fail "qs started as '$(cat "$T/qs-args")', want 'wayland|-c koompi'"
grep -q '^notify 3 .*status 127' "$T/notify" 2>/dev/null \
    || fail "qs dying at start raised no alert"

sed -i 's/^exit 127$/exit 0/' "$T/bin/qs"
run_start; rc=$?
(( rc == 0 )) || fail "clean qs exit: expected 0, got $rc"
[[ -e "$T/notify" ]] && fail "clean qs exit raised an alert: $(cat "$T/notify")"

echo "ok: shell from Arch's quickshell, no local build, start alerts on missing and dying qs"
