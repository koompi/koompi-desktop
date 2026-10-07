#!/usr/bin/env bash
# update news off in nested configs: a retried start runs hyprland-update-screen, which segfaults and toasts the live seat
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
self="$(basename -- "${BASH_SOURCE[0]}")"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

offenders=""
for f in "$ROOT"/tests/*.sh; do
    [[ "$(basename -- "$f")" == "$self" ]] && continue
    grep -qE '(^|[^-[:alnum:]_/])Hyprland[[:space:]]+(-c|--config)[[:space:]]' "$f" || continue
    grep -q 'no_update_news = true' "$f" || offenders+="${f#"$ROOT"/}"$'\n'
done
[[ -z "$offenders" ]] || fail "a nested Hyprland that can open update news (set ecosystem.no_update_news in its config):
$offenders"
echo "ok   static: every nested Hyprland in tests/ has update news off"
