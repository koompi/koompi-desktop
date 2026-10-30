#!/usr/bin/env bash
# random_cambodia_wall.sh downloads art about Cambodia: Pixabay illustrations
# when a key is set, Wikimedia Commons otherwise. Run offline against canned API
# answers: curl, secret-tool, xdg-user-dir, notify-send and apply_wall.sh are
# stubs, so nothing is fetched, the real keyring is never read and no wallpaper
# changes. Also checks that the keybinds reach the shortcut the shell declares.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SCRIPT="$SHELL_ROOT/scripts/colors/random/random_cambodia_wall.sh"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -x "$SCRIPT" ]] || fail "missing or not executable: ${SCRIPT#"$REPO_ROOT"/}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tree/colors/random" "$tmp/bin" "$tmp/home"
cp "$SCRIPT" "$tmp/tree/colors/random/"
script="$tmp/tree/colors/random/random_cambodia_wall.sh"
saved="$tmp/home/Pictures/Wallpapers/Cambodia"

cat > "$tmp/tree/colors/apply_wall.sh" <<STUB
#!/usr/bin/env bash
printf '%s\t%s\n' "\${KOOMPI_TARGET_WORKSPACE:-}" "\$1" >> "$tmp/applied"
STUB
chmod +x "$tmp/tree/colors/apply_wall.sh"

# file(1) wants a whole image, so a 1x1 PNG stands in for the download.
base64 -d > "$tmp/image.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==
PNG

# One usable candidate among three: a portrait and a too-small one must lose.
cat > "$tmp/commons.json" <<'JSON'
{"query":{"pages":[
 {"title":"File:Tall Apsara.jpg","imageinfo":[{"width":2000,"height":3000,"mime":"image/jpeg",
  "thumburl":"https://upload.example/tall.jpg","descriptionurl":"https://commons.example/tall"}]},
 {"title":"File:Small Bayon.jpg","imageinfo":[{"width":1024,"height":600,"mime":"image/jpeg",
  "thumburl":"https://upload.example/small.jpg","descriptionurl":"https://commons.example/small"}]},
 {"title":"File:Angkor Wat, sunrise (01) Tańca.JPG","imageinfo":[{"width":5000,"height":3000,"mime":"image/jpeg",
  "thumburl":"https://upload.example/3840px-Angkor.JPG","descriptionurl":"https://commons.example/angkor",
  "extmetadata":{"Artist":{"value":"<a href=\"x\">Sok Dara</a>"},"LicenseShortName":{"value":"CC BY-SA 4.0"}}}]}
]}}
JSON

# Free-tier hits: largeImageURL only. The square one must lose.
cat > "$tmp/pixabay.json" <<'JSON'
{"total":2,"totalHits":2,"hits":[
 {"id":111,"pageURL":"https://pixabay.example/square-111/","tags":"lotus, square","imageWidth":3000,"imageHeight":3000,
  "largeImageURL":"https://pixabay.example/get/square_1280.jpg","user":"someone"},
 {"id":222,"pageURL":"https://pixabay.example/angkor-222/","tags":"angkor wat, temple, sunset, cambodia","imageWidth":6000,"imageHeight":3375,
  "largeImageURL":"https://pixabay.example/get/angkor_1280.png","user":"dara_art"}
]}
JSON

# curl as the script calls it: -K - carries the Pixabay URL on stdin, -w asks
# for the status code, -o names the file. Anything else is a Commons search.
cat > "$tmp/bin/curl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/curl.calls"
[[ -e "$tmp/offline" ]] && exit 6
out="" config=0 wcode=0
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o) out="\$2"; shift ;;
        -K) config=1; shift ;;
        -w) wcode=1; shift ;;
    esac
    shift
done
if (( config )); then
    cat >> "$tmp/pixabay.calls"
    code="\$(cat "$tmp/pixabay_code" 2>/dev/null || echo 200)"
    if [[ \$code == 200 ]]; then cp "$tmp/pixabay.json" "\$out"; else echo "[ERROR \$code] Invalid key" > "\$out"; fi
    (( wcode )) && printf '%s' "\$code"
    exit 0
fi
if [[ -n "\$out" ]]; then cp "$tmp/image.png" "\$out"; else cat "$tmp/commons.json"; fi
STUB
# The keyring holds no Pixabay key unless a run puts one in the environment.
printf '#!/bin/sh\necho "{\\"apiKeys\\":{\\"gemini\\":\\"g\\"}}"\n' > "$tmp/bin/secret-tool"
printf '#!/bin/sh\necho "%s/Pictures"\n' "$tmp/home" > "$tmp/bin/xdg-user-dir"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/notified"\n' "$tmp" > "$tmp/bin/notify-send"
chmod +x "$tmp/bin/"*

