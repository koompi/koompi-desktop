.pragma library

// Which desks a strip draws. Ids are fixed: desk 5 is always Super+5, so a gap
// stays a gap and nothing is renumbered. Pure, shared by the bar and the overview.

function groupStart(activeId, groupSize) {
    return Math.floor((activeId - 1) / groupSize) * groupSize + 1;
}

// ids: ascending ids to draw, the occupied ones, the active one and newId.
// newId: the lowest id of the group not otherwise drawn, the empty "new desk"
// slot, or 0 when the group is full.
function slots(occupiedIds, activeId, groupSize) {
    const start = groupStart(activeId, groupSize);
    const end = start + groupSize - 1;
    const seen = {};
    const ids = [];
    const add = id => {
        if (id < start || id > end || seen[id]) return;
        seen[id] = true;
        ids.push(id);
    };
    (occupiedIds || []).forEach(add);
    add(activeId);
    let newId = 0;
    for (let id = start; id <= end; id++) {
        if (!seen[id]) { newId = id; break; }
    }
    if (newId) ids.push(newId);
    ids.sort((a, b) => a - b);
    return { ids: ids, newId: newId };
}

// the whole group, as the bar drew it before it followed use
function fixed(activeId, groupSize) {
    const start = groupStart(activeId, groupSize);
    const ids = [];
    for (let i = 0; i < groupSize; i++) ids.push(start + i);
    return { ids: ids, newId: 0 };
}
