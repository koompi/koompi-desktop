#!/usr/bin/env bash
# an installed koompi-migrate must find sdata/migrations: no package installed them, and the copy ./setup puts in ~/.local/bin looked three directories above itself
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v rsync > /dev/null 2>&1 || { echo "skip: rsync not installed; neither route was built"; exit 0; }

T="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT

shopt -s nullglob
migrations=("$ROOT"/sdata/migrations/*.sh)
shopt -u nullglob
(( ${#migrations[@]} )) || fail "sdata/migrations holds nothing to deliver"

# koompi-migrate as a user sees it: nothing from the caller's environment, a home of its own
migrate() {
    local home="$1" tool="$2"
    shift 2
    mkdir -p "$home"
    env -i PATH="$PATH" HOME="$home" FIXTURE_LOG="${FIXTURE_LOG:-}" "$tool" "$@"
}
lists() {
    local name
    for name in "$@"; do
        grep -qxF -- "$name" <<< "$out" || fail "the listing does not hold $name: $out"
    done
}

fake="$T/repo"
mkdir -p "$fake/sdata/dist-arch"
cp -a "$ROOT/dots" "$fake/dots"
cp -a "$ROOT/sdata/migrations" "$fake/sdata/migrations"
cp -a "$ROOT/sdata/dist-arch/koompi-shell" "$fake/sdata/dist-arch/"
printf '#!/bin/sh\n' > "$T/koompi"
install -Dm755 "$T/koompi" "$T/srcdir/koompi-cli-out/bin/koompi"
mkdir -p "$T/pkg"
# shellcheck disable=SC2034  # the sourced PKGBUILD's package() reads srcdir and pkgdir
(
    set -e
    startdir="$fake/sdata/dist-arch/koompi-shell"
    srcdir="$T/srcdir"
    pkgdir="$T/pkg"
    cd "$startdir"
    # shellcheck disable=SC1091  # the PKGBUILD path is computed, not a literal
    source ./PKGBUILD
    package
) > "$T/package.log" 2>&1 || { cat "$T/package.log" >&2; fail "koompi-shell package() failed"; }

packaged="$T/pkg/usr/share/koompi/migrations"
for m in "${migrations[@]}"; do
    cmp -s -- "$m" "$packaged/${m##*/}" || fail "package() does not install ${m##*/} into /usr/share/koompi/migrations"
    [[ ! -x "$packaged/${m##*/}" ]] || fail "package() installs ${m##*/} executable; the runner calls bash on it"
done
[[ "$(ls -A "$packaged" | wc -l)" -eq ${#migrations[@]} ]] \
    || fail "/usr/share/koompi/migrations holds files that sdata/migrations does not: $(ls -A "$packaged" | tr '\n' ' ')"

out="$(migrate "$T/home-pkg" "$T/pkg/usr/bin/koompi-migrate" --pending 2>&1)" \
    || fail "the packaged koompi-migrate lists nothing pending: $out"
lists "${migrations[@]##*/}"
echo "ok   package: package() installs every migration, and the installed koompi-migrate lists them"

checkout="$T/checkout"
mkdir -p "$checkout/dots/.config" "$checkout/dots/.local/bin" "$checkout/dots/.local/share/koompi/libexec" "$checkout/sdata/migrations"
cp -- "$ROOT/dots/.local/bin/koompi-migrate" "$checkout/dots/.local/bin/"
cp -- "$ROOT/dots/.local/share/koompi/libexec/migrate-lib.sh" "$checkout/dots/.local/share/koompi/libexec/"
printf 'echo ran-one >> "$FIXTURE_LOG"\n' > "$checkout/sdata/migrations/1000000001-fixture-one.sh"
printf 'echo ran-two >> "$FIXTURE_LOG"\n' > "$checkout/sdata/migrations/1000000002-fixture-two.sh"

home="$T/home-setup"
mkdir -p "$home"
(
    export HOME="$home" DRY_RUN=false ASSUME_YES=true NO_COLOR=1 SKIP_BACKUP=false REPO_ROOT="$checkout"
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_BIN_HOME XDG_CACHE_HOME BACKUP_ROOT KOOMPI_STATE_DIR
    source "$ROOT/sdata/lib/common.sh"
    source "$ROOT/sdata/install/files.sh"
    install_files
    record_repo_path
) > "$T/install.out" 2>&1 || fail "install_files failed: $(tail -5 "$T/install.out")"
installed="$home/.local/bin/koompi-migrate"
[[ -x "$installed" ]] || fail "./setup did not install koompi-migrate"

out="$(migrate "$home" "$installed" --pending 2>&1)" \
    || fail "the copy ./setup installed lists nothing pending; repo-path holds '$(cat "$home/.local/state/koompi/repo-path" 2>&1)': $out"
lists 1000000001-fixture-one.sh 1000000002-fixture-two.sh
echo "ok   checkout: the installed koompi-migrate lists the migrations of the checkout ./setup recorded"

out="$(migrate "$T/home-clone" "$checkout/dots/.local/bin/koompi-migrate" --pending 2>&1)" \
    || fail "a clone's own copy of koompi-migrate lists nothing pending: $out"
lists 1000000001-fixture-one.sh 1000000002-fixture-two.sh
echo "ok   checkout: a clone's own copy lists the clone's migrations with nothing recorded"

export FIXTURE_LOG="$T/fixture.log"
migrate "$home" "$installed" run > "$T/run.out" 2>&1 || fail "run failed on the checkout's migrations: $(cat "$T/run.out")"
[[ "$(cat "$FIXTURE_LOG" 2>&1)" == $'ran-one\nran-two' ]] || fail "run did not run the checkout's migrations in order: $(cat "$FIXTURE_LOG" 2>&1)"
out="$(migrate "$home" "$installed" --pending 2>&1)"
grep -q 'fixture' <<< "$out" && fail "a migration that ran is still listed as pending: $out"
migrate "$home" "$installed" run > "$T/run.out" 2>&1 || fail "the second run failed: $(cat "$T/run.out")"
[[ "$(wc -l < "$FIXTURE_LOG")" -eq 2 ]] || fail "the second run ran a migration again: $(cat "$FIXTURE_LOG")"
unset FIXTURE_LOG
echo "ok   checkout: run runs them once, in order"

both="$T/home-both"
mkdir -p "$both/.local/state/koompi"
printf '%s\n' "$checkout" > "$both/.local/state/koompi/repo-path"
cp -- "${migrations[0]}" "$checkout/sdata/migrations/"
out="$(migrate "$both" "$T/pkg/usr/bin/koompi-migrate" --pending 2>&1)" || fail "a packaged machine with a recorded checkout lists nothing: $out"
lists "${migrations[@]##*/}" 1000000001-fixture-one.sh 1000000002-fixture-two.sh
[[ -z "$(sort <<< "$out" | uniq -d)" ]] || fail "a migration found in both the package and the checkout is listed twice: $out"
echo "ok   both: a packaged machine that updates from a checkout runs the migrations of both, once each"

gone="$T/home-gone"
mkdir -p "$gone/.local/state/koompi"
printf '%s\n' "$T/vanished-checkout" > "$gone/.local/state/koompi/repo-path"
out="$(migrate "$gone" "$T/pkg/usr/bin/koompi-migrate" --pending 2>&1)" || fail "a recorded checkout that vanished broke the listing: $out"
lists "${migrations[@]##*/}"
grep -qi 'no such file\|not found\|error' <<< "$out" && fail "a recorded checkout that vanished is reported as an error: $out"
echo "ok   a recorded checkout that vanished is ignored"

if [[ -d /usr/share/koompi/migrations ]]; then
    echo "note: this host has /usr/share/koompi/migrations, so the nothing-to-find case was not run"
else
    out="$(migrate "$T/home-none" "$installed" --pending 2>&1)" && fail "a home with no record and no package lists migrations: $out"
    [[ -z "$out" ]] || fail "nothing to find should print nothing: $out"
    echo "ok   nothing recorded and nothing packaged: nothing pending, no noise"
fi

echo "migrations are delivered on both routes"
