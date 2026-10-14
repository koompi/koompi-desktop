#!/usr/bin/env bash
# The KOOMPI touchpad gestures extension (dots/.local/share/koompi/browser/pull-to-refresh),
# its content scripts run in headless Chromium against synthetic wheel events.
# Pull to refresh:
#   - a touchpad pull past the threshold at the top of the page reloads it;
#   - a short pull, a mouse wheel turned up at the top, and a pull that starts below the
#     top do not.
# Swipe between pages:
#   - a sideways swipe past a third of the width goes back, and so does a quick flick;
#   - a short slow swipe, a mostly vertical scroll, and a swipe forward with nothing ahead stay.
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

# $1 scenario, played on page two after page one sent the browser there. history.back and
# forward are stood in for (headless Chromium never finishes a dump across a real one), and
# the dumped DOM names where the browser was told to go.
swipe_ends_on() {
    cat > "$tmp/one-$1.html" <<HTML
<!doctype html><html><body data-page="one"><script>
if (!sessionStorage.getItem("went")) { sessionStorage.setItem("went", 1); setTimeout(() => location.href = "two-$1.html", 50); }
</script></body></html>
HTML
    cat > "$tmp/two-$1.html" <<HTML
<!doctype html><html><body data-page="two" style="height:3000px;margin:0">
<script>
history.back = () => { document.body.dataset.page = "one"; };
history.forward = () => { document.body.dataset.page = "three"; };
</script>
<script>$(cat "$EXT/swipe.js")</script>
<script>
const wheel = (dx, dy) => document.body.dispatchEvent(new WheelEvent("wheel", { deltaX: dx, deltaY: dy, bubbles: true }));
const play = async (steps, dx, dy, gap = 10) => { for (let i = 0; i < steps; i++) { wheel(dx, dy); await new Promise(r => setTimeout(r, gap)); } };
setTimeout(async () => {
    switch ("$1") {
    case "back":     await play(40, -16, 0); break;
    case "short":    await play(5, -6, 0, 30); break;
    case "flick":    await play(6, -20, 0, 8); break;
    case "vertical": await play(40, -3, 20); break;
    case "forward":  await play(40, 16, 0); break;
    }
}, 400);
</script></body></html>
HTML
    "$browser" --headless=new --disable-gpu --no-first-run --user-data-dir="$tmp/profile-swipe-$1" \
        --virtual-time-budget=6000 --dump-dom "file://$tmp/one-$1.html" 2> /dev/null \
        | grep -o 'data-page="[a-z]*"' | grep -o '"[a-z]*"' | tr -d '"'
}

[[ "$(swipe_ends_on back)" == one ]]     || fail "a full swipe back did not go back"
[[ "$(swipe_ends_on short)" == two ]]    || fail "a short, slow swipe went back"
[[ "$(swipe_ends_on flick)" == one ]]    || fail "a quick flick did not go back"
[[ "$(swipe_ends_on vertical)" == two ]] || fail "a vertical scroll went back"
[[ "$(swipe_ends_on forward)" == two ]]  || fail "a swipe forward with nothing ahead went somewhere"
grep -q 'TouchpadOverscrollHistoryNavigation' <<< "$(grep -h '^--disable-features' "$REPO_ROOT"/dots/.config/{chrome,brave,chromium}-flags.conf)" \
    || fail "a browser that loads the extension still runs its own touchpad back/forward, so a swipe would navigate twice"
grep -q '"swipe.js"' "$EXT/manifest.json" || fail "the manifest does not load swipe.js"
node --check "$EXT/background.js" 2> /dev/null || [[ -z "$(command -v node)" ]] || fail "background.js does not parse"

(( failed )) || echo "ok   touchpad gestures: a full pull at the top reloads, a full swipe goes back; short, mouse, vertical and dead-end gestures do nothing"
exit $failed
