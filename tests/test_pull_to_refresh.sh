#!/usr/bin/env bash
# The pull-to-refresh content script (dots/.local/share/koompi/browser/pull-to-refresh), run
# in headless Chromium against synthetic wheel events:
#   - a touchpad pull past the threshold at the top of the page reloads it;
#   - a short pull does not;
#   - a mouse wheel turned up at the top does not;
#   - a pull that starts below the top (scrolling up into the top) does not.
# A page counts its loads in sessionStorage; the dumped DOM says how many it saw.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$REPO_ROOT/dots/.local/share/koompi/browser/pull-to-refresh"
failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

browser="$(command -v chromium || command -v google-chrome-stable || true)"
[[ -n "$browser" ]] || { echo "skip: no chromium or chrome"; exit 0; }
python3 -m json.tool "$EXT/manifest.json" > /dev/null || fail "manifest.json does not parse"
grep -q '"pull.js"' "$EXT/manifest.json" || fail "the manifest does not load pull.js"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# $1 scenario: the gesture the page plays on its first load
page() {
    cat > "$tmp/$1.html" <<HTML
<!doctype html><html><body style="height:4000px;margin:0">
<script>$(cat "$EXT/pull.js")</script>
<script>
const loads = Number(sessionStorage.getItem("loads") || 0) + 1;
sessionStorage.setItem("loads", loads);
document.body.dataset.loads = loads;
const wheel = (dy, opts = {}) => document.body.dispatchEvent(new WheelEvent("wheel", { deltaY: dy, bubbles: true, ...opts }));
const play = async (steps, dy, gap = 10) => { for (let i = 0; i < steps; i++) { wheel(dy); await new Promise(r => setTimeout(r, gap)); } };
if (loads === 1) setTimeout(async () => {
    switch ("$1") {
    case "pull":  await play(30, -12); break;
    case "short": await play(6, -12); break;
    case "mouse": for (let i = 0; i < 6; i++) { document.body.dispatchEvent(new WheelEvent("wheel", { deltaY: -100, wheelDeltaY: 120, bubbles: true })); await new Promise(r => setTimeout(r, 30)); } break;
    case "below": scrollTo(0, 600); await new Promise(r => setTimeout(r, 50)); await play(30, -12); break;
    }
}, 100);
</script></body></html>
HTML
}

loads_after() {
    page "$1"
    "$browser" --headless=new --disable-gpu --no-first-run --user-data-dir="$tmp/profile-$1" \
        --virtual-time-budget=4000 --dump-dom "file://$tmp/$1.html" 2> /dev/null \
        | grep -o 'data-loads="[0-9]*"' | grep -o '[0-9]*'
}

[[ "$(loads_after pull)" == 2 ]]  || fail "a full touchpad pull at the top did not reload the page"
[[ "$(loads_after short)" == 1 ]] || fail "a short pull reloaded the page"
[[ "$(loads_after mouse)" == 1 ]] || fail "a mouse wheel turned up at the top reloaded the page"
[[ "$(loads_after below)" == 1 ]] || fail "a pull that started below the top reloaded the page"

(( failed )) || echo "ok   pull to refresh: a full pull at the top reloads; a short pull, a mouse wheel and a scroll into the top do not"
exit $failed
