#!/usr/bin/env bash
# audiod with no pipewire socket reports unavailable and exits 1 within a bound, 32 copies at a time
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIOD="${AUDIOD:-$REPO_ROOT/audiod/zig-out/bin/audiod}"
COPIES=32
LIMIT=15

command -v zig > /dev/null || { echo "skip: no zig, audiod is not built"; exit 0; }

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ ! -x $AUDIOD ]]; then
    (cd "$REPO_ROOT/audiod" && zig build) > "$tmp/zig.log" 2>&1 || { tail -20 "$tmp/zig.log"; fail "audiod does not build"; exit 1; }
fi

run_copy() {
    local n=$1 runtime="$tmp/run$1" started
    mkdir -p "$runtime"
    chmod 700 "$runtime"
    started=$SECONDS
    env -u PIPEWIRE_REMOTE XDG_RUNTIME_DIR="$runtime" timeout 20 "$AUDIOD" < /dev/null > "$tmp/out$n" 2> /dev/null
    printf '%s %s\n' "$?" "$(( SECONDS - started ))" > "$tmp/res$n"
}

for n in $(seq 1 "$COPIES"); do run_copy "$n" & done
wait

for n in $(seq 1 "$COPIES"); do
    read -r rc secs < "$tmp/res$n" || { fail "copy $n left no result"; continue; }
    [[ $rc == 1 ]] || fail "copy $n exited $rc, not 1 (124 is a hang)"
    (( secs < LIMIT )) || fail "copy $n took ${secs}s"
    grep -q '"reason":"connect_failed"' "$tmp/out$n" || fail "copy $n did not report connect_failed: $(cat "$tmp/out$n")"
done

(( failed )) && exit 1
echo "ok   $COPIES audiod runs with no pipewire socket each report connect_failed and exit 1 in under ${LIMIT}s"
