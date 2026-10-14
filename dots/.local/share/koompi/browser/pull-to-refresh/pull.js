// KOOMPI pull to refresh. At the top of a page, pull down past the edge with two fingers on
// the touchpad; a ring fills as you pull, and letting go once it is full reloads the page.
// Chrome's own elastic overscroll (ElasticOverscroll in chrome-flags.conf) gives the bounce;
// this adds the reload a phone has.
//
// Only touchpad gestures count, and only ones that start at the top: a mouse wheel turned
// up at the top of a page, or a fling that arrives at the top, never reloads anything.
(() => {
    const THRESHOLD = 180;   // px of pull before letting go reloads
    const RELEASE_MS = 140;  // no wheel event for this long: the fingers are off
    const GESTURE_GAP = 300; // a pause this long before an event starts a new gesture

    let pull = 0;
    let armed = false;
    let lastEvent = -Infinity;
    let releaseTimer = 0;
    let host = null;
    let ring = null;

    // A mouse wheel notch is a multiple of 120 in wheelDelta; a touchpad gives any value.
    const fromMouse = e => e.wheelDeltaY !== 0 && e.wheelDeltaY % 120 === 0 && e.deltaX === 0;

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
        root.innerHTML = `
<style>
  :host { all: initial; }
  .wrap { position: fixed; top: 0; left: 50%; z-index: 2147483647; pointer-events: none;
          transform: translate(-50%, -48px); transition: opacity .15s ease; opacity: 0; }
  .disc { width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center;
          background: rgba(250, 250, 252, .92); box-shadow: 0 2px 10px rgba(0, 0, 0, .22);
          backdrop-filter: blur(8px); }
  svg { width: 22px; height: 22px; transform: rotate(-90deg); }
  .track { stroke: rgba(0, 0, 0, .12); }
  .fill { stroke: #1f8a5b; transition: stroke .15s ease; }
  .ready .fill { stroke: #12a150; }
  .spin svg { animation: spin .7s linear infinite; }
  @keyframes spin { to { transform: rotate(270deg); } }
  @media (prefers-color-scheme: dark) {
    .disc { background: rgba(40, 42, 46, .92); }
    .track { stroke: rgba(255, 255, 255, .15); }
  }
</style>
<div class="wrap"><div class="disc"><svg viewBox="0 0 24 24" fill="none" stroke-width="2.6" stroke-linecap="round">
  <circle class="track" cx="12" cy="12" r="9"/>
  <circle class="fill" cx="12" cy="12" r="9" stroke-dasharray="56.55" stroke-dashoffset="56.55"/>
</svg></div></div>`;
        ring = root.querySelector(".wrap");
        document.documentElement.appendChild(host);
    }

    function show(progress) {
        ensureIndicator();
        const p = Math.min(progress, 1);
        ring.style.opacity = String(Math.min(1, p * 2));
        ring.style.transform = `translate(-50%, ${-48 + p * 64}px)`;
        ring.querySelector(".fill").style.strokeDashoffset = String(56.55 * (1 - p));
        ring.classList.toggle("ready", progress >= 1);
    }

    function hide() {
        if (!ring) return;
        ring.style.opacity = "0";
        ring.style.transform = "translate(-50%, -48px)";
        ring.classList.remove("ready", "spin");
    }

    function release() {
        if (pull >= THRESHOLD) {
            ring.classList.add("spin");
            location.reload();
        } else {
            hide();
        }
        pull = 0;
        armed = false;
    }

    addEventListener("wheel", e => {
        if (e.ctrlKey || e.deltaMode !== 0 || fromMouse(e)) return;
        const now = performance.now();
        if (now - lastEvent > GESTURE_GAP) armed = e.deltaY < 0 && atTop(e);
        lastEvent = now;
        if (!armed) return;
        // mostly sideways is a back/forward swipe, not a pull
        if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
        pull = Math.max(0, pull - e.deltaY);
        if (pull === 0 && e.deltaY > 0) {
            armed = false;
            hide();
            return;
        }
        show(pull / THRESHOLD);
        clearTimeout(releaseTimer);
        releaseTimer = setTimeout(release, RELEASE_MS);
    }, { passive: true, capture: true });
})();
