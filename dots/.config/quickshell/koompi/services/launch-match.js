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

// spec: id, entryId, name, icon, startupClass, program, pid
function record(spec, windows, active, now) {
    const known = {};
    for (const win of windows)
        known[win.address] = true;
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
        known: known,
        activeAtStart: active ? active.address : "",
        startedAt: now
    };
}

// entryOf joins dolphin on xcb and org.kde.dolphin on wayland into one entry
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

function pidMapped(pid, windows) {
    return pid > 0 && windows.some(win => win.pid === pid);
}

// an app that raises the window it already has maps nothing, so focus moving to a match counts
function settle(launches, windows, active, entryOf, now, ttl) {
    const claimed = {};
    const waiting = [];
    for (const launch of launches) {
        if (now - launch.startedAt >= ttl)
            continue;
        let done = false;
        for (const win of windows) {
            if (claimed[win.address] || launch.known[win.address] || win.mapped === false)
                continue;
            if (matches(launch, win, entryOf)) {
                claimed[win.address] = true;
                done = true;
                break;
            }
        }
        if (!done && active && active.address !== launch.activeAtStart && !claimed[active.address] && matches(launch, active, entryOf)) {
            claimed[active.address] = true;
            done = true;
        }
        if (!done)
            waiting.push(launch);
    }
    return waiting;
}
