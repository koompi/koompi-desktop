// KOOMPI touchpad gestures: the background half of the swipe. It keeps each tab's
// back/forward list and a picture of each page in it, so a swipe can slide the previous
// (or next) page in under the fingers the way Safari does. A content script cannot see
// either: the browser hides other origins' history entries from it, and it cannot take a
// screenshot.
//
// Kept in chrome.storage.session, not in memory: the service worker is stopped after
// half a minute idle, and the list has to outlive it.

const SHOTS_KEPT = 24;       // pictures across every tab; the oldest go first
const SHOT_QUALITY = 55;     // jpeg; a picture only has to read for a third of a second
const SETTLE_MS = 700;       // after a load, let the page paint before the picture

const stackKey = tab => `stack:${tab}`;

async function getStack(tab) {
    const key = stackKey(tab);
    return (await chrome.storage.session.get(key))[key] ?? { entries: [], index: -1 };
}
const putStack = (tab, stack) => chrome.storage.session.set({ [stackKey(tab)]: stack });

// A main-frame navigation: a new entry, a move through the list, or the same entry again.
async function committed(tab, url, backForward, replace) {
    const stack = await getStack(tab);
    const here = stack.entries[stack.index];
    if (here && here.url === url) return;
    if (backForward) {
        // the nearest entry with this url, either way
        for (let step = 1; step < stack.entries.length; step++) {
            for (const i of [stack.index - step, stack.index + step]) {
                if (stack.entries[i]?.url === url) {
                    stack.index = i;
                    return putStack(tab, stack);
                }
            }
        }
    }
    if (replace && here) {
        here.url = url;
        here.shot = null;
    } else {
        stack.entries = stack.entries.slice(0, stack.index + 1);
        stack.entries.push({ url, shot: null, at: Date.now() });
        stack.index = stack.entries.length - 1;
    }
    await putStack(tab, stack);
}

chrome.webNavigation.onCommitted.addListener(d => {
    if (d.frameId !== 0) return;
    const q = d.transitionQualifiers ?? [];
    committed(d.tabId, d.url, q.includes("forward_back"),
        q.includes("client_redirect") || q.includes("server_redirect") || d.transitionType === "reload");
});
chrome.webNavigation.onHistoryStateUpdated.addListener(d => {
    if (d.frameId !== 0) return;
    committed(d.tabId, d.url, (d.transitionQualifiers ?? []).includes("forward_back"), false);
});
chrome.tabs.onRemoved.addListener(tab => chrome.storage.session.remove(stackKey(tab)));

let lastShot = 0;
async function capture(tabId) {
    // the browser allows two captures a second
    if (Date.now() - lastShot < 600) return;
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (!tab?.active || tab.status !== "complete") return;
    lastShot = Date.now();
    const shot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: "jpeg", quality: SHOT_QUALITY }).catch(() => null);
    if (!shot) return;
    const stack = await getStack(tabId);
    const here = stack.entries[stack.index];
    if (!here || here.url !== tab.url) return;
    here.shot = shot;
    here.at = Date.now();
    await putStack(tabId, stack);
    await prune();
}

// only the newest pictures stay: session storage holds 10 MB
async function prune() {
    const all = await chrome.storage.session.get(null);
    const shots = [];
    for (const [key, stack] of Object.entries(all))
        if (key.startsWith("stack:"))
            stack.entries.forEach((e, i) => e.shot && shots.push({ key, i, at: e.at }));
    if (shots.length <= SHOTS_KEPT) return;
    shots.sort((a, b) => a.at - b.at);
    const changed = {};
    for (const old of shots.slice(0, shots.length - SHOTS_KEPT)) {
        changed[old.key] = changed[old.key] ?? all[old.key];
        changed[old.key].entries[old.i].shot = null;
    }
    await chrome.storage.session.set(changed);
}

chrome.tabs.onUpdated.addListener((tabId, info) => {
    if (info.status === "complete") setTimeout(() => capture(tabId), SETTLE_MS);
});
chrome.tabs.onActivated.addListener(({ tabId }) => setTimeout(() => capture(tabId), SETTLE_MS));

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
    const tabId = sender.tab?.id;
    if (tabId === undefined) return;
    if (msg.type === "settled") {
        capture(tabId);
        return;
    }
    if (msg.type === "neighbours") {
        getStack(tabId).then(stack => reply({
            back: stack.entries[stack.index - 1]?.shot ?? null,
            forward: stack.entries[stack.index + 1]?.shot ?? null,
        }));
        return true;
    }
});

// Fingers on the touchpad, for pull to refresh: a page cannot tell fingers resting still
// from fingers that have left, and the reload must wait for them to leave. The count comes
// from libexec/touchpad-fingers through native messaging; a pull that is under way holds a
// port here and hears every change. Without the helper (not installed, no touchpad, not in
// the `input` group) the pulls are told so and judge by the wheel events alone.
const FINGERS_HOST = "org.koompi.touchpad";
let fingers = { ready: false, fingers: 0 };
let host = null;
let answered = false;     // the helper has said whether it can see a touchpad
const listening = new Set();

function startHost() {
    if (host) return;
    answered = false;
    try {
        host = chrome.runtime.connectNative(FINGERS_HOST);
    } catch (e) {
        host = null;
        answered = true;
        return;
    }
    host.onMessage.addListener(msg => {
        answered = true;
        fingers = { ready: !!msg.ready, fingers: msg.fingers | 0 };
        for (const port of listening) port.postMessage(fingers);
    });
    host.onDisconnect.addListener(() => {
        void chrome.runtime.lastError;
        host = null;
        answered = true;
        fingers = { ready: false, fingers: 0 };
        for (const port of listening) port.postMessage(fingers);
    });
}

chrome.runtime.onConnect.addListener(port => {
    if (port.name !== "fingers") return;
    startHost();
    listening.add(port);
    port.onDisconnect.addListener(() => listening.delete(port));
    // a helper still starting is not a missing one: its first word reaches every port
    if (answered || !host) port.postMessage(fingers);
});
// up before the first pull, so the first pull does not wait for the helper to start
startHost();
