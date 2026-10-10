#!/usr/bin/env bash
# J20: the Control Center's optional modules (controlCenter.extraModules) are seeded once from the user's
# stored quick-toggle grid. A user who added Game mode keeps seeing it; the types the Control Center always
# shows and the one-shot captures (screen snip, colour picker...) do not come across.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v jq > /dev/null || { echo "skip: jq not installed"; exit 0; }

shopt -s nullglob
found=("$ROOT"/sdata/migrations/*-control-center-modules.sh)
[[ ${#found[@]} -eq 1 ]] || fail "expected one control-center-modules migration, found ${#found[@]}"
MIG="${found[0]}"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

run() { # $1: home name, $2: config.json text ("" for none)
    local home="$TEST_ROOT/$1"
    mkdir -p "$home/.config/koompi"
    [[ -z "$2" ]] || printf '%s' "$2" > "$home/.config/koompi/config.json"
    HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" KOOMPI_STATE_DIR="" \
        bash -euo pipefail "$MIG" > "$home/out" 2>&1 || { cat "$home/out" >&2; fail "the migration exited non-zero for $1"; }
    printf '%s\n' "$home/.config/koompi/config.json"
}
modules() { jq -c '.controlCenter.extraModules // "unset"' "$1"; }

old='{"configVersion":1,"sidebar":{"quickToggles":{"android":{"toggles":[
 {"size":2,"type":"network"},{"size":2,"type":"gameMode"},{"size":2,"type":"screenSnip"},
 {"size":1,"type":"idleInhibitor"},{"size":2,"type":"colorPicker"},{"size":2,"type":"gameMode"}]}}}}'

cfg="$(run seeded "$old")"
[[ "$(modules "$cfg")" == '["gameMode"]' ]] || fail "wanted Game mode only, got $(modules "$cfg")"
[[ "$(jq -r .configVersion "$cfg")" == 1 ]] || fail "an unrelated key was lost"
[[ "$(jq '.sidebar.quickToggles.android.toggles | length' "$cfg")" == 6 ]] || fail "the old grid was touched"
compgen -G "$TEST_ROOT/seeded/.local/state/koompi/backups/*" > /dev/null || fail "no backup of config.json was written"

before="$(cat "$cfg")"
cfg="$(run seeded "$before")"
[[ "$(cat "$cfg")" == "$before" ]] || fail "a second run changed the config"

mine='{"controlCenter":{"extraModules":["easyEffects"]},"sidebar":{"quickToggles":{"android":{"toggles":[{"size":2,"type":"gameMode"}]}}}}'
cfg="$(run chosen "$mine")"
[[ "$(modules "$cfg")" == '["easyEffects"]' ]] || fail "a list the user already has was overwritten: $(modules "$cfg")"

cfg="$(run onlyfixed '{"sidebar":{"quickToggles":{"android":{"toggles":[{"size":2,"type":"network"},{"size":2,"type":"screenSnip"}]}}}}')"
[[ "$(modules "$cfg")" == '"unset"' ]] || fail "nothing to seed, yet the key was written: $(modules "$cfg")"

run nofile "" > /dev/null
[[ ! -e "$TEST_ROOT/nofile/.config/koompi/config.json" ]] || fail "a config was created out of nothing"
cfg="$(run broken 'not json')"
[[ "$(cat "$cfg")" == "not json" ]] || fail "invalid JSON was not left alone"

mapfile -t catalog < <(sed -n '/readonly property var types: \[/p' "$ROOT/dots/.config/quickshell/koompi/modules/koompi/controlCenter/CcExtras.qml" | grep -o '"[A-Za-z]*"' | tr -d '"')
(( ${#catalog[@]} > 0 )) || fail "could not read CcExtras.types"
for t in "${catalog[@]}"; do
    cfg="$(run "type_$t" "{\"sidebar\":{\"quickToggles\":{\"android\":{\"toggles\":[{\"size\":2,\"type\":\"$t\"}]}}}}")"
    [[ "$(modules "$cfg")" == "[\"$t\"]" ]] || fail "$t is in CcExtras.types but the migration does not carry it"
done
echo "ok   migration: seeds the optional modules from the stored grid, once, leaving the rest"
