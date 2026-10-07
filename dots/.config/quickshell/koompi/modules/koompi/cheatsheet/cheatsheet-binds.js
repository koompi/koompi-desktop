.pragma library

// Hyprland key name, lower-cased -> what is printed on the key. Unknown names render as themselves.
const KEYS = {
    "grave": "`", "backslash": "\\", "slash": "/", "semicolon": ";", "apostrophe": "'",
    "comma": ",", "period": ".", "minus": "-", "equal": "=", "hash": "#",
    "bracketleft": "[", "bracketright": "]",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "page_up": "PgUp", "page_down": "PgDn", "prior": "PgUp", "next": "PgDn",
    "return": "Enter", "escape": "Esc", "space": "Space", "tab": "Tab",
    "backspace": "Backspace", "delete": "Del", "insert": "Ins", "home": "Home", "end": "End",
    "print": "PrtSc",
    "mouse:272": "Left click", "mouse:273": "Right click", "mouse:274": "Middle click",
    "mouse:275": "Back", "mouse:276": "Forward",
    // hyprland 0.56 onAxisEvent: a positive delta, scrolling down, is mouse_down
    "mouse_up": "Scroll ↑", "mouse_down": "Scroll ↓",
    "xf86audioraisevolume": "Vol +", "xf86audiolowervolume": "Vol -",
    "xf86audiomute": "Mute", "xf86audiomicmute": "Mic mute",
    "xf86audioplay": "Play", "xf86audiopause": "Pause",
    "xf86audionext": "Next", "xf86audioprev": "Prev",
    "xf86monbrightnessup": "Bright +", "xf86monbrightnessdown": "Bright -",
    "code:201": "AI",
    // Super + Super_L is the chord Super alone
    "super_l": "", "super_r": "",
};

const DIRECTIONS = ["left", "right", "up", "down"];
const DIGITS = "1234567890";
const MARK = "\u0001";
// Qt's and Windows' order, on every chord whatever order the bind lists them in
const MODS = ["super", "ctrl", "alt", "shift", "caps", "mod2", "mod3", "mod5"];

function byModOrder(mods) {
    const rank = mod => {
        const at = MODS.indexOf(String(mod).toLowerCase());
        return at < 0 ? MODS.length : at;
    };
    return mods.map((mod, index) => ({ mod: mod, index: index }))
        .sort((a, b) => rank(a.mod) - rank(b.mod) || a.index - b.index)
        .map(o => o.mod);
}

function makeLabeler(overrides) {
    const table = Object.assign({}, KEYS);
    for (const name of Object.keys(overrides || {}))
        table[name.toLowerCase()] = overrides[name];
    return name => {
        const lower = String(name).toLowerCase();
        return Object.prototype.hasOwnProperty.call(table, lower) ? table[lower] : String(name);
    };
}

function keyLabel(name, overrides) {
    return makeLabeler(overrides)(name);
}

function splitDescription(description) {
    const colon = description.indexOf(":");
    if (colon < 0)
        return { category: "", text: description.trim() };
    return { category: description.substring(0, colon), text: description.substring(colon + 1).trim() };
}

// `want` is the number or direction a description has to name for this key to be that member
function keyKind(key) {
    const lower = key.toLowerCase();
    if (/^[0-9]$/.test(lower))
        return { type: "number", want: Number(lower), sub: "digits" };
    if (DIRECTIONS.includes(lower))
        return { type: "direction", want: lower, sub: "arrows" };
    if (lower === "bracketleft" || lower === "bracketright")
        return { type: "direction", want: lower.substring("bracket".length), sub: "brackets" };
    return null;
}

function findToken(text, type, want) {
    const pattern = type === "number" ? /\b\d+\b/g : /\b(left|right|up|down)\b/gi;
    let match;
    while ((match = pattern.exec(text)) !== null) {
        const value = type === "number" ? Number(match[0]) : match[0].toLowerCase();
        const agrees = type === "number" ? value >= 1 && value <= 10 && value % 10 === want : value === want;
        if (want === undefined || agrees)
            return { start: match.index, end: match.index + match[0].length, value: value };
    }
    return null;
}

// The family an entry's description belongs to: the text with the varying number or
// direction cut out. `literal` is whether the key is the member the description names.
function classify(entry) {
    const kind = keyKind(entry.key);
    const types = kind ? [kind.type, kind.type === "number" ? "direction" : "number"] : ["direction", "number"];
    for (const type of types) {
        const exact = kind && kind.type === type ? findToken(entry.text, type, kind.want) : null;
        const token = exact || findToken(entry.text, type, undefined);
        if (!token)
            continue;
        const template = entry.text.substring(0, token.start) + MARK + entry.text.substring(token.end);
        return { group: type + "|" + template, type: type, template: template, value: token.value,
                 literal: exact !== null, sub: exact !== null ? kind.sub : "" };
    }
    return null;
}

// a family needs two different members, each one the member its own key names,
// or a row could claim a chord does something it does not
function isFamily(members) {
    return new Set(members.map(m => m.family.value)).size >= 2 && members.every(m => m.family.literal);
}