run() {
    HOME="$tmp/home" XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" PATH="$tmp/bin:$PATH" \
        "$script" "$@" > "$tmp/out" 2>&1
}
reset() { rm -rf "$saved" "$tmp/cache" "$tmp/state" "$tmp/applied" "$tmp/notified" "$tmp/curl.calls" "$tmp/pixabay.calls"; }

# --- no key: Commons ----------------------------------------------------------
run 4
status=$?
(( status == 0 )) || fail "exited $status: $(cat "$tmp/out")"

want="$saved/Angkor_Wat_sunrise_01_Ta_ca.jpg"
[[ -s "$want" ]] || fail "the landscape candidate was not saved as $want: $(ls -R "$tmp/home")"
[[ "$(cat "$tmp/applied")" == "4	$want" ]] ||
    fail "apply_wall.sh got '$(cat "$tmp/applied")', want workspace 4 and $want"
[[ "$(stat -c %a "$want")" == 644 ]] || fail "saved image is mode $(stat -c %a "$want"), want 644"
grep -q 'tall\|small' "$tmp/curl.calls" && fail "downloaded a portrait or undersized image"
[[ -e "$tmp/pixabay.calls" ]] && fail "asked Pixabay without a key"
compgen -G "$saved/*.part" > /dev/null && fail "left a .part file behind"
[[ "$(cat "$saved/CREDITS.tsv")" == \
    "Angkor_Wat_sunrise_01_Ta_ca.jpg	Sok Dara	CC BY-SA 4.0	https://commons.example/angkor" ]] ||
    fail "credit line wrong: $(cat "$saved/CREDITS.tsv")"
# Wikimedia's UA policy rejects the browser string config.json carries.
grep -q -- '-A KOOMPI-Desktop' "$tmp/curl.calls" || fail "requests do not identify as KOOMPI-Desktop"
[[ -e "$tmp/notified" ]] && fail "the no-key hint toasted without --notify"

# A picture already in the folder is reused, not fetched again or credited twice.
: > "$tmp/curl.calls"
run || fail "second run failed: $(cat "$tmp/out")"
grep -q 'upload.example' "$tmp/curl.calls" && fail "re-downloaded an image already saved"
(( $(wc -l < "$saved/CREDITS.tsv") == 1 )) || fail "credited one picture twice"

# The keybind says once that a key would bring the art, then stays quiet.
run 1 --notify || fail "--notify run without a key failed: $(cat "$tmp/out")"
grep -q 'Pixabay API key' "$tmp/notified" 2>/dev/null || fail "no hint that a Pixabay key brings digital art"
run 1 --notify
(( $(grep -c 'Pixabay API key' "$tmp/notified") == 1 )) || fail "the key hint repeated on a second keypress"

# Offline: a non-zero exit so random_wall.sh tries another source, silent unless
# --notify asks, and nothing applied.
touch "$tmp/offline"
: > "$tmp/applied"
rm -f "$tmp/notified"
run && fail "offline run reported success"
[[ -s "$tmp/applied" ]] && fail "offline run applied a wallpaper"
[[ -e "$tmp/notified" ]] && fail "notified without --notify; random_wall.sh would toast before falling back"
run 2 --notify && fail "offline --notify run reported success"
[[ -s "$tmp/notified" ]] || fail "--notify did not report the failure on the desktop"
rm -f "$tmp/offline"
echo "ok   commons: landscape pick saved, credited, applied to its workspace; reused; hint once; offline fails loud only with --notify"

