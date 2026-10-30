#!/usr/bin/env bash

# Random wallpaper of art about Cambodia. With a Pixabay key it is digital art:
# illustrations and vector work of Angkor, Khmer temples and landscapes, free to
# use without credit. Without one, or when Pixabay has nothing, it falls back to
# Wikimedia Commons, which needs no key but is nearly all photography.
#
# Usage: random_cambodia_wall.sh [workspace-id] [--notify]
# The workspace id pins where the image lands, as random_wall.sh does. --notify
# reports a failure on the desktop: a keybind has no other way to say "offline".
# random_wall.sh does not pass it, since it falls back to another source.
#
# The key is apiKeys.pixabay in the KOOMPI keyring (Settings > Services), or
# PIXABAY_API_KEY in the environment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/koompi"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/koompi/pixabay"
COMMONS_API="${KOOMPI_COMMONS_API:-https://commons.wikimedia.org/w/api.php}"
PIXABAY_API="${KOOMPI_PIXABAY_API:-https://pixabay.com/api/}"
# Wikimedia asks for a UA that names the client; the browser string in
# .networking.userAgent is exactly what its policy rejects.
UA="KOOMPI-Desktop (https://github.com/koompi/koompi-desktop) wallpaper"

notify=0
for arg in "$@"; do
    case "$arg" in
        --notify) notify=1 ;;
        0) ;;
        *[!0-9]*) ;;
        *) export KOOMPI_TARGET_WORKSPACE="$arg" ;;
    esac
done

toast() {
    [ "$notify" = 1 ] && command -v notify-send >/dev/null 2>&1 \
        && notify-send -a "Wallpaper" -i "image-x-generic" "$1" "$2"
}

fail() {
    echo "random_cambodia_wall: $*" >&2
    toast "No Cambodian art this time" "$*"
    exit 1
}

get_pictures_dir() {
    if command -v xdg-user-dir >/dev/null 2>&1; then
        xdg-user-dir PICTURES
        return
    fi
    echo "$HOME/Pictures"
}

# Inside ~/Pictures/Wallpapers, so the offline library source picks up every
# download and the collection keeps working without a network.
save_dir="$(get_pictures_dir)/Wallpapers/Cambodia"
mkdir -p "$save_dir" || fail "cannot create $save_dir"

pixabay_key() {
    if [ -n "${PIXABAY_API_KEY:-}" ]; then
        printf '%s' "$PIXABAY_API_KEY"
        return
    fi
    command -v secret-tool >/dev/null 2>&1 || return 0
    secret-tool lookup application koompi 2>/dev/null | jq -r '.apiKeys.pixabay // empty' 2>/dev/null
}

# Every candidate, from either source, is one JSON line with the same fields:
# name (becomes the file name), url, page, license, artist.

# Terms name Cambodia itself: "temple" or "mekong" alone brings back Thailand,
# Laos and Bali. Illustration and vector only; photos are what Commons is for.
pixabay_terms=(
    "angkor wat" "angkor" "cambodia" "khmer" "apsara" "bayon" "siem reap"
    "phnom penh" "cambodian temple" "tonle sap"
)
pixabay_types=(illustration vector)
pixabay_status=""

