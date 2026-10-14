#!/usr/bin/env bash
# Under --yes nobody can answer retry/skip/abort, so run() tries a failed command again
# twice before it aborts: one 503 from GitHub or the AUR used to end an unattended
# install half way. A command that fails every time still aborts, and an interactive
# run still asks instead of retrying on its own.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# fails the first $1 times it runs, then succeeds
cat > "$tmp/flaky" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$COUNT" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$COUNT"
(( n > LIMIT ))
STUB
chmod +x "$tmp/flaky"

attempt() {
    rm -f "$tmp/count"
    COUNT="$tmp/count" LIMIT="$1" bash -c '
        source "$1/sdata/lib/common.sh"
        DRY_RUN=false ASSUME_YES=true KOOMPI_RETRY_DELAY=0
        run "$2"' _ "$ROOT" "$tmp/flaky" > "$tmp/out" 2>&1
}

attempt 1 || fail "a command that failed once aborted under --yes: $(cat "$tmp/out")"
[[ "$(cat "$tmp/count")" == 2 ]] || fail "the retried command ran $(cat "$tmp/count") times, want 2"
grep -q 'trying again' "$tmp/out" || fail "the retry was not announced"

attempt 2 || fail "a command that failed twice aborted under --yes"

attempt 9 && fail "a command that always fails did not abort under --yes"
[[ "$(cat "$tmp/count")" == 3 ]] || fail "an always-failing command ran $(cat "$tmp/count") times, want 3"
grep -q 'aborting (--yes means no interactive recovery)' "$tmp/out" || fail "the abort did not say why"

# interactive: asks, and abort (the default on EOF) ends it after one try
rm -f "$tmp/count"
COUNT="$tmp/count" LIMIT=9 bash -c '
    source "$1/sdata/lib/common.sh"
    DRY_RUN=false ASSUME_YES=false
    run "$2"' _ "$ROOT" "$tmp/flaky" > "$tmp/out" 2>&1 < /dev/null && fail "an interactive run carried on after a failure"
[[ "$(cat "$tmp/count")" == 1 ]] || fail "an interactive run retried on its own ($(cat "$tmp/count") runs)"

(( failed )) || echo "ok   run: --yes retries a failed command twice, then aborts; interactive runs still ask"
exit $failed