# --- with a key: Pixabay ------------------------------------------------------
reset
export PIXABAY_API_KEY=test-key-123
run 3 || fail "Pixabay run failed: $(cat "$tmp/out")"
want="$saved/pixabay-222-angkor_wat_temple_sunset.png"
[[ -s "$want" ]] || fail "the wide Pixabay hit was not saved as $want: $(ls "$saved")"
[[ "$(cat "$tmp/applied")" == "3	$want" ]] || fail "apply_wall.sh got '$(cat "$tmp/applied")', want workspace 3 and $want"
grep -q 'square_1280' "$tmp/curl.calls" && fail "downloaded the square Pixabay hit"
grep -q 'key=test-key-123&q=' "$tmp/pixabay.calls" || fail "the key did not reach Pixabay: $(cat "$tmp/pixabay.calls")"
grep -q 'image_type=\(illustration\|vector\)' "$tmp/pixabay.calls" || fail "asked Pixabay for photos, not art"
grep -q 'test-key-123' "$tmp/curl.calls" && fail "the API key was on curl's argv, where ps shows it"
grep -q 'upload.example' "$tmp/curl.calls" && fail "used Commons although Pixabay had art"
[[ "$(cat "$saved/CREDITS.tsv")" == \
    "pixabay-222-angkor_wat_temple_sunset.png	dara_art	Pixabay Content License	https://pixabay.example/angkor-222/" ]] ||
    fail "Pixabay credit line wrong: $(cat "$saved/CREDITS.tsv")"
compgen -G "$tmp/cache/koompi/pixabay/*.json" > /dev/null || fail "the Pixabay search was not cached"

# Pixabay asks for 24 hours of caching: the same search is not asked again.
term_cache="$(compgen -G "$tmp/cache/koompi/pixabay/*.json" | head -1)"
for f in angkor_wat angkor cambodia khmer apsara bayon siem_reap phnom_penh cambodian_temple tonle_sap; do
    for t in illustration vector; do
        [[ "$tmp/cache/koompi/pixabay/$f-$t.json" == "$term_cache" ]] || cp "$term_cache" "$tmp/cache/koompi/pixabay/$f-$t.json"
    done
done
rm -f "$tmp/pixabay.calls"
run || fail "cached run failed: $(cat "$tmp/out")"
[[ -e "$tmp/pixabay.calls" ]] && fail "asked Pixabay again inside the 24-hour cache"

# A rejected key stops at once and says which setting to fix.
reset
echo 400 > "$tmp/pixabay_code"
run 1 --notify && fail "a rejected key reported success"
grep -q 'rejected the API key' "$tmp/notified" 2>/dev/null || fail "a rejected key was not reported: $(cat "$tmp/out")"
(( $(grep -c 'key=' "$tmp/pixabay.calls") == 1 )) || fail "kept asking Pixabay with a rejected key"
[[ -s "$tmp/applied" ]] && fail "a rejected key still applied something"
rm -f "$tmp/pixabay_code"

# Pixabay up but with nothing wide: the last try falls back to Commons.
reset
jq '.hits |= map(select(.id == 111))' "$tmp/pixabay.json" > "$tmp/p.json" && mv "$tmp/p.json" "$tmp/pixabay.json"
run || fail "fallback run failed: $(cat "$tmp/out")"
[[ -s "$saved/Angkor_Wat_sunrise_01_Ta_ca.jpg" ]] || fail "an empty Pixabay did not fall back to Commons"
unset PIXABAY_API_KEY
echo "ok   pixabay: wide art saved and credited, key off argv, searches cached, rejected key stops, empty falls back to Commons"

# random_wall.sh only offers sources named random_<name>_wall.sh beside it.
[[ "$(basename "$SCRIPT")" == random_cambodia_wall.sh ]] || fail "renamed out of random_wall.sh's source pattern"

# The keybinds call shortcuts the shell actually declares.
KEYBINDS="$REPO_ROOT/dots/.config/hypr/hyprland/keybinds_shell_extra.lua"
SELECTOR="$SHELL_ROOT/modules/koompi/wallpaperSelector/WallpaperSelector.qml"
for name in wallpaperSelectorRandom wallpaperRandomCambodia; do
    grep -q "quickshell:$name\"" "$KEYBINDS" || fail "no keybind for quickshell:$name"
    grep -q "name: \"$name\"" "$SELECTOR" || fail "keybinds.lua calls $name but the shell does not declare it"
done
awk '/name: "wallpaperRandomCambodia"/,/^    }/' "$SELECTOR" | grep -q 'random_cambodia_wall.sh' ||
    fail "the wallpaperRandomCambodia shortcut does not run random_cambodia_wall.sh"

# The key field writes the keyring only once it has been read, or a save would
# replace every other stored key with this one.
SERVICES="$SHELL_ROOT/modules/settings/ServicesConfig.qml"
grep -q '"apiKeys", "pixabay"' "$SERVICES" || fail "Settings > Services has no Pixabay key field"
grep -q 'enabled: KeyringStorage.loaded' "$SERVICES" || fail "the Pixabay key field can save before the keyring is loaded"
echo "ok   wiring: keybinds reach the shell's shortcut; the key field waits for the keyring"
