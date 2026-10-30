#!/usr/bin/env bash
# Pull to refresh end to end under Playwright (tests/e2e_touchpad_pull.py): a real Chromium,
# the real extension, the real native messaging host reading a stand-in touchpad. A full pull
# held still does not reload, lifting the fingers does; a short pull or one taken back does not.
# Runs only from uv's cache, so the suite never reaches the network for it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
browser="$(command -v chromium || true)"
[[ -n "$browser" ]] || { echo "skip: no chromium (Chrome refuses --load-extension)"; exit 0; }
command -v uv > /dev/null || { echo "skip: no uv"; exit 0; }
uv run -q --offline --no-project --with playwright python -c 'import playwright' > /dev/null 2>&1 \
    || { echo "skip: playwright is not in uv's cache; uv run --with playwright once to fetch it"; exit 0; }

shots="$(mktemp -d)"
trap 'rm -rf "$shots"' EXIT
out="$(timeout 300 uv run -q --offline --no-project --with playwright python "$REPO_ROOT/tests/e2e_touchpad_pull.py" "$browser" "$shots" 2>&1)"
status=$?
if (( status != 0 )); then
    printf 'FAIL: pull to refresh end to end\n%s\n' "$out" >&2
    exit 1
fi
echo "ok   pull to refresh end to end: reloads when the fingers lift, never while they hold"
