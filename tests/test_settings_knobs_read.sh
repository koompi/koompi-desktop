#!/usr/bin/env bash
# Every knob Settings writes must be read by something.
#
# A ConfigSpinBox in modules/settings writes Config.options.<path>. Nothing checks
# that anything reads that path back, so a knob can sit in the UI, move, persist to
# config.json and change nothing at all. bar.workspaces.showNumberDelay was exactly
# that: the "Number show delay when pressing Super" spinbox wrote it while
# Workspaces.qml paced its timer off bar.autoHide.showWhenPressingSuper.delay.
#
# A reader is any use of the same path outside modules/settings and Config.qml:
# QML elsewhere in the shell, or a script pulling it out of config.json with jq.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SETTINGS="$SHELL_ROOT/modules/settings"

[[ -d "$SETTINGS" ]] || { echo "missing $SETTINGS" >&2; exit 1; }

# Paths that are written from Settings and read by nothing, deliberately. Empty on
# purpose: add a row only with the reason, never to silence a real dead knob.
declare -a ALLOWED=()

# `Config.options.a.b.c =` and `Config.options?.a.b.c =`, minus the assignment.
written="$(grep -rhoE 'Config\.options\??(\.[A-Za-z_][A-Za-z0-9_]*\??)+[[:space:]]*=[^=]' "$SETTINGS" 2>/dev/null \
    | sed -E 's/[[:space:]]*=.*$//; s/^Config\.options\??\.//; s/\?//g' \
    | sort -u)"

[[ -n "$written" ]] || { echo "found no Config.options writes under $SETTINGS; the scan broke" >&2; exit 1; }

dead=()
checked=0
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    checked=$((checked + 1))

    skip=0
    for allowed in ${ALLOWED[@]+"${ALLOWED[@]}"}; do
        [[ "$path" == "$allowed" ]] && { skip=1; break; }
    done
    (( skip )) && continue

    # QML reader, either spelling:
    #   Config.options.a.b.c              - the whole path, optional-chained or not
    #   const cfg = Config.options.a.b     - an alias, with `.c` off it later
    # For the alias form, walk the parents: a file that reads the parent object and
    # mentions the leaf is reading the knob.
    leaf="${path##*.}"
    prefix="$path"
    found=0
    while :; do
        pattern="options$(sed -E 's/\./\\??\\./g' <<< ".$prefix")\\b"
        readers="$(grep -rlE "$pattern" --include='*.qml' --include='*.js' "$SHELL_ROOT" \
            --exclude-dir=settings --exclude=Config.qml 2>/dev/null)"
        if [[ -n "$readers" ]]; then
            if [[ "$prefix" == "$path" ]]; then
                found=1
            elif grep -qE "\\b${leaf}\\b" $readers 2>/dev/null; then
                found=1
            fi
        fi
        (( found )) && break
        [[ "$prefix" == *.* ]] || break
        prefix="${prefix%.*}"
    done
    (( found )) && continue

    # Script reader: jq over config.json, keyed on the same path.
    if grep -rqF ".$path" "$SHELL_ROOT/scripts" "$REPO_ROOT/dots/.local" "$REPO_ROOT/cli" 2>/dev/null; then
        continue
    fi

    dead+=("$path")
done <<< "$written"

if (( ${#dead[@]} )); then
    echo "Settings writes these config paths and nothing reads them back:" >&2
    printf '  %s\n' "${dead[@]}" >&2
    echo >&2
    echo "Point the reader at the path Settings writes, drop the control, or add the" >&2
    echo "path to ALLOWED in this test with the reason." >&2
    exit 1
fi

echo "ok   settings: $checked config paths written by Settings, every one has a reader"
