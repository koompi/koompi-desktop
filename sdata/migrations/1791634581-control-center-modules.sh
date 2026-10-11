# shellcheck shell=bash
# the Control Center's optional modules start from what the user kept in the old toggle grid; the types it always shows (and the one-shot captures, which are Search commands now) are dropped
config="${XDG_CONFIG_HOME:-$HOME/.config}/koompi/config.json"
backups="${KOOMPI_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/koompi}/backups"
[[ -f "$config" ]] || exit 0
command -v jq > /dev/null 2>&1 || { echo "jq is not installed; the Control Center's optional modules were not seeded"; exit 0; }
jq -e . "$config" > /dev/null 2>&1 || exit 0
jq -e '.controlCenter.extraModules != null' "$config" > /dev/null 2>&1 && exit 0

# keep in step with CcExtras.types in modules/koompi/controlCenter/CcExtras.qml
seeded="$(jq -c '
    ["screenRecord", "gameMode", "powerProfile", "easyEffects", "cloudflareWarp", "antiFlashbang", "mic"] as $modules
    | [.sidebar.quickToggles.android.toggles // [] | .[].type | select(. as $t | $modules | index($t))]
    | reduce .[] as $t ([]; if index($t) then . else . + [$t] end)
' "$config")"
[[ "$seeded" != "[]" ]] || exit 0

tmp="$(mktemp -- "$config.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT
jq --argjson modules "$seeded" '.controlCenter.extraModules = $modules' "$config" > "$tmp"
mkdir -p -- "$backups"
cp -a -- "$config" "$backups/migrate-$(date +%Y%m%d-%H%M%S)-config_koompi_config.json"
cat "$tmp" > "$config"
echo "Control Center: optional modules seeded from your quick toggles: $(jq -r 'join(", ")' <<< "$seeded")"
