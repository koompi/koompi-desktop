.pragma library

function lower(text) {
    return String(text || "").toLowerCase();
}

// the xcb class of org.kde.dolphin is dolphin
function stem(name) {
    return lower(name).split(".").pop();
}

function programOf(text) {
    return String(text || "").trim().split(/\s+/)[0].split("/").pop();
}

// two entries on one program is a launcher such as flatpak, not an app
function entryForProgram(program, entries) {
    const want = programOf(program);
    let found = null;
    if (!want)
        return null;
    for (const entry of entries) {
        if (programOf(entry.command && entry.command[0]) !== want)
            continue;
        if (found && found !== entry)
            return null;
        found = entry;
    }
    return found;
}

function record(spec, now) {
    const entryId = spec.entryId || "";
    const id = spec.id || entryId;
    const names = [];
    // koompi-launch-tui names its window TUI.<id>
    for (const name of [id, entryId, stem(entryId), spec.program, spec.startupClass, "tui." + id]) {
        const key = lower(name);
        if (key.length > 0 && key !== "tui." && names.indexOf(key) < 0)
            names.push(key);
    }
    return {
        id: id,
        entryId: entryId,
        name: spec.name || "",
        icon: spec.icon || "",
        pid: spec.pid || 0,
        names: names,
        startedAt: Math.min(spec.startedAt || now, now)
    };
}

function noneSeen() {
    return { first: {}, focus: "", focusSince: 0, claimedWindows: {}, claimedFocus: false };
}

// first-seen times, the focus move's time, and the claims: a window ends one launch while it exists, a focus move one
function track(seen, windows, active, now) {
    const first = {};
    const claimedWindows = {};
    for (const win of windows) {
        first[win.address] = seen.first[win.address] || now;
        if (seen.claimedWindows[win.address])
            claimedWindows[win.address] = true;
    }
    const focus = active ? active.address : "";
    const moved = focus !== seen.focus;
    return {
        first: first,
        focus: focus,
        focusSince: moved ? now : seen.focusSince,
        claimedWindows: claimedWindows,
        claimedFocus: moved ? false : seen.claimedFocus
    };
}

// entryOf joins dolphin on xcb and org.kde.dolphin on wayland
function matches(launch, win, entryOf) {
    if (!win)
        return false;
    if (launch.pid > 0 && win.pid === launch.pid)
        return true;
    for (const cls of [win["class"], win.initialClass]) {
        if (!cls)
            continue;
        if (launch.names.indexOf(lower(cls)) >= 0)
            return true;
        if (launch.entryId.length > 0 && entryOf(cls) === launch.entryId)
            return true;
    }
    return false;
}

// a window first seen after the launch began ends it, or focus landing on a match (an app may raise a window it has)
function settle(launches, windows, active, entryOf, now, ttl, seen) {
    const claimed = Object.assign({}, seen.claimedWindows);
    let focusClaimed = seen.claimedFocus;
    const waiting = [];
    for (const launch of launches) {
        if (now - launch.startedAt >= ttl)
            continue;
        let done = false;
        for (const win of windows) {
            if (claimed[win.address] || !(seen.first[win.address] > launch.startedAt) || win.mapped === false)
                continue;
            if (matches(launch, win, entryOf)) {
                claimed[win.address] = true;
                done = true;
                break;
            }
        }
        if (!done && active && !focusClaimed && !claimed[active.address] && seen.focusSince > launch.startedAt && matches(launch, active, entryOf)) {
            focusClaimed = true;
            done = true;
        }
        if (!done)
            waiting.push(launch);
    }
    return { waiting: waiting, seen: Object.assign({}, seen, { claimedWindows: claimed, claimedFocus: focusClaimed }) };
}