function span(values, isNext) {
    const run = values.length >= 3 && values.every((v, i) => i === 0 || isNext(values[i - 1], v));
    return run ? values[0] + "–" + values[values.length - 1] : values.join("/");
}

function joinArrows(labels) {
    return labels.every(label => label.length === 1 && "←→↑↓".includes(label)) ? labels.join("") : labels.join("/");
}

function familyText(members) {
    const first = members[0].family;
    const values = [...new Set(members.map(m => m.family.value))];
    if (first.type === "number")
        return first.template.replace(MARK, span(values.sort((a, b) => a - b), (a, b) => b === a + 1));
    return first.template.replace(MARK, values.sort((a, b) => DIRECTIONS.indexOf(a) - DIRECTIONS.indexOf(b)).join("/"));
}

// "Super + 1–0" and "Super + ←→↑↓" are each one chord per (modifiers, kind of key)
function familyItems(members, label) {
    const isNumber = members[0].family.type === "number";
    const rank = key => isNumber ? DIGITS.indexOf(key) : DIRECTIONS.indexOf(key.toLowerCase().replace("bracket", ""));
    const text = familyText(members);
    const chords = new Map();
    for (const member of members) {
        const id = member.family.sub + "|" + member.entry.mods.join("+");
        if (!chords.has(id)) chords.set(id, []);
        chords.get(id).push(member.entry);
    }
    return [...chords.values()].map(entries => {
        const keys = entries.map(e => e.key).sort((a, b) => rank(a) - rank(b));
        const key = isNumber ? span(keys, (a, b) => rank(b) === rank(a) + 1) : joinArrows(keys.map(label));
        return { text: text, entries: entries, key: key };
    });
}

function toItems(entries, label) {
    const members = entries.map(entry => ({ entry: entry, family: classify(entry) }));
    const groups = new Map();
    for (const member of members) {
        if (!member.family) continue;
        if (!groups.has(member.family.group)) groups.set(member.family.group, []);
        groups.get(member.family.group).push(member);
    }
    const items = [];
    const done = new Set();
    for (const member of members) {
        const group = member.family ? groups.get(member.family.group) : null;
        if (!group || !isFamily(group)) {
            items.push({ text: member.entry.text, entries: [member.entry], key: label(member.entry.key) });
        } else if (!done.has(member.family.group)) {
            done.add(member.family.group);
            items.push(...familyItems(group, label));
        }
    }
    return items;
}

// The modifier keycaps of a chord. A plane-16 mark (the KOOMPI star) is drawn by a
// font that has no letters, so it gets a keycap to itself.
function keycaps(mods, split) {
    if (split)
        return mods;
    const caps = [];
    let run = [];
    for (const mod of mods) {
        if (mod.length > 0 && mod.codePointAt(0) >= 0x100000) {
            if (run.length > 0) caps.push(run.join(" "));
            run = [];
            caps.push(mod);
        } else {
            run.push(mod);
        }
    }
    if (run.length > 0) caps.push(run.join(" "));
    return caps;
}

function chordOf(item, label) {
    const mods = item.entries[0].mods;
    const runner = item.entries.find(e => e.dispatchable);
    return { mods: mods.map(label), modCount: mods.length, key: item.key,
             ids: item.entries.map(e => e.id), run: runner ? runner.id : -1 };
}

// Rows for one category ("" is the binds without one), in order of first
// appearance. Binds that share a description are one row with every chord,
// fewest modifiers first. binds: { id, mods, key, description, dispatchable }.
function buildRows(binds, category, overrides) {
    const label = makeLabeler(overrides);
    const entries = [];
    for (const bind of binds) {
        const parts = splitDescription(bind.description || "");
        if (parts.text.length === 0 || parts.category !== category)
            continue;
        entries.push({ id: bind.id, mods: byModOrder(bind.mods), key: bind.key, text: parts.text, dispatchable: bind.dispatchable });
    }
    const rows = new Map();
    for (const item of toItems(entries, label)) {
        if (!rows.has(item.text)) rows.set(item.text, { text: item.text, chords: [] });
        const chords = rows.get(item.text).chords;
        const chord = chordOf(item, label);
        const same = chords.find(c => c.mods.join("+") === chord.mods.join("+") && c.key === chord.key);
        if (!same) {
            chords.push(chord);
        } else {
            same.ids = same.ids.concat(chord.ids);
            if (same.run < 0) same.run = chord.run;
        }
    }
    return [...rows.values()].map(row => {
        const ordered = row.chords.map((chord, index) => ({ chord: chord, index: index }))
            .sort((a, b) => a.chord.modCount - b.chord.modCount || a.index - b.index)
            .map(o => o.chord);
        const runner = ordered.find(c => c.run >= 0);
        return { text: row.text, chords: ordered, ids: ordered.reduce((all, c) => all.concat(c.ids), []), runId: runner ? runner.run : -1 };
    });
}
