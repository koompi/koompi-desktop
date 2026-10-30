# shellcheck shell=bash
# light_tile_cut SRC OUT: when SRC is a logo laid on a flat light tile (Antigravity's white squircle, a web app's
# white disc), write the logo alone to OUT, 128 px, and return 0. Anything else returns 1 and writes nothing: a
# dark tile (its logo was drawn for the dark), a full-bleed picture, a plain shape, and a logo that would
# vanish on the bar's dark glass once its white ground is gone (Xournal++'s black x). Needs ImageMagick 7.
light_tile_cut() {
    local src=$1 out=$2 tmp box w h x y
    tmp=$(mktemp -d) || return 1
    # the tile's body: its opaque area, eroded past the anti-aliased rim and the drop shadow
    box=$(magick -background none "$src" -resize 128x128 -gravity center -extent 128x128 -write "PNG32:$tmp/in.png" \
        -alpha extract -threshold 50% -morphology Erode Disk:4 -write "$tmp/body.png" -format '%@' info: 2> /dev/null)
    if [[ ! $box =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then rm -rf "$tmp"; return 1; fi
    w=${BASH_REMATCH[1]} h=${BASH_REMATCH[2]} x=${BASH_REMATCH[3]} y=${BASH_REMATCH[4]}
    if (( w < 80 || h < 80 )); then rm -rf "$tmp"; return 1; fi

    # a short band just inside each edge of the body, short enough to sit inside a disc: opaque, light and flat
    local verdicts
    verdicts=$(magick "$tmp/in.png" \
        \( -clone 0 -crop "$((w / 6))x4+$((x + 5 * w / 12))+$((y + 4))" \) \
        \( -clone 0 -crop "$((w / 6))x4+$((x + 5 * w / 12))+$((y + h - 8))" \) \
        \( -clone 0 -crop "4x$((h / 6))+$((x + 4))+$((y + 5 * h / 12))" \) \
        \( -clone 0 -crop "4x$((h / 6))+$((x + w - 8))+$((y + 5 * h / 12))" \) -delete 0 +repage \
        -format '%[fx:minima.a >= 0.98 && mean.r*0.2126 + mean.g*0.7152 + mean.b*0.0722 >= 0.85 && standard_deviation <= 0.06]\n' info: 2> /dev/null)
    if [[ $verdicts != $'1\n1\n1\n1' ]]; then rm -rf "$tmp"; return 1; fi

    # keep the body only, clear the light ground from each edge inward, and frame what is left
    if ! magick "$tmp/in.png" \( "$tmp/in.png" -alpha extract "$tmp/body.png" -compose Multiply -composite \) \
        -alpha off -compose CopyOpacity -composite -compose Over -fuzz 14% -fill none \
        -draw "alpha $((x + w / 2)),$((y + 6)) floodfill" -draw "alpha $((x + w / 2)),$((y + h - 7)) floodfill" \
        -draw "alpha $((x + 6)),$((y + h / 2)) floodfill" -draw "alpha $((x + w - 7)),$((y + h / 2)) floodfill" \
        -trim +repage -resize 116x116 -gravity center -background none -extent 128x128 "PNG32:$tmp/out.png" 2> /dev/null; then
        rm -rf "$tmp"; return 1
    fi

    # near-black, colourless pixels disappear on the dark bar: past 15 % of the logo, the tile stays
    local dark opaque
    dark=$(magick "$tmp/out.png" -fx 'u.a > 0.5 && lightness < 0.25 && saturation < 0.25' -alpha off -format '%[fx:mean]' info: 2> /dev/null)
    opaque=$(magick "$tmp/out.png" -alpha extract -threshold 50% -format '%[fx:mean]' info: 2> /dev/null)
    if ! awk -v d="$dark" -v o="$opaque" 'BEGIN { exit !(d != "" && o > 0.02 && d / o <= 0.15) }'; then
        rm -rf "$tmp"; return 1
    fi
    mv -f "$tmp/out.png" "$out"
    rm -rf "$tmp"
}
