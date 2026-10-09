#!/usr/bin/env bash
# sdata/uv/requirements.txt leaves PyGObject (gi) and OpenCV (cv2) to the distro, so
# the Arch recipe has to install them. A shipped script that imports one of them
# on a machine set up from git, with nothing providing it, fails on first use.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
pkgbuild="$REPO_ROOT/sdata/dist-arch/koompi-python/PKGBUILD"

failed=0
check() {
    local module="$1" package="$2" users
    users="$(grep -rIlE "^(import|from) $module\b" "$REPO_ROOT/dots" --include='*.py' --include='koompi-*' 2>/dev/null |
        grep -v '/tests/' || true)"
    [[ -n "$users" ]] || { echo "FAIL: nothing imports $module any more; drop $package from koompi-python" >&2; failed=1; return; }
    grep -qx "  $package" "$pkgbuild" || {
        echo "FAIL: shipped code imports $module but koompi-python does not depend on $package:" >&2
        sed 's#^#      #' <<< "$users" >&2
        failed=1
    }
}

check gi python-gobject
check cv2 python-opencv
exit "$failed"
