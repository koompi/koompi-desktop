#!/usr/bin/env bash
# write_litert_lm_config must size itself to the machine it runs on, not to the
# 8-core Arc laptop it was first written on.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

info() { :; }; ok() { :; }; manifest_add() { :; }
DRY_RUN=false

# shellcheck source=sdata/install/setups/ai.sh
source "$REPO_ROOT/sdata/install/setups/ai.sh"

mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho 2\n' > "$tmp/bin/nproc"
chmod +x "$tmp/bin/nproc"
PATH="$tmp/bin:$PATH"
HOME="$tmp/home"
mkdir -p "$HOME"

write_litert_lm_config
config="$HOME/.litert-lm/config.json"
[[ -s "$config" ]] || fail 'no config written'
jq -e 'type == "object"' "$config" >/dev/null || fail 'config is not a JSON object'

threads="$(jq -r '.default.cpu_thread_count' "$config")"
[[ "$threads" == 2 ]] || fail "cpu_thread_count is $threads on a 2-core machine"

want=cpu
compgen -G '/dev/dri/renderD*' >/dev/null && want=gpu
backend="$(jq -r '.default.backend' "$config")"
[[ "$backend" == "$want" ]] || fail "backend is $backend, this machine wants $want"

printf 'ok: %s, %s threads\n' "$backend" "$threads"
