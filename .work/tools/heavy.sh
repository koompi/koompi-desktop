#!/usr/bin/env bash
# heavy.sh CMD...: run CMD holding the machine-wide lock, so one nested compositor or full suite runs at a time
set -euo pipefail
[[ $# -gt 0 ]] || { echo "usage: heavy.sh CMD..." >&2; exit 2; }
[[ -n ${KOOMPI_HEAVY_LOCKED:-} ]] && exec "$@"
export KOOMPI_HEAVY_LOCKED=1
# one waiter per worktree on the shared lock, so one worker's queued batch cannot crowd out the rest
tree=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec flock "/tmp/koompi-heavy-$(printf %s "$tree" | md5sum | cut -c1-12).lock" flock /tmp/koompi-heavy.lock "$@"
