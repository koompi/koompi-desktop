#!/usr/bin/env bash
# J10 round 2: scripts/hyprland/hyprconfigurator.py edits the shell's overrides file
# (hyprland/shellOverrides/main.lua), and every Game mode, Reduce Motion and
# anti-flashbang write goes through it. It imports argparse, re, os and tempfile and
# nothing else, so it must run with no virtual environment: the variable that used to
# be sourced by its shebang is unset for every call below. It must also
#   - print nothing on stderr when it works (a SyntaxWarning on every call hid real errors),
#   - write only the lines it was asked to, in place, and leave the rest of the file alone,
#   - give a second identical call the same file,
#   - take a path with spaces and a value with quotes, backslashes or spaces,
#   - and fail loudly: a non-zero exit and the reason on stderr when it cannot write,
#     or is asked to do nothing, with the file untouched.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/dots/.config/quickshell/koompi/scripts/hyprland/hyprconfigurator.py"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v python3 > /dev/null 2>&1 || { echo "skip: python3 not installed"; exit 0; }
[[ -x "$CONF" ]] || fail "$CONF is not executable"

T="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "$T"' EXIT

[[ "$(head -n1 "$CONF")" == '#!/usr/bin/env python3' ]] \
    || fail "the shebang is '$(head -n1 "$CONF")', not '#!/usr/bin/env python3': it must not need a virtual environment"
echo "ok   shebang: python3 from the PATH, no virtual environment"

conf() { env -u ILLOGICAL_IMPULSE_VIRTUAL_ENV -u PYTHONWARNINGS "$CONF" "$@"; }

OVR="$T/a path with spaces/hyprland/shellOverrides/main.lua"
mkdir -p "$(dirname -- "$OVR")"
printf '%s\n' '-- DO NOT EDIT' 'hl.config({general={gaps_in=9}})' > "$OVR"

conf --file "$OVR" --set animations:enabled 0 --set decoration:blur:enabled 0 --set general:gaps_in 0 > "$T/out" 2> "$T/err" \
    || fail "a set failed with no virtual environment: $(cat "$T/err")"
[[ ! -s "$T/err" ]] || fail "a working call wrote to stderr: $(cat "$T/err")"
expected=$'-- DO NOT EDIT\nhl.config({general={gaps_in=0}})\nhl.config({animations={enabled=0}})\nhl.config({decoration={blur={enabled=0}}})'
[[ "$(cat "$OVR")" == "$expected" ]] || fail "the file after a set is:
$(cat "$OVR")"
echo "ok   set: new keys appended, an existing key rewritten in place, the comment kept, stderr empty, path with spaces"

cp "$OVR" "$T/after-first"
conf --file "$OVR" --set animations:enabled 0 --set decoration:blur:enabled 0 --set general:gaps_in 0 > /dev/null 2>&1 || fail "the second identical set failed"
cmp -s "$OVR" "$T/after-first" || fail "a second identical call changed the file"
echo "ok   a second identical call gives the same file"

conf --file "$OVR" --reset animations:enabled --reset general:gaps_in --reset general:nothing_here > /dev/null 2> "$T/err" || fail "a reset failed: $(cat "$T/err")"
expected=$'-- DO NOT EDIT\nhl.config({decoration={blur={enabled=0}}})'
[[ "$(cat "$OVR")" == "$expected" ]] || fail "the file after a reset is:
$(cat "$OVR")"
echo "ok   reset: the lines go, a key that was never there is no error"

conf --file "$OVR" --reset decoration:blur:enabled --set decoration:rounding 0 > /dev/null 2>&1 || fail "a mixed set and reset failed"
expected=$'-- DO NOT EDIT\nhl.config({decoration={rounding=0}})'
[[ "$(cat "$OVR")" == "$expected" ]] || fail "the file after a mixed call is:
$(cat "$OVR")"
echo "ok   one call can reset and set"

conf --file "$OVR" --set 'decoration:screen_shader' '/home/a user/shaders/"odd" \name.glsl' > /dev/null 2>&1 || fail "a string value with a space, quotes and a backslash failed"
want='hl.config({decoration={screen_shader="/home/a user/shaders/\"odd\" \\name.glsl"}})'
grep -qxF -- "$want" "$OVR" || fail "the string value is not escaped for Lua; the file holds:
$(cat "$OVR")"
if command -v lua > /dev/null 2>&1; then
    cat > "$T/read-back.lua" <<'LUA'
