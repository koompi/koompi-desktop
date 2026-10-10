.pragma library

// One ranked Search list from several providers. Pure: the QML supplies rows
// (anything with a name and a key) and this decides which come first.

var SECTION_CAP = 5;
var TIER_EXACT = 100;
var TIER_PREFIX = 90;
var TIER_WORD = 80;
var TIER_INSIDE = 70;
var TIER_FUZZY = 50;

function lower(text) {
    return String(text || "").toLowerCase();
}

// How well a name answers the query: the order a person would rank them in.
function tierOf(name, query) {
    const n = lower(name).trim();
    const q = lower(query).trim();
    if (q === "" || n === "")
        return TIER_FUZZY;
    if (n === q)
        return TIER_EXACT;
    if (n.indexOf(q) === 0)
        return TIER_PREFIX;
    if (new RegExp("[\\s._/-]" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).test(n))
        return TIER_WORD;
    if (n.indexOf(q) >= 0)
        return TIER_INSIDE;
    return TIER_FUZZY;
}

function rowTier(row, query) {
    return row.tier > 0 ? row.tier : tierOf(row.name, query);
}

function indexOfKey(rows, key) {
    for (let i = 0; i < rows.length; i++) {
        if (rows[i].key === key)
            return i;
    }
    return -1;
}

// The Top Hit: the best first row among the sections allowed to supply one.
// A pinned key (the previous Top Hit for this same query) wins while it is
// still a candidate, so a row arriving late cannot take the top from under
// a hand already on Enter.
function pickTop(sections, query, pinnedKey) {
    let best = null;
    for (let s = 0; s < sections.length; s++) {
        const rows = sections[s].rows;
        if (!sections[s].top || rows.length === 0)
            continue;
        const pinned = pinnedKey ? indexOfKey(rows, pinnedKey) : -1;
        if (pinned >= 0)
            return { section: s, index: pinned };
        const t = rowTier(rows[0], query);
        if (best === null || t > best.tier)
            best = { section: s, index: 0, tier: t };
    }
    return best;
}

function takeRow(sections, hit) {
    const rows = sections[hit.section].rows;
    const row = rows[hit.index];
    sections[hit.section].rows = rows.slice(0, hit.index).concat(rows.slice(hit.index + 1));
    sections[hit.section].total += 1;
    return row;
}

function sectionRows(section, defaultCap, makeMore) {
    const rows = section.rows;
    const cap = section.cap || defaultCap;
    if (rows.length === 0)
        return [];
    rows[0].heading = section.title;
    if (rows.length <= cap)
        return rows;
    const total = rows.length + section.total;
    const hidden = rows[cap];
    const more = makeMore(total, hidden.scopePrefix || section.prefix || "", section.id);
    return rows.slice(0, cap).concat(more ? [more] : []);
}

// input: { query, sections: [{ id, title, rows, top, prefix }] in display
// order, topTitle, pinnedTop, cap, makeMore(total, prefix, id), tail: [rows] }
// -> { rows, topKey }
function blend(input) {
    const cap = input.cap || SECTION_CAP;
    const sections = input.sections.map(section => ({
        id: section.id,
        title: section.title,
        top: !!section.top,
        prefix: section.prefix,
        cap: section.cap,
        rows: section.rows.filter(Boolean),
        total: 0
    }));
    const hit = pickTop(sections, input.query, input.pinnedTop || "");
    const out = [];
    let topKey = "";
    if (hit) {
        const top = takeRow(sections, hit);
        top.heading = input.topTitle;
        topKey = top.key;
        out.push(top);
    }
    for (const section of sections) {
        for (const row of sectionRows(section, cap, input.makeMore))
            out.push(row);
    }
    for (const row of input.tail || [])
        out.push(row);
    return { rows: out, topKey: topKey };
}

// The rows best answering the query first, the providers' own order inside a
// tier. Array.sort is stable in Qt's engine, but the index makes it not matter.
function rankRows(rows, query) {
    return rows.map((row, index) => ({ row: row, index: index, tier: rowTier(row, query) }))
        .sort((a, b) => b.tier - a.tier || a.index - b.index)
        .map(entry => entry.row);
}

// Where the cursor goes when the list changes under it: on the same row if it
// is still there, else the nearest index that exists.
function stableIndex(prevKey, nextKeys, fallbackIndex) {
    const at = prevKey ? nextKeys.indexOf(prevKey) : -1;
    if (at >= 0)
        return at;
    return Math.max(0, Math.min(fallbackIndex || 0, nextKeys.length - 1));
}

// "translate hello" -> "hello"; "translate" -> ""; anything else -> null
function translateText(query, word) {
    const m = new RegExp("^" + word + "(?:\\s+([\\s\\S]*))?$", "i").exec(String(query || "").trim());
    return m ? (m[1] || "").trim() : null;
}

// qalc echoes a non-sum back or prints a sentence about it; a result worth a row
// is a different string from the query and has a digit in it
function mathWorthShowing(query, result) {
    const r = String(result || "").trim();
    if (r === "" || r === String(query).trim())
        return false;
    return /\d/.test(query) && /\d/.test(r);
}
