#!/usr/bin/env bash
# AppIconBodies.qml: the icon each app ships itself, "name<TAB>path" per line. A bare icon (the bar) draws this in
# place of the active theme's full-bleed tile: first the app's own (hicolor, pixmaps), then the flat icon of a theme
# the active one inherits from (breeze), best file per name: scalable, then the largest SVG design, then the
# smallest PNG of 64 px or more.
source "$(dirname -- "${BASH_SOURCE[0]}")/icon_theme.sh"

theme="$(active_icon_theme)"
IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
bases=("${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons" "${dirs[@]/%//icons}")

inherited=()
for base in "${bases[@]}"; do
    [[ -n $theme && -f $base/$theme/index.theme ]] || continue
    IFS=, read -ra inherited <<< "$(awk -F= '$1 == "Inherits" { gsub(/[ \r]/, "", $2); print $2; exit }' "$base/$theme/index.theme")"
    break
done

# rank<TAB>path, rank being the source's place in the order above
candidates() {
    local base t rank=2
    for base in "${bases[@]}"; do
        [[ -d $base/hicolor ]] && find -L "$base/hicolor" -path '*/apps/*' -type f \( -name '*.svg' -o -name '*.png' \) -printf '0\t%p\n'
    done
    for base in "${dirs[@]}"; do
        [[ -d $base/pixmaps ]] && find -L "$base/pixmaps" -maxdepth 1 -type f \( -name '*.svg' -o -name '*.png' \) -printf '1\t%p\n'
    done
    for t in "${inherited[@]}"; do
        [[ -n $t && $t != hicolor && $t != "$theme" ]] || continue
        for base in "${bases[@]}"; do
            [[ -d $base/$t ]] && find -L "$base/$t" -path '*/apps/*' -type f \( -name '*.svg' -o -name '*.png' \) -printf "$rank\t%p\n"
        done
        rank=$((rank + 1))
    done
}

candidates 2> /dev/null | awk -F'\t' '{
    path = $2; file = path; sub(/.*\//, "", file)
    name = file; sub(/\.[^.]*$/, "", name)
    design = 0; size = 0
    if (match(path, /\/[0-9]+(x[0-9]+)?(@[0-9]x)?\//)) {
        seg = substr(path, RSTART + 1, RLENGTH - 2)
        design = seg + 0; size = design
        if (seg ~ /@[0-9]x/) { scale = seg; sub(/.*@/, "", scale); size *= scale + 0 }
    }
    if (file ~ /\.svg$/) score = design ? 1000 - design : 0
    else score = 2000 + (size >= 64 ? size : 100000 - size)
    printf "%s\t%d\t%d\t%s\n", name, $1, score, path
}' | sort -t$'\t' -k1,1 -k2,2n -k3,3n | awk -F'\t' '!seen[$1]++ { print $1 "\t" $4 }'
