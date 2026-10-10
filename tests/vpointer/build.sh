#!/usr/bin/env bash
# build.sh OUT_DIR: compile the virtual pointer into OUT_DIR/vpointer; exit 1 when gcc, wayland-scanner or the client library is missing
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
out="$1"
command -v gcc > /dev/null && command -v wayland-scanner > /dev/null || exit 1
mkdir -p -- "$out"
xml="$here/wlr-virtual-pointer-unstable-v1.xml"
wayland-scanner client-header "$xml" "$out/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$xml" "$out/protocol.c"
gcc -O1 -I"$out" -o "$out/vpointer" "$here/vpointer.c" "$out/protocol.c" -lwayland-client
