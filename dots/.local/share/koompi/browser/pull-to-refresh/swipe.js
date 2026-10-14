// KOOMPI swipe between pages, as on a Mac. Two fingers sideways past the edge of a page:
// the previous page (or the next) slides in under the fingers, following them, and
// letting go far enough - or flicking - finishes the slide and goes there. Letting go
// early slides it back. The picture is the page as it was last seen (background.js).
//
// Chrome's own touchpad back/forward is switched off in chrome-flags.conf
// (TouchpadOverscrollHistoryNavigation), or both would navigate.
(() => {
    const COMMIT = 0.33;      // of the width: let go past this and it goes
    const FLICK = 0.9;        // px per ms at the end of a gesture: a flick goes too
    const RELEASE_MS = 140;   // no wheel event for this long: the fingers are off
    const GESTURE_GAP = 300;  // a pause this long before an event starts a new gesture
    const SETTLE_MS = 800;    // scrolling stopped this long: the page is worth a picture

    let neighbours = { back: null, forward: null };
    let dir = 0;              // -1 back, 1 forward, 0 no swipe in this gesture
    let travel = 0;           // px the fingers have moved in the swipe's direction
    let decided = false;      // the gesture has been read as a swipe or as a scroll
    let lastEvent = -Infinity;
    let velocity = 0;
    let releaseTimer = 0;
    let settleTimer = 0;
    let host = null, layer = null, shade = null, picture = null, sheet = null;

    const send = msg => new Promise(resolve => {
        try {
            chrome.runtime.sendMessage(msg, r => resolve(chrome.runtime.lastError ? null : r));
        } catch (e) {
            resolve(null);   // the extension was reloaded under this page
        }
    });
    const refresh = () => send({ type: "neighbours" }).then(r => { if (r) neighbours = r; });

    const canGo = d => window.navigation
        ? (d < 0 ? navigation.canGoBack : navigation.canGoForward)
        : history.length > 1;

    // at the edge of everything the swipe would otherwise scroll sideways
    function atEdge(e, d) {
        for (const node of e.composedPath()) {
            if (!(node instanceof Element) || node.scrollWidth <= node.clientWidth) continue;
            const style = getComputedStyle(node).overflowX;
            if (node !== document.scrollingElement && style !== "auto" && style !== "scroll") continue;
            const left = Math.abs(node.scrollLeft);
            if (d < 0 ? left > 0 : left + node.clientWidth < node.scrollWidth - 1) return false;
        }
        return true;
    }

    function build() {
        if (host) return;
        host = document.createElement("div");
        const root = host.attachShadow({ mode: "closed" });
        root.innerHTML = `
<style>
  :host { all: initial; }
  .shade { position: fixed; inset: 0; z-index: 2147483646; pointer-events: none;
           background: #000; opacity: 0; }
  .layer { position: fixed; inset: 0; z-index: 2147483647; pointer-events: none;
           display: none; box-shadow: 0 0 40px rgba(0, 0, 0, .35); overflow: hidden;
           background: #f4f5f7; }
  .layer img { width: 100%; height: 100%; object-fit: cover; object-position: top; display: block; }
  .blank { position: absolute; inset: 0; display: grid; place-items: center; color: #8a8f98;
           font: 600 15px system-ui, sans-serif; }
  @media (prefers-color-scheme: dark) { .layer { background: #1d1f23; } }
</style>
<div class="shade"></div>
<div class="layer"><img alt=""><div class="blank"></div></div>`;
        shade = root.querySelector(".shade");
        layer = root.querySelector(".layer");
        picture = layer.querySelector("img");
        sheet = layer.querySelector(".blank");
        document.documentElement.appendChild(host);
    }

    // p: 0 (not started) .. 1 (the other page fills the window)
    function place(p, animate) {
        const ms = animate ? 260 : 0;
        const ease = "cubic-bezier(.2, .8, .3, 1)";
        layer.style.transition = shade.style.transition = animate ? `transform ${ms}ms ${ease}, opacity ${ms}ms ${ease}` : "none";
        layer.style.transform = `translateX(${(dir < 0 ? -1 : 1) * (1 - p) * 100}%)`;
        shade.style.opacity = String(0.25 * p);
        return new Promise(r => setTimeout(r, ms));
    }

    function begin(d) {
        build();
        dir = d;
        const shot = d < 0 ? neighbours.back : neighbours.forward;
        picture.style.display = shot ? "block" : "none";
        if (shot) picture.src = shot;
        sheet.textContent = shot ? "" : (d < 0 ? "← Back" : "Forward →");
        layer.style.display = "block";
        place(0, false);
        // a single-page app moves on without a load, so ask again for what is next to it now
        refresh().then(() => {
            const fresh = d < 0 ? neighbours.back : neighbours.forward;
            if (dir !== d || !fresh || fresh === shot) return;
            picture.src = fresh;
            picture.style.display = "block";
            sheet.textContent = "";
        });
    }

    function end() {
        layer.style.display = "none";
        shade.style.opacity = "0";
        dir = 0;
        travel = 0;
    }

    async function release() {
        const width = innerWidth;
        const p = travel / width;
        const go = canGo(dir) && (p >= COMMIT || (velocity >= FLICK && p > 0.08));
        if (go) {
            await place(1, true);
            const d = dir;
            // the slid-in picture stays up until the other page replaces this one
            if (d < 0) history.back(); else history.forward();
        } else {
            await place(0, true);
            end();
        }
        decided = false;
    }

    addEventListener("wheel", e => {
        if (e.ctrlKey || e.deltaMode !== 0) return;
        const now = performance.now();
        const gap = now - lastEvent;
        lastEvent = now;
        if (gap > GESTURE_GAP) {
            decided = false;
            velocity = 0;
        }
        if (!decided) {
            // the first events say what this gesture is; mostly vertical is a scroll
            if (Math.abs(e.deltaX) < 2 || Math.abs(e.deltaX) <= Math.abs(e.deltaY) * 1.5) {
                if (Math.abs(e.deltaY) > 2) decided = true;
                return;
            }
            decided = true;
            const d = e.deltaX < 0 ? -1 : 1;
            if (!atEdge(e, d)) return;
            begin(d);
        }
        if (dir === 0) return;
        travel = Math.max(0, travel + (dir < 0 ? -e.deltaX : e.deltaX));
        // past the end of the history the page only gives a little
        const room = canGo(dir) ? 1 : 0.12;
        const p = Math.min(travel / innerWidth, 1) * room;
        velocity = Math.abs(e.deltaX) / Math.max(gap, 1);
        place(p, false);
        clearTimeout(releaseTimer);
        releaseTimer = setTimeout(release, RELEASE_MS);
    }, { passive: true, capture: true });

    // a picture of the page as it is now, for coming back to it
    addEventListener("scroll", () => {
        clearTimeout(settleTimer);
        settleTimer = setTimeout(() => send({ type: "settled" }), SETTLE_MS);
    }, { passive: true });

    // back on this page from the back/forward cache: drop the slide that left it, and
    // learn the new neighbours
    addEventListener("pageshow", ev => {
        if (ev.persisted && layer) end();
        refresh();
    });
    // a back or forward inside a single-page app: there is no new page to cover the slide,
    // so it fades once the app has drawn
    addEventListener("popstate", () => {
        refresh();
        if (!layer || layer.style.display !== "block") return;
        setTimeout(() => {
            layer.style.transition = shade.style.transition = "opacity 180ms ease";
            layer.style.opacity = "0";
            shade.style.opacity = "0";
            setTimeout(() => { end(); layer.style.opacity = "1"; }, 200);
        }, 120);
    });
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
    refresh();
})();
