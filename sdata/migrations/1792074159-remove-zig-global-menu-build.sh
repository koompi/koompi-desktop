# shellcheck shell=bash
# The zig global menu daemon was built inside the installed shell tree. ./setup's files step
# excludes zig-out/ and .zig-cache/ from its rsync --delete, and rsync leaves a directory that
# still holds excluded files, so dropping the daemon from the repo left
# ~/.config/quickshell/koompi/scripts/global-menu behind with a stale binary (and up to
# hundreds of MB of cache) in it, plus its build cache under ~/.cache/koompi/build. Removed
# only while nothing but that build output is left in the directory.
dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/koompi/scripts/global-menu"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/koompi/build/global-menu"

if [[ -d "$dir" ]]; then
    other="$(find "$dir" -mindepth 1 -maxdepth 1 ! -name zig-out ! -name .zig-cache -print -quit)"
    if [[ -z "$other" ]]; then
        rm -rf -- "$dir"
        echo "removed the old zig global menu build from $dir"
    else
        echo "left $dir in place: it holds more than the old zig build ($other)"
    fi
fi
if [[ -d "$cache" ]]; then
    rm -rf -- "$cache"
    echo "removed the old zig global menu build cache $cache"
fi
exit 0
