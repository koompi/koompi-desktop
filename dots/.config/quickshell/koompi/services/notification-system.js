.pragma library

function isSender(senders, appName, appHint) {
    return senders.includes(appName) || (appHint !== "" && senders.includes(appHint));
}

// critical is held to normal for system notices
function heldUrgency(isSystem, urgency, critical, normal) {
    return isSystem && urgency === critical ? normal : urgency;
}

// one row per summary: how many, the newest body, and every id, so one clear takes them all
function foldRows(list) {
    const rows = {};
    list.forEach((notif) => {
        const row = rows[notif.summary] || (rows[notif.summary] = { summary: notif.summary, body: "", count: 0, ids: [], time: 0 });
        row.count++;
        row.ids.push(notif.notificationId);
        if (notif.time >= row.time) {
            row.time = notif.time;
            row.body = notif.body;
        }
    });
    return Object.values(rows).sort((a, b) => b.time - a.time);
}
