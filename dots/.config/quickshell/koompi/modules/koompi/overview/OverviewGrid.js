.pragma library

// The desk grid: n equal cells of one aspect ratio inside w x h, as large as
// they go. The last row is centred. Pure, so bun can test it.

function grid(n, w, h, aspect, gap) {
    let best = null;
    for (let cols = 1; cols <= Math.max(1, n); cols++) {
        const rows = Math.ceil(n / cols);
        const cellW = Math.min((w - gap * (cols - 1)) / cols, (h - gap * (rows - 1)) / rows * aspect);
        if (cellW <= 0)
            continue;
        if (!best || cellW > best.cellW + 1e-6)
            best = { cols: cols, rows: rows, cellW: cellW };
    }
    if (!best)
        return { cols: 1, rows: 1, cellW: 0, cellH: 0, n: n, gap: gap };
    best.cellH = best.cellW / aspect;
    best.n = n;
    best.gap = gap;
    best.x0 = (w - (best.cols * best.cellW + gap * (best.cols - 1))) / 2;
    best.y0 = (h - (best.rows * best.cellH + gap * (best.rows - 1))) / 2;
    return best;
}

function cell(g, i) {
    const row = Math.floor(i / g.cols);
    const col = i % g.cols;
    const inRow = row === g.rows - 1 ? g.n - row * g.cols : g.cols;
    const shift = (g.cols - inRow) * (g.cellW + g.gap) / 2;
    return {
        x: g.x0 + shift + col * (g.cellW + g.gap),
        y: g.y0 + row * (g.cellH + g.gap),
        w: g.cellW,
        h: g.cellH
    };
}

// arrow keys over the desks: left and right walk the reading order, up and down
// a row; down onto a short last row lands on its last desk. A move off the grid stays put.
function step(index, key, cols, n) {
    const last = Math.floor((n - 1) / cols);
    const row = Math.floor(index / cols);
    let next = index;
    if (key === "left")
        next = index - 1;
    else if (key === "right")
        next = index + 1;
    else if (key === "up")
        next = index - cols;
    else if (key === "down")
        next = row < last ? Math.min(index + cols, n - 1) : index;
    return next < 0 || next >= n ? index : next;
}

// a tile captures live frames only when it is big enough to read
function isLive(drawnWidth, threshold) {
    return drawnWidth >= threshold;
}
