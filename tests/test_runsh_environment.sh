#!/usr/bin/env bash
# tests/run.sh gives every test one environment: the caller's XDG dirs and live displays are gone, the runtime dir is its own, and easyeffects is a recorder that comes first on PATH
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
for v in XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME KOOMPI_STATE_DIR WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE; do
    [[ -z "\${!v:-}" ]] || { echo "\$v reached the test: \${!v}"; exit 1; }
done
[[ "\${QT_QPA_PLATFORM:-}" == offscreen ]] || { echo "QT_QPA_PLATFORM is \${QT_QPA_PLATFORM:-unset}, not offscreen"; exit 1; }
[[ "\${XDG_DATA_DIRS:-}" == "$T/datadirs" ]] || { echo "XDG_DATA_DIRS changed to \${XDG_DATA_DIRS:-unset}"; exit 1; }
rt="\${XDG_RUNTIME_DIR:-}"
[[ -n "\$rt" && "\$rt" != "$T/runtime" ]] || { echo "XDG_RUNTIME_DIR is the caller's: \${rt:-unset}"; exit 1; }
[[ "\${KOOMPI_TEST_LIVE_RUNTIME_DIR:-}" == "$T/runtime" ]] || { echo "the caller's runtime dir is not handed on as KOOMPI_TEST_LIVE_RUNTIME_DIR"; exit 1; }
[[ -d "\$rt" && "\$(stat -c %a "\$rt")" == 700 && -z "\$(ls -A "\$rt")" ]] || { echo "XDG_RUNTIME_DIR \$rt is not an empty 0700 dir"; exit 1; }
echo "\$rt" >> "$T/runtimes"
easyeffects --hide-window --service-mode || { echo "the easyeffects stand-in did not exit 0"; exit 1; }
PROBE
cat > "$T/tests/test_probe_own.sh" <<PROBE
#!/usr/bin/env bash
PATH="$T/own:\$PATH"
first="\$(head -1 "$T/runtimes")"
[[ -n "\$first" && ! -e "\$first" ]] || { echo "the test before this one left its runtime dir: \${first:-none recorded}"; exit 1; }
echo "\$XDG_RUNTIME_DIR" >> "$T/runtimes"
easyeffects --its-own
PROBE

out="$(NO_COLOR=1 PATH="$T/fakebin:$PATH" TMPDIR="$T/tmp" \
    WAYLAND_DISPLAY=wayland-live DISPLAY=:live HYPRLAND_INSTANCE_SIGNATURE=live QT_QPA_PLATFORM=wayland \
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
[[ "$(sort -u "$T/runtimes" | wc -l)" -eq 2 ]] || fail "the two tests did not get a runtime dir each: $(cat "$T/runtimes" 2>&1)"
echo "run.sh environment ok"
