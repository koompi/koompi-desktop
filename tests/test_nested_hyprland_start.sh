#!/usr/bin/env bash
# tests/nested-hyprland.sh starts a nested Hyprland again when it has no output (aquamarine 0.15.1 can leave a new
# output's requests unflushed for good, hyprwm/aquamarine#415). Stand-ins for Hyprland and hyprctl, no compositor:
#   an output on the first start             -> one start, nothing said
#   no output on the first, one on the second -> two starts, the first stopped with its children, the second's signature and socket exported
#   no output ever                            -> ten starts, all stopped, a non-zero answer
#   a Hyprland that dies on its own           -> one start, the log named, no second try
#   a config that leaves update news on       -> refused before anything starts
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in jq pgrep; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, nested-hyprland.sh not run"; exit 0; }
done

WORK="$(mktemp -d)" || { fail "mktemp -d failed"; exit 1; }
trap 'while read -r pid; do kill "$pid" 2> /dev/null; done < <(cat "$WORK"/*/pids "$WORK"/*/children 2> /dev/null); rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/Hyprland" <<'SH'
#!/usr/bin/env bash
n=$(( $(cat "$STUB_DIR/starts" 2> /dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/starts"
[[ $STUB_MODE == crash ]] && exit 3
sleep 120 &
echo "$!" >> "$STUB_DIR/children"
mkdir -p "$XDG_RUNTIME_DIR/hypr/stub-$n"
echo "$$" >> "$STUB_DIR/pids"
printf '%s\nwayland-stub-%s\n' "$$" "$n" > "$XDG_RUNTIME_DIR/hypr/stub-$n/hyprland.lock"
exec sleep 120
SH
cat > "$WORK/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
n=${HYPRLAND_INSTANCE_SIGNATURE#stub-}
case $1 in
    monitors) if [[ " $STUB_OUTPUT_ON " == *" $n "* ]]; then echo '[{"id":0}]'; else echo '[]'; fi ;;
    dispatch) read -r pid < "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock"; kill "$pid" ;;
esac
SH
chmod +x "$WORK/bin/Hyprland" "$WORK/bin/hyprctl"

quiet="$WORK/quiet.lua"
loud="$WORK/loud.lua"
echo 'hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })' > "$quiet"
echo 'hl.config({ misc = { disable_watchdog_warning = true } })' > "$loud"

# start CASE OUTPUT_ON MODE CONFIG: one nested_hyprland_start in a runtime dir of its own; the answer lands in $WORK/CASE/answer
start() {
    local case_dir="$WORK/$1"
    mkdir -p "$case_dir/rt"
    chmod 700 "$case_dir/rt"
    (
        export STUB_DIR="$case_dir" STUB_OUTPUT_ON="$2" STUB_MODE="$3" XDG_RUNTIME_DIR="$case_dir/rt" NESTED_HYPRLAND_OUTPUT_POLLS=3
        export PATH="$WORK/bin:$PATH" WAYLAND_DISPLAY=host-0
        source "$ROOT/tests/nested-hyprland.sh"
        nested_hyprland_start "$4" "$case_dir/hyprland.log" 2> "$case_dir/stderr"
        echo "rc=$? starts=$(cat "$case_dir/starts" 2> /dev/null || echo 0) signature=${HYPRLAND_INSTANCE_SIGNATURE:-} display=$WAYLAND_DISPLAY pid=${hypr_pid:-}" > "$case_dir/answer"
    )
}
answer() { cat "$WORK/$1/answer" 2> /dev/null; }
alive() { kill -0 "$1" 2> /dev/null; }

start direct 1 ok "$quiet"
[[ "$(answer direct)" == rc=0\ starts=1\ signature=stub-1\ display=wayland-stub-1\ pid=* ]] || fail "an output on the first start: '$(answer direct)'"
[[ ! -s $WORK/direct/stderr ]] || fail "an output on the first start was still reported: $(cat "$WORK/direct/stderr")"

start wedged 2 ok "$quiet"
[[ "$(answer wedged)" == rc=0\ starts=2\ signature=stub-2\ display=wayland-stub-2\ pid=* ]] || fail "no output on the first start, one on the second: '$(answer wedged)'"
grep -q 'no output 0.3 s after start 1 of 10' "$WORK/wedged/stderr" || fail "the empty first start was not reported: $(cat "$WORK/wedged/stderr")"
first="$(sed -n 1p "$WORK/wedged/pids")"
second="$(sed -n 2p "$WORK/wedged/pids")"
[[ -n $first && -n $second ]] || fail "the stand-in Hyprland did not record two starts"
alive "$first" && fail "the Hyprland without an output was left running"
alive "$second" || fail "the Hyprland with an output was stopped"
alive "$(sed -n 1p "$WORK/wedged/children")" && fail "a child of the Hyprland without an output was left running"
alive "$(sed -n 2p "$WORK/wedged/children")" || fail "a child of the Hyprland with an output was stopped"
[[ "$(answer wedged)" == *"pid=$second" ]] || fail "hypr_pid is not the second start's pid ($second): '$(answer wedged)'"
grep -c 'nested Hyprland start' "$WORK/wedged/hyprland.log" | grep -qx 2 || fail "the log does not hold both starts"

start never "" ok "$quiet"
[[ "$(answer never)" == rc=1\ starts=10\ * ]] || fail "no output ever: '$(answer never)'"
grep -q 'giving up after 10 starts' "$WORK/never/stderr" || fail "giving up was not reported: $(cat "$WORK/never/stderr")"
while read -r pid; do alive "$pid" && fail "a Hyprland without an output was left running (pid $pid)"; done < "$WORK/never/pids"
while read -r pid; do alive "$pid" && fail "a child of a Hyprland without an output was left running (pid $pid)"; done < "$WORK/never/children"

start crash "" crash "$quiet"
[[ "$(answer crash)" == rc=1\ starts=1\ * ]] || fail "a Hyprland that dies on its own: '$(answer crash)'"
grep -q 'exited before it was ready' "$WORK/crash/stderr" || fail "the dead Hyprland was not reported: $(cat "$WORK/crash/stderr")"

start loud 1 ok "$loud"
[[ "$(answer loud)" == rc=2\ starts=0\ * ]] || fail "a config that leaves update news on: '$(answer loud)'"

(( failed )) && exit 1
echo "ok   nested-hyprland.sh: an empty start is redone, ten starts at most, a dead Hyprland and a loud config are not"
