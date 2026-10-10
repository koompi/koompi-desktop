#!/usr/bin/env bash
# The overview draws one cell per desk, as large as the area allows. OverviewGrid.js
# lays the cells out; run under bun, no shell needed.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$REPO_ROOT/dots/.config/quickshell/koompi/modules/koompi/overview/OverviewGrid.js"

[[ -f "$JS" ]] || { echo "FAIL: missing $JS" >&2; exit 1; }
command -v bun > /dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed '/^\.pragma /d' "$JS" > "$tmp/grid.js"
printf '\nexport { grid, cell, step, isLive };\n' >> "$tmp/grid.js"

cat > "$tmp/check.js" <<'JS'
import { grid, cell, step, isLive } from "./grid.js";
let bad = 0;
const fail = msg => { console.error(`FAIL: ${msg}`); bad = 1; };
const areas = [[1800, 1000, 1.6], [1300, 640, 16 / 9], [900, 1400, 1.25], [1200, 1200, 2]];
const gap = 16;
for (const [w, h, aspect] of areas) {
    for (let n = 1; n <= 12; n++) {
        const g = grid(n, w, h, aspect, gap);
        const rects = Array.from({ length: n }, (_, i) => cell(g, i));
        const tag = `n=${n} ${w}x${h}`;
        rects.forEach((r, i) => {
            if (r.x < -0.01 || r.y < -0.01 || r.x + r.w > w + 0.01 || r.y + r.h > h + 0.01) fail(`${tag}: cell ${i} leaves the area`);
            if (Math.abs(r.w / r.h - aspect) / aspect > 0.01) fail(`${tag}: cell ${i} lost its aspect`);
            for (let j = 0; j < i; j++) {
                const o = rects[j];
                if (r.x < o.x + o.w - 0.01 && o.x < r.x + r.w - 0.01 && r.y < o.y + o.h - 0.01 && o.y < r.y + r.h - 0.01) fail(`${tag}: cells ${i} and ${j} overlap`);
            }
        });
        for (let cols = 1; cols <= n; cols++) {
            const rows = Math.ceil(n / cols);
            const alt = Math.min((w - gap * (cols - 1)) / cols, (h - gap * (rows - 1)) / rows * aspect);
            if (alt > g.cellW + 0.01) fail(`${tag}: ${cols} columns would draw larger cells`);
        }
        if (n === 1 && g.cellW < 0.6 * w && g.cellH < 0.6 * h) fail(`${tag}: one desk should fill most of the area`);
    }
}
const g5 = grid(5, 1800, 1000, 1.6, gap);
if (g5.cols === 3 && !(cell(g5, 4).x > cell(g5, 0).x)) fail("the short last row is not centred");

const eq = (name, got, want) => { if (got !== want) fail(`${name}: got ${got}, want ${want}`); };
eq("right", step(0, "right", 3, 5), 1);
eq("right walks on to the next row", step(2, "right", 3, 5), 3);
eq("right stops at the last desk", step(4, "right", 3, 5), 4);
eq("left walks back to the row above", step(3, "left", 3, 5), 2);
eq("left stops at the first desk", step(0, "left", 3, 5), 0);
eq("down", step(1, "down", 3, 5), 4);
eq("down onto a short last row lands on its last desk", step(2, "down", 3, 5), 4);
eq("down from the last row stays", step(4, "down", 3, 5), 4);
eq("up from the first row stays", step(1, "up", 3, 5), 1);
eq("up", step(4, "up", 3, 5), 1);
eq("unknown key stays", step(1, "home", 3, 5), 1);
eq("a big tile is live", isLive(320, 320), true);
eq("a small tile is not", isLive(319.9, 320), false);
if (!bad) console.log("ok   overview grid: 1 to 12 desks fit, keep aspect, never overlap; arrows and the live rule");
process.exit(bad);
JS
cd "$tmp" && bun check.js
