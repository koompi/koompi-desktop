#!/usr/bin/env bash
# The zig global menu daemon left the repo, but not existing homes: ./setup's files step
# syncs ~/.config/quickshell/koompi with rsync --delete and excludes zig-out/ and
# .zig-cache/, and rsync keeps a directory that still holds excluded files. The
# migration removes what is left (and the zig build cache), only while nothing else
# is in that directory, and is a no-op the second time.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

shopt -s nullglob
found=("$ROOT"/sdata/migrations/*-remove-zig-global-menu-build.sh)
[[ ${#found[@]} -eq 1 ]] || fail "expected one remove-zig-global-menu-build migration, found ${#found[@]}"
MIG="${found[0]}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run() { # home -> migration output; fails the test on a non-zero exit
    HOME="$1" XDG_CONFIG_HOME="$1/.config" XDG_CACHE_HOME="$1/.cache" bash -euo pipefail "$MIG" 2>&1 \
        || fail "the migration exited non-zero for $1"
}

# A home as the old ./setup left it: the daemon built in the shell tree, its cache outside.
home="$tmp/home"
shell="$home/.config/quickshell/koompi"
mkdir -p "$shell/scripts/global-menu/src" "$shell/scripts/global-menu/zig-out/bin" \
    "$shell/scripts/global-menu/.zig-cache/h" "$shell/scripts/colors" "$home/.cache/koompi/build/global-menu/cache"
echo daemon > "$shell/scripts/global-menu/zig-out/bin/global-menu-daemon"
echo obj > "$shell/scripts/global-menu/.zig-cache/h/main.o"
echo zig > "$shell/scripts/global-menu/src/main.zig"
echo wall > "$shell/scripts/colors/switchwall.sh"
echo obj > "$home/.cache/koompi/build/global-menu/cache/x.o"

# The files step's own sync, with the tree as the repo now ships it.
grep -q -- "--exclude='zig-out' --exclude='.zig-cache'" "$ROOT/sdata/install/files.sh" \
    || fail "the files step no longer excludes zig build output; re-check what an update leaves behind"
src="$tmp/repo-shell"
mkdir -p "$src/scripts/colors"
echo wall > "$src/scripts/colors/switchwall.sh"
rsync -a --delete --exclude='zig-out' --exclude='.zig-cache' "$src/" "$shell/" > /dev/null 2>&1
[[ -e "$shell/scripts/global-menu/zig-out/bin/global-menu-daemon" ]] \
    || fail "setup: the sync removed the zig build itself, so there is nothing for the migration to do"
[[ -e "$shell/scripts/global-menu/src" ]] && fail "setup: the sync kept the zig sources"

out="$(run "$home")"
[[ ! -e "$shell/scripts/global-menu" ]] || fail "the leftover zig build is still in the shell tree: $out"
[[ ! -e "$home/.cache/koompi/build/global-menu" ]] || fail "the zig build cache is still there: $out"
[[ -f "$shell/scripts/colors/switchwall.sh" ]] || fail "the migration touched the rest of the shell tree"
grep -q 'removed the old zig global menu build' <<< "$out" || fail "the migration did not say what it removed: $out"

out="$(run "$home")"
[[ -z "$out" ]] || fail "a second run did something: $out"

# Something the user put there is not ours to delete.
mine="$tmp/mine"
mkdir -p "$mine/.config/quickshell/koompi/scripts/global-menu/zig-out"
echo note > "$mine/.config/quickshell/koompi/scripts/global-menu/notes.txt"
out="$(run "$mine")"
[[ -f "$mine/.config/quickshell/koompi/scripts/global-menu/notes.txt" ]] || fail "a user's file next to the build output was deleted"
grep -q 'left .* in place' <<< "$out" || fail "the migration did not say why it left the directory: $out"

mkdir -p "$tmp/fresh"
out="$(run "$tmp/fresh")"
[[ -z "$out" ]] || fail "a home that never had the zig daemon got output: $out"

echo "ok: the old zig global menu build is removed from existing homes, once"
