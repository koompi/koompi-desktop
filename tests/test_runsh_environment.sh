#!/usr/bin/env bash
# tests/run.sh gives every test one environment: the caller's XDG dirs are gone, and easyeffects is a recorder that comes first on PATH
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "${T:?}"' EXIT
mkdir -p "$T/tests" "$T/fakebin" "$T/own" "$T/tmp" "$T/decoy"
cp -- "$ROOT/tests/run.sh" "$T/tests/run.sh"

cat > "$T/fakebin/easyeffects" <<STUB
#!/usr/bin/env bash
echo started >> "$T/real-started"
STUB
cat > "$T/own/easyeffects" <<STUB
#!/usr/bin/env bash
echo started >> "$T/own-started"
STUB
chmod +x "$T/fakebin/easyeffects" "$T/own/easyeffects"

cat > "$T/tests/test_probe_env.sh" <<PROBE
#!/usr/bin/env bash
for v in XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME KOOMPI_STATE_DIR; do
    [[ -z "\${!v:-}" ]] || { echo "\$v reached the test: \${!v}"; exit 1; }
done
[[ "\${XDG_RUNTIME_DIR:-}" == "$T/runtime" ]] || { echo "XDG_RUNTIME_DIR changed to \${XDG_RUNTIME_DIR:-unset}"; exit 1; }
[[ "\${XDG_DATA_DIRS:-}" == "$T/datadirs" ]] || { echo "XDG_DATA_DIRS changed to \${XDG_DATA_DIRS:-unset}"; exit 1; }
easyeffects --hide-window --service-mode || { echo "the easyeffects stand-in did not exit 0"; exit 1; }
PROBE
cat > "$T/tests/test_probe_own.sh" <<PROBE
#!/usr/bin/env bash
PATH="$T/own:\$PATH"
easyeffects --its-own
PROBE

out="$(env -u HYPRLAND_INSTANCE_SIGNATURE NO_COLOR=1 PATH="$T/fakebin:$PATH" TMPDIR="$T/tmp" \
    XDG_CONFIG_HOME="$T/decoy/config" XDG_STATE_HOME="$T/decoy/state" XDG_DATA_HOME="$T/decoy/data" XDG_CACHE_HOME="$T/decoy/cache" \
    KOOMPI_STATE_DIR="$T/decoy/koompi-state" XDG_RUNTIME_DIR="$T/runtime" XDG_DATA_DIRS="$T/datadirs" \
    bash "$T/tests/run.sh" 2>&1)"
rc=$?

[[ $rc -eq 0 ]] || fail "run.sh failed its two probes (rc=$rc): $out"
grep -q '2 passed, 0 skipped, 0 failed' <<<"$out" || fail "run.sh did not run both probes: $out"
[[ ! -e "$T/real-started" ]] || fail "a test started the real easyeffects: the stand-in is not first on PATH"
[[ -e "$T/own-started" ]] || fail "a test's own easyeffects lost to the stand-in"
tab=$'\t'
grep -q "^ *1 test_probe_env\\.sh${tab}--hide-window --service-mode\$" <<<"$out" || fail "the record does not name the test that started easyeffects and its arguments: $out"
grep -q 'test_probe_own.sh.*--its-own' <<<"$out" && fail "the record lists a test that used its own easyeffects: $out"
[[ -z "$(ls -A "$T/tmp")" ]] || fail "run.sh left its scratch dir behind: $(ls -A "$T/tmp")"
echo "run.sh environment ok"