# Pixabay asks clients to cache each search for 24 hours, and it is faster: a
# re-roll on a cached search costs only the image download.
pixabay_candidates() {
    local key="$1" term="$2" type="$3" cache response code
    mkdir -p "$CACHE_DIR" || return 1
    cache="$CACHE_DIR/$(printf '%s-%s' "$term" "$type" | tr -c 'A-Za-z0-9-' '_').json"
    if [ -z "$(find "$cache" -mmin -1440 2>/dev/null)" ]; then
        response="$(mktemp -- "$cache.XXXXXX")" || return 1
        # The key goes through curl's stdin config, not argv, so ps never shows it.
        code="$(printf 'url = "%s?key=%s&q=%s&image_type=%s&orientation=horizontal&safesearch=true&order=popular&per_page=200"\n' \
                "$PIXABAY_API" "$key" "$(jq -rn --arg t "$term" '$t|@uri')" "$type" \
            | curl -sS --max-time 20 -A "$UA" -K - -o "$response" -w '%{http_code}')"
        if [ "$code" != 200 ] || ! jq -e '.hits' "$response" >/dev/null 2>&1; then
            pixabay_status="$code"
            rm -f "$response"
            return 1
        fi
        mv -f "$response" "$cache"
    fi
    # Full HD and original files come only with Pixabay's full API access, which
    # an account asks for once; until then largeImageURL is 1280 px wide.
    jq -c '
        .hits[]? | select(.imageWidth * 3 >= .imageHeight * 4)
        | {
            name: "pixabay-\(.id)-\(.tags | split(", ")[0:3] | join(" "))",
            url: (.imageURL // .fullHDURL // .largeImageURL),
            page: .pageURL,
            license: "Pixabay Content License",
            artist: (.user // "unknown")
          }' "$cache"
}

# Commons: reviewed photographs of Angkor weighted double, then sculpture,
# reliefs and dance. "Quality images of Cambodia" as a whole was tried and
# dropped: it also holds power plants. The negative terms keep the genocide
# memorials out; they belong in a museum, not behind a desktop.
commons_pools=(
    'deepcat:"Quality images of Angkor"'
    'deepcat:"Quality images of Angkor"'
    'deepcat:"Featured pictures of Cambodia"'
    'deepcat:"Khmer sculpture"'
    'deepcat:"Bas-reliefs in Cambodia"'
    'deepcat:"Dance of Cambodia"'
    'deepcat:"Art of Cambodia"'
)
commons_filters='filetype:bitmap filew:>1919 -"Tuol Sleng" -"Choeung Ek" -"Killing Fields" -skull -genocide'

# A random page of matches, landscape and at least 1920 wide. The 3840px
# thumbnail is plenty for a 4K screen and keeps a 60-megapixel original from
# costing a minute on a slow line.
commons_candidates() {
    curl -fsS --max-time 20 -G -A "$UA" "$COMMONS_API" \
        --data-urlencode "action=query" \
        --data-urlencode "format=json" \
        --data-urlencode "formatversion=2" \
        --data-urlencode "generator=search" \
        --data-urlencode "gsrnamespace=6" \
        --data-urlencode "gsrlimit=30" \
        --data-urlencode "gsrsort=random" \
        --data-urlencode "gsrsearch=$1 $commons_filters" \
        --data-urlencode "prop=imageinfo" \
        --data-urlencode "iiprop=url|size|mime|extmetadata" \
        --data-urlencode "iiurlwidth=3840" \
        --data-urlencode "iiextmetadatafilter=Artist|LicenseShortName" \
    | jq -c '
        .query.pages[]? | .imageinfo[0]? as $i | select($i != null)
        | select($i.width >= 1920 and $i.width * 3 >= $i.height * 4)
        | select($i.mime == "image/jpeg" or $i.mime == "image/png")
        | {
            name: (.title | sub("^File:"; "") | sub("\\.[A-Za-z0-9]+$"; "")),
            url: ($i.thumburl // $i.url),
            page: $i.descriptionurl,
            license: ($i.extmetadata.LicenseShortName.value // "see page"),
            artist: (($i.extmetadata.Artist.value // "unknown") | gsub("<[^>]*>"; "") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" "))
          }'
}

# Made safe and short, so a picture already downloaded is recognised and a
# re-roll never overwrites a file another workspace points at. LC_ALL=C makes
# the class ASCII: in a UTF-8 locale "Tańca" kept its ń.
local_name() {
    local base
    base="$(printf '%s' "$1" | LC_ALL=C sed -E 's/[^A-Za-z0-9._-]+/_/g; s/^_+|_+$//g' | cut -c1-120)"
    printf '%s.%s' "$base" "$2"
}

ext_of() {
    case "$1" in *.png*|*.PNG*) echo png ;; *) echo jpg ;; esac
}

key="$(pixabay_key)"
if [ -z "$key" ]; then
    echo "random_cambodia_wall: no Pixabay key, using Wikimedia Commons photos" >&2
    # Once, not on every keypress: the photos are a fine answer, only not the art.
    hint="$STATE_DIR/cambodia-wallpaper-key-hint"
    if [ "$notify" = 1 ] && [ ! -e "$hint" ]; then
        toast "Photos for now" "Add a free Pixabay API key in Settings > Services for Cambodian digital art."
        mkdir -p "$STATE_DIR" && touch "$hint"
    fi
fi

for attempt in 1 2 3 4; do
    found=()
    source_label=""
    if [ -n "$key" ]; then
        term="${pixabay_terms[RANDOM % ${#pixabay_terms[@]}]}"
        type="${pixabay_types[RANDOM % ${#pixabay_types[@]}]}"
        pixabay_status=""
        # Not a process substitution: pixabay_status has to survive the call.
        mkdir -p "$CACHE_DIR"
        pixabay_candidates "$key" "$term" "$type" > "$CACHE_DIR/candidates.$$" 2>/dev/null
        mapfile -t found < "$CACHE_DIR/candidates.$$"
        rm -f "$CACHE_DIR/candidates.$$"
        source_label="Pixabay $type '$term'"
        # A rejected key fails every term the same way; stop asking.
        case "$pixabay_status" in
            400|401|403) fail "Pixabay rejected the API key (HTTP $pixabay_status). Check it in Settings > Services." ;;
        esac
    fi
    # Commons when there is no key, or as the last try when Pixabay keeps coming
    # back empty, so a keypress still changes the wallpaper.
    if [ "${#found[@]}" -eq 0 ] && { [ -z "$key" ] || [ "$attempt" = 4 ]; }; then
        pool="${commons_pools[RANDOM % ${#commons_pools[@]}]}"
        mapfile -t found < <(commons_candidates "$pool")
        source_label="Commons $pool"
    fi
    if [ "${#found[@]}" -eq 0 ]; then
        echo "random_cambodia_wall: nothing usable from $source_label (attempt $attempt)" >&2
        continue
    fi

    # Prefer something new; a picture already in the folder is still better
    # than a dead keypress.
    fresh=()
    for c in "${found[@]}"; do
        name="$(jq -r .name <<< "$c")"
        [ -e "$save_dir/$(local_name "$name" "$(ext_of "$(jq -r .url <<< "$c")")")" ] || fresh+=("$c")
    done
    [ "${#fresh[@]}" -gt 0 ] && found=("${fresh[@]}")

    pick="${found[RANDOM % ${#found[@]}]}"
    url="$(jq -r .url <<< "$pick")"
    target="$save_dir/$(local_name "$(jq -r .name <<< "$pick")" "$(ext_of "$url")")"

    if [ ! -s "$target" ]; then
        # Beside the target, so the final mv is a rename and a half-written file
        # is never what a workspace points at.
        part="$(mktemp -- "$target.XXXXXX.part")" || fail "cannot write to $save_dir"
        if ! curl -fsS --max-time 90 -A "$UA" "$url" -o "$part" \
            || ! file -b --mime-type "$part" | grep -q '^image/'; then
            rm -f "$part"
            echo "random_cambodia_wall: download failed for $url (attempt $attempt)" >&2
            continue
        fi
        # mktemp made it 0600; a wallpaper is as readable as the rest of ~/Pictures
        chmod 644 "$part"
        mv -f "$part" "$target"
        # Commons is mostly CC BY or BY-SA: the credit stays with the picture.
        # Pixabay asks for none, but where a picture came from is worth keeping.
        printf '%s\t%s\t%s\t%s\n' "$(basename "$target")" \
            "$(jq -r .artist <<< "$pick")" "$(jq -r .license <<< "$pick")" \
            "$(jq -r .page <<< "$pick")" >> "$save_dir/CREDITS.tsv"
    fi

    printf '%s\n' "$target"
    "$SCRIPT_DIR/../apply_wall.sh" "$target"
    exit $?
done

fail "no source could be reached, or none returned anything usable"
