#!/usr/bin/env bash
# KOOMPI Desktop installs on Arch and the distributions built on it, and nowhere else.
#   1. Arch and its derivatives reach the arch recipe; everything else reaches none.
#   2. setup refuses another distro before it changes anything, and says what it runs on.
#   3. install.sh refuses it before cloning.
# Then the zig and cargo floors, which the Arch recipe relies on too.
# Nothing here touches the network or a package manager.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

DRY_RUN=true ASSUME_YES=true
# shellcheck source=sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"
# shellcheck source=sdata/lib/distro.sh
source "$ROOT/sdata/lib/distro.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

os_release() { { printf 'ID=%s\nPRETTY_NAME="%s"\n' "$2" "$1"; [[ -n "$3" ]] && printf 'ID_LIKE="%s"\n' "$3"; } > "$tmp/os-release"; }

# 1. Arch, its derivatives through ID_LIKE, and nothing else.
check_group() {
    local name="$1" id="$2" like="$3" want="$4"
    os_release "$name" "$id" "$like"
    KOOMPI_OS_RELEASE="$tmp/os-release" detect_distro
    [[ "$OS_GROUP_ID" == "$want" ]] \
        || fail "$name mapped to '${OS_GROUP_ID:-none}', expected '${want:-none}'"
}
check_group arch        arch                ''              arch
check_group koompi      koompi              ''              arch
check_group endeavouros endeavouros         'arch'          arch
check_group cachyos     cachyos             'arch'          arch
check_group manjaro     manjaro             'arch'          arch
check_group fedora      fedora              ''              ''
check_group ubuntu      ubuntu              'debian'        ''
check_group debian      debian              ''              ''
check_group tumbleweed  opensuse-tumbleweed 'suse'          ''
[[ -d "$ROOT/sdata/dist-arch" ]] || fail "sdata/dist-arch is missing"
for f in install-deps.sh install-apps.sh; do
    [[ -f "$ROOT/sdata/dist-arch/$f" ]] || fail "missing sdata/dist-arch/$f"
done
compgen -G "$ROOT/sdata/dist-*" | grep -v '/dist-arch$' && fail "a recipe for another distro is back in sdata/"

# 2. setup on another distro stops before the confirmation, with the reason.
os_release "Ubuntu 26.04 LTS" ubuntu debian
out="$(KOOMPI_OS_RELEASE="$tmp/os-release" "$ROOT/setup" install --dry-run -y 2>&1 < /dev/null)" \
    && fail "setup install went ahead on Ubuntu: $out"
grep -q 'Arch Linux and Arch-based distributions only' <<< "$out" || fail "setup did not say what it runs on: $out"
grep -q 'This is Ubuntu 26.04 LTS' <<< "$out" || fail "setup did not name the system it refused: $out"
grep -q 'About to install' <<< "$out" && fail "setup reached the confirmation on Ubuntu"
os_release "Arch Linux" arch ''
out="$(KOOMPI_OS_RELEASE="$tmp/os-release" "$ROOT/setup" install --dry-run -y --no-deps --no-apps --no-setups --no-files 2>&1 < /dev/null)"
grep -q 'Arch Linux and Arch-based distributions only' <<< "$out" && fail "setup refused Arch: $out"

# 3. install.sh says no before it clones anything.
grep -q '^is_arch || die' "$ROOT/install.sh" || fail "install.sh no longer checks for Arch before cloning"
grep -qE 'dnf|apt-get' "$ROOT/install.sh" && fail "install.sh still knows another package manager"

# 4. The zig floor. A stub stands in for the distro's compiler, behind a PATH
#    holding only that stub and the one tool zig_usable itself runs - otherwise
#    this host's real zig answers, and the no-zig case can never be reached.
mkdir -p "$tmp/bin"
ln -s "$(command -v sort)" "$tmp/bin/sort"

zig_says() {
    printf '#!/bin/sh\necho %s\n' "$1" > "$tmp/bin/zig"
    chmod +x "$tmp/bin/zig"
}
floor_accepts() { ( PATH="$tmp/bin"; zig_usable ); }

zig_says 0.14.1; floor_accepts && fail "zig 0.14.1 passed a ${ZIG_MIN} floor"
zig_says 0.15.2; floor_accepts && fail "zig 0.15.2 passed a ${ZIG_MIN} floor"
zig_says 0.16.0; floor_accepts || fail "zig 0.16.0 failed a ${ZIG_MIN} floor"
zig_says 0.17.0; floor_accepts || fail "zig 0.17.0 failed a ${ZIG_MIN} floor"
zig_says 1.0.0;  floor_accepts || fail "zig 1.0.0 failed a ${ZIG_MIN} floor"
# A pre-release is not the release it names, and the daemon needs the release.
zig_says 0.16.0-dev.164+bc7955306; floor_accepts && fail "a 0.16.0-dev build passed the floor"
# ...but a pre-release of the next one is still above this floor.
zig_says 0.17.0-dev.1+aaaaaaaaa;   floor_accepts || fail "a 0.17.0-dev build failed the floor"
rm -f "$tmp/bin/zig"; floor_accepts && fail "no zig at all passed the floor"

# 5. The floor has to match what the daemon actually declares, or one moves
#    without the other and the check starts lying.
declared="$(sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' \
    "$ROOT/dots/.config/quickshell/koompi/scripts/global-menu/build.zig.zon")"
[[ "$declared" == "$ZIG_MIN" ]] \
    || fail "global-menu declares zig $declared but common.sh floors at $ZIG_MIN"

# 5b. Same trap on the rust side. cargo_usable is a plain version compare, so
#     the pre-release trap zig has does not apply, but the drift one does.
cargo_says() {
    printf '#!/bin/sh\necho "cargo %s (c980f4866 2026-06-30)"\n' "$1" > "$tmp/bin/cargo"
    chmod +x "$tmp/bin/cargo"
}
cargo_floor_accepts() { ( PATH="$tmp/bin"; cargo_usable ); }
ln -sf "$(command -v awk)" "$tmp/bin/awk"

cargo_says 1.75.0; cargo_floor_accepts && fail "cargo 1.75.0 passed a ${RUST_MIN} floor"
cargo_says 1.87.0; cargo_floor_accepts || fail "cargo 1.87.0 failed a ${RUST_MIN} floor"
cargo_says 1.97.1; cargo_floor_accepts || fail "cargo 1.97.1 failed a ${RUST_MIN} floor"
rm -f "$tmp/bin/cargo"; cargo_floor_accepts && fail "no cargo at all passed the floor"

rust_declared="$(sed -n 's/^rust-version = "\([^"]*\)".*/\1/p' "$ROOT/globalmenu/Cargo.toml")"
[[ "$rust_declared" == "$RUST_MIN" ]] \
    || fail "globalmenu declares rust $rust_declared but common.sh floors at $RUST_MIN"

echo "ok"
