// KOOMPI pull to refresh, as on an iPhone. At the top of a page, pull down with two fingers on
// the touchpad: a spinner comes down with the fingers and draws its ticks one by one. Once
// every tick is drawn it pops and starts to turn, and letting go then reloads the page. Let go
// before that, or pull back up first, and it slides away and nothing happens.
// Chrome's own elastic overscroll (ElasticOverscroll in chrome-flags.conf) gives the bounce;
// this adds the reload.
//
// Letting go is the moment that counts, and holding still never reloads. A page cannot see it:
// fingers resting on the touchpad and fingers gone both just stop the wheel events. So the
// touchpad says how many fingers are on it (libexec/touchpad-fingers, through background.js),
// and the reload waits for that count to drop below two.
//
// On Wayland, Chrome also turns a lift with the fingers still moving into a glide (a fling):
// wheel events it makes up itself and marks `momentum`. They come after the fingers have
// left, so they never pull and never start a pull, and the first one is a release too.
// Counting them is what let a short flick at the top glide on until the page reloaded.
//
// Without the touchpad's word (no helper, or it cannot see this touchpad) the glide is the
// only release the page can trust: a pull that stops dead slides away after a moment rather
// than reload under fingers that may still be resting there.
//
// Only touchpad gestures count, and only ones that start at the top: a mouse wheel turned
// up at the top of a page, or a scroll that arrives at the top, never reloads anything.
(() => {
    const THRESHOLD = 720;   // px of finger travel before letting go reloads; at 360 a short
                             // stroke on a laptop touchpad already got there
    const SETTLE_MS = 160;   // no wheel event for this long: the fingers stopped, or left
    const GIVE_UP_MS = 900;  // with no word from the touchpad, a pull that stopped this long goes
    const GESTURE_GAP = 300; // a pause this long before an event starts a new gesture
    const TICKS = 8;
    const DROP = 96;         // px the spinner would come down for an endless pull; each px of
                             // pull moves it less than the one before, like a rubber band

    let pull = 0;
    let armed = false;
    let ready = false;
    let gliding = false;     // the last event was the browser's glide, not the fingers
    let lastEvent = -Infinity;
    let releaseTimer = 0;
    let pad = null;          // {ready, fingers} from the touchpad; null until it has answered
    let padPort = null;
    let sawTwo = false;      // the touchpad counted the pull's fingers, so its count is this pull's
    let host = null;
    let wrap = null;
    let ticks = [];

    // A mouse wheel notch is a multiple of 120 in wheelDelta; a touchpad gives any value.
    const fromMouse = e => e.wheelDeltaY !== 0 && e.wheelDeltaY % 120 === 0 && e.deltaX === 0;
    // A browser too old to mark its glide still gives it away: the glide carries no wheel ticks.
    const isGlide = e => "momentum" in e ? e.momentum : e.wheelDeltaY === 0 && Math.abs(e.deltaY) >= 1;

    // At the top of everything the event would scroll: the page, and any scroller it is inside.
    function atTop(e) {
        for (const node of e.composedPath()) {
            if (!(node instanceof Element)) continue;
            if (node.scrollTop > 0 && node.scrollHeight > node.clientHeight) {
                const style = getComputedStyle(node).overflowY;
                if (style === "auto" || style === "scroll" || node === document.scrollingElement)
                    return false;
            }
        }
        return (document.scrollingElement?.scrollTop ?? window.scrollY) <= 0;
    }

    function ensureIndicator() {
        if (host) return;
        host = document.createElement("div");
        const root = host.attachShadow({ mode: "closed" });
        const lines = Array.from({ length: TICKS }, (_, i) =>
            `<line x1="12" y1="2.6" x2="12" y2="7" transform="rotate(${i * 360 / TICKS} 12 12)"/>`).join("");
        root.innerHTML = `
<style>
  :host { all: initial; }
  .wrap { position: fixed; top: 0; left: 50%; z-index: 2147483647; pointer-events: none;
          opacity: 0; transform: translate(-50%, -44px) scale(.6); }
  .wrap.back { transition: transform .34s cubic-bezier(.3, 0, .2, 1), opacity .26s ease; }
  .disc { width: 38px; height: 38px; border-radius: 50%; display: grid; place-items: center;
          background: rgba(252, 252, 253, .86); backdrop-filter: blur(12px) saturate(1.6);
          box-shadow: 0 0 0 .5px rgba(0, 0, 0, .06), 0 1px 2px rgba(0, 0, 0, .08), 0 6px 18px rgba(0, 0, 0, .16); }
  svg { width: 22px; height: 22px; display: block; }
  line { stroke: #6e6e73; stroke-width: 2.3; stroke-linecap: round; opacity: 0; }
  .ready .disc { animation: pop .32s cubic-bezier(.3, 0, .2, 1); }
  .ready svg { animation: turn .9s steps(${TICKS}) infinite; }
  @keyframes pop { 45% { transform: scale(1.14); } 100% { transform: scale(1); } }
  @keyframes turn { to { transform: rotate(360deg); } }
  .dark .disc { background: rgba(58, 58, 60, .9);
                box-shadow: 0 0 0 .5px rgba(255, 255, 255, .12), 0 6px 18px rgba(0, 0, 0, .45); }
  .dark line { stroke: #aeaeb2; }
  @media (prefers-reduced-motion: reduce) {
    .ready .disc, .ready svg { animation: none; }
  }
</style>
<div class="wrap"><div class="disc"><svg viewBox="0 0 24 24" fill="none">${lines}</svg></div></div>`;
        wrap = root.querySelector(".wrap");
        ticks = [...root.querySelectorAll("line")];
        document.documentElement.appendChild(host);
    }

    // The spinner takes the page's shade, not the system's: a dark disc on a white page is a hole.
    function pageIsDark() {
        for (const el of [document.body, document.documentElement]) {
            if (!el) continue;
            const [r, g, b, a = 1] = (getComputedStyle(el).backgroundColor.match(/[\d.]+/g) ?? []).map(Number);
            if (a > 0.5) return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128;
        }
        // nothing painted: the canvas is white unless the page asked for the dark scheme
        return getComputedStyle(document.documentElement).colorScheme.includes("dark")
            && matchMedia("(prefers-color-scheme: dark)").matches;
    }

    // Follows the fingers with no easing; only going away is animated.
    function show(progress) {
        ensureIndicator();
        const p = Math.min(progress, 1);
        wrap.classList.remove("back");
        wrap.style.opacity = String(Math.min(1, progress * 3));
        const y = -44 + DROP * (1 - 1 / (1 + 1.6 * progress));
        wrap.style.transform = `translate(-50%, ${y}px) scale(${0.6 + 0.4 * p})`;
        if (ready !== progress >= 1) {
            ready = progress >= 1;
            wrap.classList.toggle("ready", ready);
        }
        // pulling, the ticks come in one by one; turning, they trail off behind the brightest
        ticks.forEach((tick, i) => {
            tick.style.opacity = String(ready
                ? 0.25 + 0.75 * (i + 1) / TICKS
                : 0.9 * Math.min(1, Math.max(0, p * TICKS - i)));
        });
    }

    function hide() {
        if (!wrap) return;
        ready = false;
        wrap.classList.add("back");
        wrap.classList.remove("ready");
        wrap.style.opacity = "0";
        wrap.style.transform = "translate(-50%, -44px) scale(.6)";
    }

    // Only while a pull is under way: the port wakes the extension and its helper for nothing otherwise.
    function listen() {
        if (padPort || !globalThis.chrome?.runtime?.connect) return;
        try {
            padPort = chrome.runtime.connect({ name: "fingers" });
        } catch (e) {
            return;          // the extension was reloaded under this page
        }
        padPort.onMessage.addListener(msg => {
            pad = msg;
            if (!armed || !pad.ready) return;
            if (pad.fingers >= 2) sawTwo = true;
            else if (sawTwo) release();
        });
        padPort.onDisconnect.addListener(() => {
            void chrome.runtime.lastError;
            padPort = null;
            pad = null;
        });
    }

    function unlisten() {
        padPort?.disconnect();
        padPort = null;
        pad = null;
        sawTwo = false;
    }

    // the touchpad has counted this pull's fingers and they are still there
    const holding = () => pad?.ready && sawTwo && pad.fingers >= 2;

    // the wheel events stopped
    function settle() {
        if (holding()) return;   // resting fingers: the spinner waits for them to lift
        releaseTimer = setTimeout(cancel, GIVE_UP_MS);
    }

    function cancel() {
        clearTimeout(releaseTimer);
        armed = false;
        pull = 0;
        unlisten();
        hide();
    }

    function release() {
        clearTimeout(releaseTimer);
        const go = armed && pull >= THRESHOLD;
        armed = false;
        pull = 0;
        unlisten();
        if (!go) {
            hide();
            return;
        }
        // the spinner keeps turning until the reloaded page replaces this one
        location.reload();
        // a "leave site?" prompt answered with stay keeps this page, so the spinner goes
        setTimeout(hide, 10000);
    }

    addEventListener("wheel", e => {
        if (e.ctrlKey || e.deltaMode !== 0 || fromMouse(e)) return;
        const now = performance.now();
        const gap = now - lastEvent;
        lastEvent = now;
        if (isGlide(e)) {
            // the fingers have left the touchpad: this is the release, and the glide pulls nothing
            gliding = true;
            if (armed) release();
            return;
        }
        // fingers down again after a glide or a pause: a new gesture, which pulls only if it
        // starts at the top going down. Fingers that only held still are the same pull going on.
        if ((gliding || gap > GESTURE_GAP) && !(armed && holding())) {
            const was = armed && pull > 0;
            armed = e.deltaY < 0 && atTop(e);
            if (was && !armed) cancel();
        }
        gliding = false;
        if (!armed) return;
        if (pull === 0) {
            ensureIndicator();
            wrap.classList.toggle("dark", pageIsDark());
            listen();
        }
        // mostly sideways is a back/forward swipe, not a pull
        if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
        pull = Math.max(0, pull - e.deltaY);
        if (pull === 0) {
            // pushed all the way back up: the page scrolls on as usual
            cancel();
            return;
        }
        show(pull / THRESHOLD);
        clearTimeout(releaseTimer);
        releaseTimer = setTimeout(settle, SETTLE_MS);
    }, { passive: true, capture: true });
})();
