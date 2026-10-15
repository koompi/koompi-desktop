#!/usr/bin/env bash
# The shell finds the global menu daemon on both install routes. ./setup builds
# it into ~/.local/bin (sdata/install/setups/globalmenu.sh); the koompi-shell
# package ships it in /usr/lib/koompi. Until 2026-10 no PKGBUILD shipped it at
# all, so on KOOMPI OS the bar could never show an app menu. Checks that each
# route installs where GlobalMenuService.qml looks, in that order, and runs the
# service's own launch line against stand-ins: the first present one starts, and
# none present is exit 127, which the service does not respawn.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$REPO_ROOT/dots/.config/quickshell/koompi/services/GlobalMenuService.qml"
SETUP_STEP="$REPO_ROOT/sdata/install/setups/globalmenu.sh"
PKGBUILD="$REPO_ROOT/sdata/dist-arch/koompi-shell/PKGBUILD"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

candidates="$(grep -m1 'property var daemonCandidates:' "$QML")"
[[ -n $candidates ]] || { echo "FAIL: GlobalMenuService.qml has no daemonCandidates list" >&2; exit 1; }
user_at="$(grep -bo '"/.local/bin/koompi-global-menu-daemon"' <<< "$candidates" | cut -d: -f1)"
package_at="$(grep -bo '"/usr/lib/koompi/koompi-global-menu-daemon"' <<< "$candidates" | cut -d: -f1)"
[[ -n $user_at ]] || fail "the shell does not look in ~/.local/bin, where ./setup installs the daemon"
[[ -n $package_at ]] || fail "the shell does not look in /usr/lib/koompi, where koompi-shell installs the daemon"
[[ -n $user_at && -n $package_at ]] && (( user_at < package_at )) \
    || fail "~/.local/bin has to come first, as it does for every other koompi binary"

grep -q 'install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-global-menu-daemon"' "$SETUP_STEP" \
    || fail "setups/globalmenu.sh no longer installs to \$XDG_BIN_HOME/koompi-global-menu-daemon"
grep -q '"$pkgdir/usr/lib/koompi/koompi-global-menu-daemon"' "$PKGBUILD" \
    || fail "koompi-shell's package() does not install /usr/lib/koompi/koompi-global-menu-daemon"
grep -q -- '--manifest-path "$_repo_root/globalmenu/Cargo.toml"' "$PKGBUILD" \
    || fail "koompi-shell's build() does not build globalmenu/"

# The service's launch line, as QML hands it to bash.
script="$(sed -n "s/.*command: \[\"bash\", \"-c\", '\(.*\)', \"bash\", \.\.\.root\.daemonCandidates\].*/\1/p" "$QML")"
[[ -n $script ]] || { echo "FAIL: cannot read the daemon's launch line from GlobalMenuService.qml" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for name in first second; do
    printf '#!/bin/sh\necho %s\n' "$name" > "$tmp/$name"
done
chmod +x "$tmp/second"
got="$(bash -c "$script" bash "$tmp/missing" "$tmp/first" "$tmp/second")"
[[ $got == second ]] || fail "the launch line ran '$got', not the first executable candidate"
chmod +x "$tmp/first"
got="$(bash -c "$script" bash "$tmp/first" "$tmp/second")"
[[ $got == first ]] || fail "the launch line ran '$got', not the first candidate"
bash -c "$script" bash "$tmp/missing" "$tmp/also-missing"
[[ $? == 127 ]] || fail "with no daemon installed the launch line does not exit 127"
grep -q 'exitCode === 127' "$QML" || fail "the service respawns a daemon that is not installed"

(( failed == 0 )) || exit 1
echo "ok: both install routes put the daemon where the shell looks"
