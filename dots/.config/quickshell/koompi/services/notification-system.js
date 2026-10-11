.pragma library

function isSender(senders, appName, appHint) {
    return senders.includes(appName) || (appHint !== "" && senders.includes(appHint));
}

// critical is held to normal for system notices
function heldUrgency(isSystem, urgency, critical, normal) {
    return isSystem && urgency === critical ? normal : urgency;
}

// a notice about a file (a screenshot, a recording) names it as its whole body; "" when it does not
function filePath(body) {
    const text = (body || "").trim().replace(/^file:\/\//, "");
    return /^\/[^\n<>]+$/.test(text) ? text : "";
}

// one row per summary: how many, the newest body, and every id, so one clear takes them all.
// Notices about files are not folded: nine screenshots are nine files, each with its own path.
function foldRows(list) {
    const rows = {};
    list.forEach((notif) => {
        const path = filePath(notif.body);
        const key = path ? notif.summary + "\n" + path : notif.summary;
        const row = rows[key] || (rows[key] = { summary: notif.summary, body: "", path: path, count: 0, ids: [], time: 0 });
        row.count++;
        row.ids.push(notif.notificationId);
        if (notif.time >= row.time) {
            row.time = notif.time;
            row.body = notif.body;
        }
    });
    return Object.values(rows).sort((a, b) => b.time - a.time);
}
