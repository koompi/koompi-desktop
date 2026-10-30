#!/usr/bin/env bash
# Guards: an AUR key fetch cannot hang an install. paru imports signing keys with
# `gpg --recv-keys`, which a stalled keyserver held forever at an ISO first boot.
# sdata/lib/paru-gpg bounds the fetch; every paru install has to go through it.
#
# Runs paru-gpg against a stub gpg on PATH; touches no keyring and no network.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

stub="$(mktemp -d)"
trap 'rm -rf "$stub"' EXIT
calls="$stub/calls"

# The stub records each call; a fetch hangs until the try named in $GPG_GOOD.
cat > "$stub/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[[ " $* " == *" --recv-keys "* ]] || exit 0
n=$(grep -c -- '--recv-keys' "$CALLS")
(( n >= ${GPG_GOOD:-99} )) && exit 0
exec sleep 30
EOF
# shellcheck disable=SC2016  # expands in the stub, not here
printf '#!/bin/sh\necho "gpgconf $*" >> "$CALLS"\n' > "$stub/gpgconf"
chmod +x "$stub/gpg" "$stub/gpgconf"
export CALLS="$calls" PATH="$stub:$PATH" KOOMPI_GPG_FETCH_TIMEOUT=1

# Anything but a fetch is plain gpg, arguments untouched.
"$REPO_ROOT/sdata/lib/paru-gpg" --list-keys "a b" || fail "a plain gpg call failed"
[[ "$(cat "$calls")" == "--list-keys a b" ]] || fail "a plain call was changed: $(cat "$calls")"

# A fetch that never answers gives up after three tries, and says so.
: > "$calls"
start=$SECONDS
out="$("$REPO_ROOT/sdata/lib/paru-gpg" --recv-keys F4FDB18A 2>&1)" && fail "a hung fetch reported success"
(( SECONDS - start < 15 )) || fail "a hung fetch was not cut off ($((SECONDS - start))s)"
[[ "$(grep -c -- '--recv-keys' "$calls")" == 3 ]] || fail "expected three tries: $(cat "$calls")"
grep -q 'gpgconf --kill dirmngr' "$calls" || fail "dirmngr was not restarted between tries"
[[ "$out" == *"could not fetch F4FDB18A"* ]] || fail "no message naming the key: $out"

# A fetch that answers on the second try succeeds.
: > "$calls"
GPG_GOOD=2 "$REPO_ROOT/sdata/lib/paru-gpg" --recv-keys F4FDB18A 2>/dev/null || fail "the second try's success was lost"

# Every paru install in the recipes goes through arch_paru.
bare="$({ grep -rnE --include='*.sh' '(^|[^_[:alnum:]-])paru +-S' "$REPO_ROOT"/sdata
          grep -nHE '(^|[^_[:alnum:]-])paru +-S' "$REPO_ROOT"/setup "$REPO_ROOT"/install.sh; } 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:\s*#')"
[[ -z "$bare" ]] || fail "paru called without paru-gpg (use arch_paru):"$'\n'"$bare"
# shellcheck disable=SC2016  # the literal text in arch.sh
grep -q 'paru --gpg "$REPO_ROOT/sdata/lib/paru-gpg"' "$REPO_ROOT/sdata/lib/arch.sh" \
    || fail "arch_paru no longer passes paru-gpg"

printf 'paru gpg test passed\n'
