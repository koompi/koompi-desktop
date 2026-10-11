.pragma library

// What a file row says under its name: where it lives and when it changed.

function baseName(path) {
    return path.slice(path.lastIndexOf("/") + 1);
}

function homeRelative(path, home) {
    if (home && path === home)
        return "~";
    return home && path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path;
}

function parentFolder(path, home) {
    const dir = path.slice(0, path.lastIndexOf("/")) || "/";
    return homeRelative(dir, home);
}

// `stat --printf '%Y\t%n\n'`, one line per file, as fd -X prints it
function parseStat(text) {
    const files = [];
    for (const line of String(text).split("\n")) {
        const tab = line.indexOf("\t");
        if (tab <= 0 || !/^\d+$/.test(line.slice(0, tab)))
            continue;
        const path = line.slice(tab + 1);
        if (path.length === 0)
            continue;
        files.push({ path: path, name: baseName(path), modified: Number(line.slice(0, tab)) * 1000 });
    }
    return files;
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// "Today 14:02", "Yesterday 09:10", "3 Oct", "3 Oct 2025". format(date, pattern)
// is Qt.formatDateTime in the shell, so the month names follow the locale.
function formatModified(ms, nowMs, format, labels) {
    if (!ms || ms <= 0)
        return "";
    const when = new Date(ms);
    const now = new Date(nowMs);
    if (sameDay(when, now))
        return labels.today + " " + format(when, "HH:mm");
    const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    if (sameDay(when, yesterday))
        return labels.yesterday + " " + format(when, "HH:mm");
    return format(when, when.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
}

// folder, then date when there is one: "~/Documents · Today 14:02"
function describe(path, ms, home, nowMs, format, labels) {
    const when = formatModified(ms, nowMs, format, labels);
    const folder = parentFolder(path, home);
    return when === "" ? folder : folder + "  ·  " + when;
}
