#!/usr/bin/env bash
# The bar shows the workspaces in use. modules/common/functions/workspace-slots.js
# decides which desks to draw: occupied ones, the active one, and one empty "new
# desk" slot, always under their own fixed ids, and what each one shows: its app,
# else its number. Run under bun, no shell needed.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$REPO_ROOT/dots/.config/quickshell/koompi/modules/common/functions/workspace-slots.js"

[[ -f "$JS" ]] || { echo "FAIL: missing $JS" >&2; exit 1; }
command -v bun > /dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed '/^\.pragma /d' "$JS" > "$tmp/slots.js"
printf '\nexport { slots, fixed, face };\n' >> "$tmp/slots.js"

cat > "$tmp/check.js" <<'JS'
import { slots, fixed, face } from "./slots.js";
let bad = 0;
const eq = (name, got, want) => {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g !== w) { console.error(`FAIL: ${name}: got ${g}, want ${w}`); bad = 1; }
    else console.log(`ok   ${name}`);
};
eq("nothing open, desk 1 active", slots([], 1, 10), { ids: [1, 2], newId: 2 });
eq("one desk", slots([1], 1, 10), { ids: [1, 2], newId: 2 });
eq("1, 2 and 5 with 5 active keep their numbers", slots([1, 2, 5], 5, 10), { ids: [1, 2, 3, 5], newId: 3 });
eq("an empty active desk is drawn", slots([1, 2, 5], 7, 10), { ids: [1, 2, 3, 5, 7], newId: 3 });
eq("the new slot is the lowest free id", slots([1, 2, 3], 2, 10), { ids: [1, 2, 3, 4], newId: 4 });
eq("a full group has no new slot", slots([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 4, 10), { ids: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], newId: 0 });
eq("second group draws only its own ids", slots([2, 11, 14, 25], 14, 10), { ids: [11, 12, 14], newId: 12 });
eq("unsorted and repeated input", slots([5, 1, 5, 2], 1, 10), { ids: [1, 2, 3, 5], newId: 3 });
eq("special workspaces are ignored", slots([-98, 1], 1, 10), { ids: [1, 2], newId: 2 });
eq("fixed row of ten", fixed(3, 10).ids.length, 10);
eq("fixed row in the second group", fixed(13, 10).ids[0], 11);
eq("a desk with an app shows the app", face(false, true, true), "icon");
eq("an empty desk shows its number", face(false, false, true), "number");
eq("Super held shows numbers over apps", face(true, true, true), "number");
eq("the fixed row shows apps too", face(false, true, false), "icon");
eq("the fixed row keeps a dot for an empty desk", face(false, false, false), "dot");
process.exit(bad);
JS
cd "$tmp" && bun check.js
