#!/usr/bin/env bash
# Guards: a user unit that ships from dots/ is enabled only after the files step.
# run_setups runs before install_files, so on a first install the unit file is not
# in ~/.config/systemd/user yet and `systemctl --user enable` fails - under --yes
# that aborted every fresh install (litert-lm.socket, at the ISO's first boot).
# Such enables belong in setup_services, or a function only it calls.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

units=()
for f in "$ROOT"/dots/.config/systemd/user/*.service "$ROOT"/dots/.config/systemd/user/*.socket \
         "$ROOT"/dots/.config/systemd/user/*.timer; do
    [[ -e "$f" ]] && units+=("$(basename "$f")")
done
(( ${#units[@]} )) || fail "no user units under dots/.config/systemd/user; the test lost its subject"

# The functions setup_services calls, itself included.
services_body="$(sed -n '/^setup_services() {/,/^}/p' "$ROOT"/sdata/install/setups/*.sh)"
[[ -n "$services_body" ]] || fail "setup_services is gone"
allowed=(setup_services)
mapfile -t -O 1 allowed < <(grep -oE '^\s+setup_[a-z_]+\s*$' <<<"$services_body" | tr -d ' ')

checked=0
for file in "$ROOT"/sdata/install/setups/*.sh; do
    fn=''
    while IFS= read -r line; do
        if [[ "$line" =~ ^([a-z_]+)\(\)\ \{ ]]; then fn="${BASH_REMATCH[1]}"; continue; fi
        [[ "$line" =~ systemctl\ --user\ enable ]] || continue
        for u in "${units[@]}"; do
            name="${u%.service}"
            [[ "$line" =~ [[:space:]]($u|$name)([[:space:]]|$) ]] || continue
            checked=$((checked + 1))
            printf '%s\n' "${allowed[@]}" | grep -qxF "$fn" ||
                fail "${file#"$ROOT"/}: $fn enables $u, which ships from dots/; enable it from setup_services (after the files step)"
        done
    done < "$file"
done
(( checked > 0 )) || fail "found no enable of a dots/ user unit at all; the pattern no longer matches the setups"
printf 'user units after files test passed (%d enables checked)\n' "$checked"
