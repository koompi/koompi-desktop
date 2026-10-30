#!/usr/bin/env bash
# A stand-in for /usr/local/bin/koompi-install that touches nothing: it reads
# the answers file like the engine (and deletes it), then prints log lines and
# @@koompi progress with sleeps.
#
#   KOOMPI_FAKE_FAIL=N    fail during step N (exit 1)
#   KOOMPI_FAKE_DELAY=S   seconds per step (default 1)
#   KOOMPI_FAKE_COPY=F    keep a copy of the answers here, for tests
set -u
answers=""
while (( $# )); do
    case "$1" in
        --answers) answers="${2:-}"; shift 2 ;;
        *) echo "fake-engine: unknown argument $1" >&2; exit 2 ;;
    esac
done
[[ -f "$answers" ]] || { echo "@@koompi fail no answers file"; exit 2; }
mode="$(stat -c %a "$answers")"
[[ -n "${KOOMPI_FAKE_COPY:-}" ]] && cp "$answers" "$KOOMPI_FAKE_COPY"
disk="$(sed -n 's/.*"disk": "\(.*\)",/\1/p' "$answers")"
user="$(sed -n 's/.*"username": "\(.*\)",/\1/p' "$answers")"
rm -f "$answers"
echo "fake-engine: answers file mode $mode, disk $disk, user $user"

delay="${KOOMPI_FAKE_DELAY:-1}"
fail="${KOOMPI_FAKE_FAIL:-0}"
steps=("Preparing the disk" "Installing the base system" "Setting up the account" "Installing the boot loader")
total=${#steps[@]}
for i in "${!steps[@]}"; do
    n=$((i + 1))
    echo "@@koompi step $n/$total ${steps[$i]}"
    for j in 1 2 3; do
        echo "fake: ${steps[$i],,} ($j/3)"
        sleep "$(awk "BEGIN { print $delay / 3 }")"
    done
    if (( n == fail )); then
        echo "error: something broke in step $n" >&2
        echo "@@koompi fail ${steps[$i]} failed (fake)"
        exit 1
    fi
done
echo "@@koompi done"
