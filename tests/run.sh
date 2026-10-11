#!/usr/bin/env bash
# Run every test in this directory:  ./tests/run.sh
#
# Shell-level regression tests. Each shadows the commands that would touch the
# machine (pacman, makepkg, sudo, killall, hyprctl) and asserts on what the code
# tried to do, so nothing installs, removes, stops or reads a password.
#
# A test that cannot run here (no bun, no python-evdev, no live compositor) says
# so on a line containing "skipping" or starting with "skip:" and exits 0. It is
# counted as skipped, not passed, and its note is always printed, so a machine
# missing half the tools cannot report a green run that checked nothing. Only a
# non-zero exit fails the run.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# a test that pins only HOME writes into whatever these name when the caller exports them
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME KOOMPI_STATE_DIR

# a stray GUI process finds no compositor and lands offscreen, not on the founder's screen
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
export QT_QPA_PLATFORM=offscreen

# only the user manager and PipeWire checks (test_app_slice, test_shell_services) read the real runtime dir, through this
export KOOMPI_TEST_LIVE_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"

# the real easyeffects aborts in a nested test session and each abort toasts the live desktop; a test that wants one puts its own first on PATH
scratch="$(mktemp -d)" || { echo "run.sh: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${scratch:?}"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/easyeffects" <<STUB
#!/usr/bin/env bash
printf '%s\t%s\n' "\${KOOMPI_RUNSH_TEST:-?}" "\$*" >> "$scratch/easyeffects.calls"
exit 0
STUB
chmod +x "$scratch/bin/easyeffects"
export PATH="$scratch/bin:$PATH"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_RST=''
fi

passed=0
skipped=0
failed=0
skips=()
failures=()

for test in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test" ]] || continue
    name="$(basename -- "$test")"
    printf '%s==> %s%s\n' "${C_BOLD}" "$name" "${C_RST}"

    # qs registers its instance and sockets in the runtime dir, so each test gets one of its own
    rt="$(mktemp -d "$scratch/rt.XXXXXX")" || { echo "run.sh: mktemp -d failed" >&2; exit 1; }
    chmod 700 "$rt"

    # Invoked through bash rather than executed, so a test that arrived without
    # its executable bit is still run instead of being reported as a failure.
    output="$(XDG_RUNTIME_DIR="$rt" KOOMPI_RUNSH_TEST="$name" bash "$test" 2>&1 < /dev/null)"
    rc=$?
    rm -rf "${rt:?}"
    if (( rc != 0 )); then
        printf '%s\n' "$output"
        printf '%s  xx%s %s\n' "${C_RED}" "${C_RST}" "$name"
        failed=$((failed + 1))
        failures+=("$name")
    elif notes="$(grep -E 'skipping|^[[:space:]]*skip:' <<< "$output")"; then
        printf '%s\n' "$notes" | sed 's/^[[:space:]]*/      /'
        printf '%s  --%s %s (skipped)\n' "${C_YELLOW}" "${C_RST}" "$name"
        skipped=$((skipped + 1))
        skips+=("$name")
    else
        printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RST}" "$name"
        passed=$((passed + 1))
    fi
done

if [[ -s "$scratch/easyeffects.calls" ]]; then
    printf '\neasyeffects was started by (count, test, arguments):\n'
    sort "$scratch/easyeffects.calls" | uniq -c | sed 's/^/  /'
fi

printf '\n%s%d passed, %d skipped, %d failed%s\n' "${C_BOLD}" "$passed" "$skipped" "$failed" "${C_RST}"
(( skipped == 0 )) || printf 'skipped: %s\n' "${skips[*]}" >&2
(( failed == 0 )) || {
    printf 'failed: %s\n' "${failures[*]}" >&2
    exit 1
}