hl = setmetatable({}, { __index = function() return function() end end })
hl.config = function(t)
    local d = t.decoration
    if d and d.screen_shader then io.write(d.screen_shader) end
end
dofile(arg[1])
LUA
    lua "$T/read-back.lua" "$OVR" > "$T/lua-out" 2> "$T/lua-err" < /dev/null \
        || fail "Lua cannot load the file the script wrote: $(cat "$T/lua-err")"
    [[ "$(cat "$T/lua-out")" == '/home/a user/shaders/"odd" \name.glsl' ]] || fail "Lua reads the string back as '$(cat "$T/lua-out")'"
fi
echo "ok   a value with spaces, quotes and a backslash is written as a Lua string that reads back unchanged"

conf --file "$T/values.lua" --set v:int 0 --set v:neg -1 --set v:real 0.5 --set v:lead .5 --set v:exp 1e3 --set v:yes true --set v:word inf --set v:plus +3 > /dev/null 2>&1 \
    || fail "a set of every kind of value failed"
expected=$'hl.config({v={int=0}})\nhl.config({v={neg=-1}})\nhl.config({v={real=0.5}})\nhl.config({v={lead=.5}})\nhl.config({v={exp=1e3}})\nhl.config({v={yes=true}})\nhl.config({v={word="inf"}})\nhl.config({v={plus="+3"}})'
[[ "$(cat "$T/values.lua")" == "$expected" ]] || fail "numbers, booleans and words are not told apart:
$(cat "$T/values.lua")"
echo "ok   numbers and booleans are bare, a word that only looks numeric to Python (inf, +3) is a string"

before="$(cat "$OVR")"
for key in 'a}b:c' 'a:b c' ':a' 'a:' 'a:b)'; do
    if conf --file "$OVR" --set "$key" 1 > /dev/null 2> "$T/err"; then fail "the key '$key' was accepted"; fi
    [[ -s "$T/err" ]] || fail "the key '$key' was refused without a word on stderr"
done
[[ "$(cat "$OVR")" == "$before" ]] || fail "a refused key still changed the file"
echo "ok   a key that is not an option path is refused before anything is written"

mkdir -p "$T/locked"
cp "$OVR" "$T/locked/main.lua"
chmod 555 "$T/locked"
if conf --file "$T/locked/main.lua" --set animations:enabled 0 > "$T/out" 2> "$T/err"; then
    chmod 755 "$T/locked"
    fail "a write into a directory it cannot write to was reported as success"
fi
chmod 755 "$T/locked"
[[ -s "$T/err" ]] || fail "the failed write said nothing on stderr"
grep -qi 'error' "$T/err" || fail "the failure message does not say what happened: $(cat "$T/err")"
grep -q '^Updated' "$T/out" && fail "the failed write printed an 'Updated' line"
[[ "$(cat "$T/locked/main.lua")" == "$before" ]] || fail "a failed write changed the file"
chmod 555 "$T/locked"
if conf --file "$T/locked/hyprland/shellOverrides/main.lua" --set animations:enabled 0 > "$T/out" 2> "$T/err"; then
    chmod 755 "$T/locked"
    fail "a write into a directory it cannot create was reported as success"
fi
chmod 755 "$T/locked"
[[ -s "$T/err" ]] || fail "the write that cannot create its directory said nothing on stderr"
echo "ok   a write it cannot make exits non-zero with the reason on stderr and no 'Updated' line, in an existing directory and in one it must create"

if conf --file "$OVR" > "$T/out" 2> "$T/err"; then fail "a call that asks for nothing was reported as success"; fi
[[ -s "$T/err" ]] || fail "a call that asks for nothing said nothing on stderr"
[[ "$(cat "$OVR")" == "$before" ]] || fail "a call that asks for nothing changed the file"
echo "ok   a call with nothing to do exits non-zero and says so on stderr"

echo "hyprconfigurator: all checks passed"
