#!/usr/bin/env bash
# install_files only fetches the shapes submodule when the file it tests for is
# missing. A path the submodule never had re-runs `git submodule update` on every
# install, and that dies in any tree that is not a git checkout.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

probe="$(sed -n 's#.*\$REPO_ROOT/\(dots/[^"]*/widgets/shapes/[^"]*\)".*#\1#p' "$REPO_ROOT/sdata/install/files.sh")"
[[ -n "$probe" ]] || { echo 'FAIL: files.sh no longer probes the shapes submodule' >&2; exit 1; }
[[ "$(wc -l <<< "$probe")" -eq 1 ]] || { echo 'FAIL: more than one shapes probe in files.sh' >&2; exit 1; }

[[ -e "$REPO_ROOT/$probe" ]] || { echo "FAIL: files.sh tests for $probe, which the checked-out submodule does not contain" >&2; exit 1; }
printf 'ok: %s\n' "$probe"
