#!/usr/bin/env bash
# Guards: a failed zig build stops the install. `( cd "$src" && run zig build )`
# hid it - run aborts via die, die is exit, and inside `( )` that ends only the
# subshell, after which the caller went on to install a binary that was never
# built.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/cache"

cat > "$stub/zig" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == version ]] && { echo 0.16.0; exit 0; }
printf '%s\n' "$*" > "${ZIG_ARGS_FILE:?}"
echo 'zig: simulated build failure' >&2
exit 1
STUB
chmod +x "$stub/zig"

# The setups function, sourced with the installer's own helpers, under --yes
# so a failure has no prompt to hide behind.
run_setup() {
    local fn="$1"
    ZIG_ARGS_FILE="$tmp/zig-args" \
    PATH="$stub:$PATH" HOME="$tmp/home" NO_COLOR=1 \
    XDG_CACHE_HOME="$tmp/cache" XDG_CONFIG_HOME="$tmp/config" XDG_BIN_HOME="$tmp/home/.local/bin" \
    bash -c '
        set -uo pipefail
        REPO_ROOT="$1"; readonly REPO_ROOT
        ASSUME_YES=true
        source "$REPO_ROOT/sdata/lib/common.sh"
        source "$REPO_ROOT/sdata/install/setups.sh"
        "$2"
        echo "REACHED-AFTER-$2"
    ' _ "$REPO_ROOT" "$fn" > "$tmp/out" 2>&1
}

run_setup setup_koompi_cli
status=$?
(( status != 0 )) || fail "setup_koompi_cli exited 0 after zig build failed"
grep -q 'REACHED-AFTER' "$tmp/out" && fail "the install went on after the CLI build failed: $(cat "$tmp/out")"
grep -q 'koompi CLI installed' "$tmp/out" && fail "reported the CLI installed after its build failed"
grep -q 'command failed: zig build' "$tmp/out" || fail "the zig failure never surfaced: $(cat "$tmp/out")"

printf 'zig build abort test passed\n'
