#!/usr/bin/env bash
# heavy.sh CMD...: run CMD holding the machine-wide lock, so one nested compositor or full suite runs at a time
set -euo pipefail
[[ $# -gt 0 ]] || { echo "usage: heavy.sh CMD..." >&2; exit 2; }
[[ -n ${KOOMPI_HEAVY_LOCKED:-} ]] && exec "$@"
# the lead pauses the swarm's heavy runs (on battery) by creating this file; waiting happens outside the lock
while [[ -e /tmp/koompi-heavy.pause ]]; do sleep 10; done
export KOOMPI_HEAVY_LOCKED=1
# one waiter per worktree on the shared lock so one worker's batch cannot crowd out the rest; -o so a child the run leaves behind cannot keep holding it
tree=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
exec flock -o "/tmp/koompi-heavy-$(printf %s "$tree" | md5sum | cut -c1-12).lock" flock -o /tmp/koompi-heavy.lock "$@"
