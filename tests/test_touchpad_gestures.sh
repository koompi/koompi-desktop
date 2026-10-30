#!/usr/bin/env bash
# The KOOMPI touchpad gestures extension (dots/.local/share/koompi/browser/pull-to-refresh),
# its content scripts run in headless Chromium against synthetic wheel events.
# Pull to refresh, with the touchpad's finger count (pad-*, background.js stood in for):
#   - a full pull reloads when the fingers lift, and only then: held still on the touchpad
#     for seconds it does not, and a pause mid-pull is the same pull going on;
#   - a short pull, or a full one taken back, does nothing when the fingers lift;
#   - a helper that cannot see this touchpad leaves the page to judge by the wheel alone.
# And by the wheel alone:
#   - a full pull let go while still moving (the browser's glide follows) reloads;
#   - a full pull that stops dead does not, since resting fingers look the same;
#   - a short pull, pulls that only reach the old 180px and 360px thresholds, a short flick whose
#     glide would carry it past the threshold, a full pull taken back before letting go, a
#     glide that arrives at the top on its own, a mouse wheel turned up at the top, and a pull
#     that starts below the top do not.
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
<script>
// background.js and the touchpad, stood in for: fingers(n) is the touchpad's count changing
if ("$1".startsWith("pad-")) {
    const heard = [];
    const port = { onMessage: { addListener: f => heard.push(f) }, onDisconnect: { addListener() {} }, disconnect() {} };
    window.fingers = n => heard.forEach(f => f({ ready: true, fingers: n }));
    Object.defineProperty(window, "chrome", { configurable: true, value: { runtime: {
        connect() { setTimeout(() => fingers("$1" === "pad-deaf" ? 0 : 2), 5); return port; },
    } } });
}
</script>
<script>$(cat "$EXT/pull.js")</script>
<script>
const loads = Number(sessionStorage.getItem("loads") || 0) + 1;
sessionStorage.setItem("loads", loads);
document.body.dataset.loads = loads;
const wheel = (dy, opts = {}) => document.body.dispatchEvent(new WheelEvent("wheel", { deltaY: dy, bubbles: true, ...opts }));
const play = async (steps, dy, gap = 10) => { for (let i = 0; i < steps; i++) { wheel(dy); await new Promise(r => setTimeout(r, gap)); } };
// the browser's glide after the fingers lift while moving: one event a frame, slowing down
const glide = async (dy) => { for (let i = 0; i < 30; i++) { wheel(dy * 0.88 ** i, { momentum: true }); await new Promise(r => setTimeout(r, 16)); } };
const wait = ms => new Promise(r => setTimeout(r, ms));
if (loads === 1) setTimeout(async () => {
    switch ("$1") {
    case "pad-lift":  await play(70, -12); await wait(600); fingers(0); break;
    case "pad-liftglide": await play(70, -12); fingers(0); await glide(-40); break;
    case "pad-hold":  await play(70, -12); await wait(3000); break;
    case "pad-pause": await play(40, -12); await wait(600); await play(30, -12); await wait(400); fingers(0); break;
    case "pad-short": await play(20, -12); await wait(600); fingers(0); break;
    case "pad-undo":  await play(70, -12); await play(35, 12); fingers(0); break;
    case "pad-deaf":  await play(70, -12); await glide(-40); break;
    case "still": await play(70, -12); break;
    case "pullglide": await play(70, -12); await glide(-40); break;
    case "short": await play(6, -12); break;
    case "old":   await play(20, -12); break;
    case "last":  await play(40, -12); break;
    case "flick": await play(15, -12); await glide(-40); break;
    case "undo":  await play(70, -12); await play(35, 12); break;
    case "coast": await glide(-40); break;
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
        --virtual-time-budget=6000 --dump-dom "file://$tmp/$1.html" 2> /dev/null \
        | grep -o 'data-loads="[0-9]*"' | grep -o '[0-9]*'
}

[[ "$(loads_after pad-lift)" == 2 ]]  || fail "a full pull did not reload the page when the fingers lifted"
[[ "$(loads_after pad-liftglide)" == 2 ]] || fail "a full pull let go while moving did not reload exactly once"
[[ "$(loads_after pad-hold)" == 1 ]]  || fail "a full pull reloaded the page while the fingers were still on the touchpad"
[[ "$(loads_after pad-pause)" == 2 ]] || fail "a pull that paused with the fingers down and went on did not reload when they lifted"
[[ "$(loads_after pad-short)" == 1 ]] || fail "a short pull reloaded the page when the fingers lifted"
[[ "$(loads_after pad-undo)" == 1 ]]  || fail "a full pull taken back reloaded the page when the fingers lifted"
[[ "$(loads_after pad-deaf)" == 2 ]]  || fail "with a helper that cannot see this touchpad, a full pull let go while moving did not reload"
[[ "$(loads_after still)" == 1 ]]     || fail "with no word from the touchpad, a pull that stopped dead reloaded under fingers that may be resting"
[[ "$(loads_after pullglide)" == 2 ]] || fail "a full pull let go while still moving did not reload the page"
[[ "$(loads_after short)" == 1 ]] || fail "a short pull reloaded the page"
[[ "$(loads_after old)" == 1 ]]   || fail "a 240px pull reloaded the page; the pull is as twitchy as it was at 180px"
[[ "$(loads_after last)" == 1 ]]  || fail "a 480px pull reloaded the page; that was still a short stroke at the 360px threshold"
[[ "$(loads_after flick)" == 1 ]] || fail "a short flick reloaded the page: the glide after the fingers left was counted as pull"
[[ "$(loads_after undo)" == 1 ]]  || fail "a full pull taken back before letting go reloaded the page"
[[ "$(loads_after coast)" == 1 ]] || fail "a glide that arrived at the top on its own reloaded the page"
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
