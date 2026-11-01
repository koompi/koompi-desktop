#!/usr/bin/env bash
# The offline model is 2.6 GB. An unattended install (-y, which the ISO's first
# boot runs) must leave it out instead of taking the yes; one run by hand asks,
# and downloads on a yes only. uv, litert-lm, docker and podman are shimmed, so
# nothing is downloaded and no container is started.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

shims="$tmp/bin"; mkdir -p "$shims"
log="$tmp/calls"
# litert-lm lists no models, so the model question is always reached
printf '#!/usr/bin/env bash\n[[ "$1" == list ]] && exit 0\nprintf "litert-lm %%s\\n" "$*" >> "%s"\n' "$log" > "$shims/litert-lm"
printf '#!/usr/bin/env bash\nprintf "uv %%s\\n" "$*" >> "%s"\n' "$log" > "$shims/uv"
# inspect answers "already present", so the search step stops before a pull
for runtime in docker podman; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s"\n' "$runtime" "$log" > "$shims/$runtime"
done
chmod 755 "$shims"/*

run_setup() { # ASSUME_YES, then the answer on stdin
    : > "$log"
    rm -rf "${tmp:?}/home"; mkdir -p "$tmp/home"
    (
        export PATH="$shims:$PATH" HOME="$tmp/home" DRY_RUN=false ASSUME_YES="$1" \
            REPO_ROOT="$ROOT" OS_GROUP_ID=arch NO_COLOR=1
        unset XDG_BIN_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
        cd "$ROOT" || exit 1
        # shellcheck source=../sdata/lib/common.sh
        source sdata/lib/common.sh
        # shellcheck source=../sdata/install/setups.sh
        source sdata/install/setups.sh
        setup_local_ai
        printf 'units=%s\n' "${LOCAL_AI_UNITS:-false}"
    ) 2>&1
}

# 1. Unattended: no download, the units stay off, and the skip says how to get it.
out="$(run_setup true < /dev/null)" || fail "setup_local_ai -y failed: $out"
grep -q 'litert-lm import' "$log" && fail "an unattended install downloaded the 2.6 GB model"
grep -Fq 'unattended install' <<< "$out" || fail "the skip does not say why: $out"
grep -Fq 'litert-lm import --from-huggingface-repo' <<< "$out" \
    || fail "the skip does not print the command to fetch the model later: $out"
grep -Fxq 'units=false' <<< "$out" || fail "litert-lm.socket is enabled with no model to serve"
[[ -s "$tmp/home/.litert-lm/config.json" ]] || fail "the litert-lm config is not written on an unattended install"

# 2. By hand, a yes downloads.
out="$(run_setup false <<< y)" || fail "setup_local_ai with a yes failed: $out"
grep -Fq 'litert-lm import --from-huggingface-repo' "$log" || fail "a yes did not download the model: $out"
grep -Fxq 'units=true' <<< "$out" || fail "a downloaded model does not get litert-lm.socket"

# 3. By hand, a no does not.
out="$(run_setup false <<< n)" || fail "setup_local_ai with a no failed: $out"
grep -q 'litert-lm import' "$log" && fail "a no still downloaded the model"
grep -Fxq 'units=false' <<< "$out" || fail "a no still enables litert-lm.socket"

echo "ok test_local_ai_unattended.sh"
